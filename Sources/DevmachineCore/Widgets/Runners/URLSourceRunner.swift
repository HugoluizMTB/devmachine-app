import Foundation

/// A GET, so a URL widget can be tested without the network.
public protocol WidgetHTTPClient: Sendable {
    func get(_ url: URL, timeout: TimeInterval) async throws -> (status: Int, body: Data)
}

/// GET only. A status widget wants the code whatever it is; text and JSON
/// need a 2xx answer.
public struct URLSourceRunner: SourceRunner {
    let client: any WidgetHTTPClient
    let clock: @Sendable () -> Date

    public init(client: any WidgetHTTPClient, clock: @escaping @Sendable () -> Date = Date.init) {
        self.client = client
        self.clock = clock
    }

    /// The address a fetch or a web view loads, filled from the same inputs
    /// and context; anything but http(s) is refused.
    public static func address(of resolved: ResolvedSource, context: [String: String]) throws -> URL {
        try resolve(resolved, context: context).url
    }

    private static func resolve(_ resolved: ResolvedSource, context: [String: String]) throws -> (source: URLSource, url: URL) {
        guard case let .url(source) = try SourceFailure.refusing({ try resolved.resolved(context: context) }) else {
            throw SourceError.cannotStart("not a url source")
        }
        guard let url = URL(string: source.url), PreviewURLPolicy.isWeb(url) else {
            throw SourceError.unreadable("\(source.url) is not a web address")
        }
        return (source, url)
    }

    public func fetch(_ request: SourceRunRequest) async throws -> SourceRunResult {
        if let blocked = try SourceApprovalGate.blocked(request) { return .needsApproval(blocked) }
        let (source, url) = try Self.resolve(request.source, context: request.context)
        let started = clock()
        let answer: (status: Int, body: Data)
        do {
            answer = try await client.get(url, timeout: source.timeout)
        } catch let error as URLError where error.code == .timedOut {
            throw SourceError.timedOut(source.timeout)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SourceError.http(error.localizedDescription)
        }
        let latency = clock().timeIntervalSince(started)
        if source.parse == .status { return .output(.status(code: answer.status, latency: latency)) }
        guard (200..<300).contains(answer.status) else { throw SourceError.http("the page answered HTTP \(answer.status)") }
        guard answer.body.count <= OutputParser.maxBytes else { throw SourceError.unreadable("the page is larger than 1 MB") }
        return .output(try SourceOutputs.parse(answer.body, as: source.parse))
    }
}
