import XCTest
import DevmachineCore
@testable import DevmachineApp

private final class ViewerRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var output: (stdout: String, stderr: String, exitCode: Int32)
    private var commands: [String] = []

    init(stdout: String, stderr: String = "", exitCode: Int32 = 0) {
        self.output = (stdout, stderr, exitCode)
    }

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        try runCapturing(executable: executable, args: args, environment: environment).stdout
    }

    func runCapturing(executable: String, args: [String], environment: [String: String]?) throws
        -> (stdout: String, stderr: String, exitCode: Int32) {
        lock.lock()
        commands.append(args.last ?? "")
        lock.unlock()
        return output
    }

    var lastCommand: String? {
        lock.lock()
        defer { lock.unlock() }
        return commands.last
    }
}

@MainActor
final class FileViewerStoreTests: XCTestCase {
    private func payload(_ text: String) -> String {
        let data = Data(text.utf8)
        return "\(data.count)\u{1e}" + data.base64EncodedString()
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !condition() {
            if Date() > deadline { return XCTFail("condition never became true") }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    func testReadingAFileFromAHost() async throws {
        let ssh = ViewerRunner(stdout: payload("print(1)\n"))
        let store = FileViewerStore(host: HostRunner(remote: RemoteService(runner: ssh)))

        store.open(.remote(alias: "acme-devmachine", session: "dash"), path: "/repo/main.swift")
        try await waitUntil { store.preview != nil }

        XCTAssertEqual(store.preview?.kind, .code(language: "swift"))
        XCTAssertEqual(store.preview?.text, "print(1)\n")
        XCTAssertNil(store.errorText)
        XCTAssertFalse(store.isLoading)
    }

    func testReadingAFileOnThisMacRunsHere() async throws {
        let local = ViewerRunner(stdout: payload("# Title\n"))
        let ssh = ViewerRunner(stdout: "")
        let store = FileViewerStore(
            host: HostRunner(remote: RemoteService(runner: ssh), local: local))

        store.open(.local(session: "acme", path: "/repo"), path: "/repo/README.md")
        try await waitUntil { store.preview != nil }

        XCTAssertEqual(store.preview?.kind, .markdown)
        XCTAssertNil(ssh.lastCommand)
        XCTAssertTrue(try XCTUnwrap(local.lastCommand).contains("/repo/README.md"))
    }

    func testAFailedReadReportsTheReason() async throws {
        let ssh = ViewerRunner(stdout: "", stderr: "cat: no such file", exitCode: 1)
        let store = FileViewerStore(host: HostRunner(remote: RemoteService(runner: ssh)))

        store.open(.remote(alias: "acme-devmachine", session: "dash"), path: "/repo/gone.swift")
        try await waitUntil { store.errorText != nil }

        XCTAssertEqual(store.errorText, "cat: no such file")
        XCTAssertNil(store.preview)
    }

    func testOpeningAnotherFileClearsWhatWasOnScreen() async throws {
        let ssh = ViewerRunner(stdout: payload("print(1)\n"))
        let store = FileViewerStore(host: HostRunner(remote: RemoteService(runner: ssh)))

        store.open(.remote(alias: "acme-devmachine", session: "dash"), path: "/repo/main.swift")
        try await waitUntil { store.preview != nil }
        store.showsSource = true

        store.open(.remote(alias: "acme-devmachine", session: "dash"), path: "/repo/other.swift")

        XCTAssertNil(store.preview)
        XCTAssertFalse(store.showsSource)
        XCTAssertEqual(store.path, "/repo/other.swift")
    }
}
