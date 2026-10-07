import DevmachineCore
import Foundation

enum WidgetSourceLive {
    static func runners() -> SourceRunners {
        let launcher = FoundationProcessLauncher()
        let environment = SourceRunEnvironment(
            cli: {
                let cli = try DevmachineCLI.resolve()
                return CLIInvocationContext(executable: cli.executable, environment: cli.environment())
            },
            localEnvironment: ProcessInfo.processInfo.environment,
            home: NSHomeDirectory())
        return SourceRunners(
            command: CommandSourceRunner(launcher: launcher, environment: environment),
            url: URLSourceRunner(client: URLSessionWidgetClient()),
            prompt: PromptSourceRunner(launcher: launcher, environment: environment, locateHarness: { harness in
                let name = HarnessRegistry.builtIn.adapter(for: HarnessID(rawValue: harness.rawValue))?.executableName
                    ?? harness.rawValue
                return SystemExecutableLocator().executable(named: name)?.path
            }),
            session: SessionSourceRunner(launcher: launcher, environment: environment, zmxPath: { LocalTools.zmxPath() }),
            launcher: launcher,
            environment: environment,
            packageProvider: PackageProviderRunner(launcher: launcher, environment: environment))
    }
}

enum WidgetHTTPError: LocalizedError, Equatable {
    case tooLarge(Int)
    case redirectRefused(String)

    var errorDescription: String? {
        switch self {
        case let .tooLarge(limit):
            return limit == OutputParser.maxBytes ? "the page is larger than 1 MB" : "the page is larger than \(limit) bytes"
        case let .redirectRefused(scheme):
            return "the page redirected to a \(scheme): address, which is not a web page"
        }
    }
}

private final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var refusedScheme: String?

    var refused: String? { lock.withLock { refusedScheme } }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard URLSessionWidgetClient.followsRedirect(to: request.url) else {
            lock.withLock { refusedScheme = request.url?.scheme?.lowercased() ?? "unknown" }
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

/// No cookies, no cache: a widget only reads a page. The body stops at the
/// limit while it downloads, so a huge page never fills memory first.
struct URLSessionWidgetClient: WidgetHTTPClient {
    private static let chunkSize = 64 * 1024

    private let session: URLSession
    private let maxBytes: Int

    init(configuration: URLSessionConfiguration = URLSessionWidgetClient.defaultConfiguration(), maxBytes: Int = OutputParser.maxBytes) {
        session = URLSession(configuration: configuration)
        self.maxBytes = maxBytes
    }

    static func defaultConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return configuration
    }

    static func followsRedirect(to url: URL?) -> Bool {
        url.map(PreviewURLPolicy.isWeb) ?? false
    }

    /// `timeoutInterval` only bounds the wait between packets, so the whole
    /// request also races the widget's own timeout.
    func get(_ url: URL, timeout: TimeInterval) async throws -> (status: Int, body: Data) {
        try await withThrowingTaskGroup(of: (status: Int, body: Data).self) { group in
            group.addTask { try await download(url, timeout: timeout) }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw URLError(.unknown) }
            return first
        }
    }

    private func download(_ url: URL, timeout: TimeInterval) async throws -> (status: Int, body: Data) {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        let redirects = RedirectGuard()
        let (bytes, response) = try await session.bytes(for: request, delegate: redirects)
        if let scheme = redirects.refused {
            bytes.task.cancel()
            throw WidgetHTTPError.redirectRefused(scheme)
        }
        guard let http = response as? HTTPURLResponse else {
            bytes.task.cancel()
            throw URLError(.badServerResponse)
        }
        if response.expectedContentLength > Int64(maxBytes) {
            bytes.task.cancel()
            throw WidgetHTTPError.tooLarge(maxBytes)
        }
        var body = Data()
        var chunk: [UInt8] = []
        chunk.reserveCapacity(Self.chunkSize)
        for try await byte in bytes {
            guard body.count + chunk.count < maxBytes else {
                bytes.task.cancel()
                throw WidgetHTTPError.tooLarge(maxBytes)
            }
            chunk.append(byte)
            guard chunk.count == Self.chunkSize else { continue }
            body.append(contentsOf: chunk)
            chunk.removeAll(keepingCapacity: true)
        }
        body.append(contentsOf: chunk)
        return (http.statusCode, body)
    }
}
