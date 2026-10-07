import XCTest
@testable import DevmachineApp
@testable import DevmachineCore

private final class StubHTTPProtocol: URLProtocol, @unchecked Sendable {
    enum Reply {
        case body(status: Int, chunks: [Data])
        case redirect(to: String)
        case silence
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var replies: [String: Reply] = [:]

    static func set(_ url: String, _ reply: Reply) {
        lock.withLock { replies[url] = reply }
    }

    static func reset() {
        lock.withLock { replies.removeAll() }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let reply = Self.lock.withLock({ Self.replies[url.absoluteString] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        switch reply {
        case let .body(status, chunks):
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            chunks.forEach { client?.urlProtocol(self, didLoad: $0) }
            client?.urlProtocolDidFinishLoading(self)
        case let .redirect(target):
            let response = HTTPURLResponse(
                url: url, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": target])!
            let next = URLRequest(url: URL(string: target)!)
            client?.urlProtocol(self, wasRedirectedTo: next, redirectResponse: response)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        case .silence:
            break
        }
    }

    override func stopLoading() {}
}

final class URLSessionWidgetClientTests: XCTestCase {
    override func tearDown() {
        StubHTTPProtocol.reset()
    }

    private func client(maxBytes: Int = 1_048_576) -> URLSessionWidgetClient {
        let configuration = URLSessionWidgetClient.defaultConfiguration()
        configuration.protocolClasses = [StubHTTPProtocol.self]
        return URLSessionWidgetClient(configuration: configuration, maxBytes: maxBytes)
    }

    func testAPageComesBackWithItsStatusAndBody() async throws {
        StubHTTPProtocol.set("https://example.com/ok", .body(status: 200, chunks: [Data("he".utf8), Data("llo".utf8)]))
        let answer = try await client().get(URL(string: "https://example.com/ok")!, timeout: 5)
        XCTAssertEqual(answer.status, 200)
        XCTAssertEqual(String(decoding: answer.body, as: UTF8.self), "hello")
    }

    func testABodyOverTheLimitStopsTheDownload() async {
        let chunk = Data(repeating: 0x61, count: 8)
        StubHTTPProtocol.set("https://example.com/big", .body(status: 200, chunks: [chunk, chunk, chunk]))
        do {
            _ = try await client(maxBytes: 10).get(URL(string: "https://example.com/big")!, timeout: 5)
            XCTFail("a body over the limit came back")
        } catch {
            XCTAssertEqual(error as? WidgetHTTPError, .tooLarge(10))
            XCTAssertEqual(error.localizedDescription, "the page is larger than 10 bytes")
        }
    }

    func testAWebRedirectIsFollowed() async throws {
        StubHTTPProtocol.set("https://example.com/old", .redirect(to: "https://example.com/new"))
        StubHTTPProtocol.set("https://example.com/new", .body(status: 200, chunks: [Data("moved".utf8)]))
        let answer = try await client().get(URL(string: "https://example.com/old")!, timeout: 5)
        XCTAssertEqual(String(decoding: answer.body, as: UTF8.self), "moved")
    }

    func testARedirectOffTheWebIsRefused() async {
        StubHTTPProtocol.set("https://example.com/sneaky", .redirect(to: "file:///etc/hosts"))
        do {
            _ = try await client().get(URL(string: "https://example.com/sneaky")!, timeout: 5)
            XCTFail("a redirect to a file was followed")
        } catch {
            XCTAssertEqual(error as? WidgetHTTPError, .redirectRefused("file"))
        }
    }

    func testAPageThatNeverAnswersTimesOut() async {
        StubHTTPProtocol.set("https://example.com/slow", .silence)
        do {
            _ = try await client().get(URL(string: "https://example.com/slow")!, timeout: 0.1)
            XCTFail("a silent page answered")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
        }
    }

    func testOnlyWebAddressesAreFollowed() {
        XCTAssertTrue(URLSessionWidgetClient.followsRedirect(to: URL(string: "http://example.com")))
        XCTAssertTrue(URLSessionWidgetClient.followsRedirect(to: URL(string: "HTTPS://example.com")))
        XCTAssertFalse(URLSessionWidgetClient.followsRedirect(to: URL(string: "ftp://example.com")))
        XCTAssertFalse(URLSessionWidgetClient.followsRedirect(to: nil))
    }
}
