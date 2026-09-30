import XCTest
@testable import DevmachineApp
@testable import DevmachineCore

@MainActor
final class PaneUploadStoreTests: XCTestCase {
    private let kind = TerminalKind.remote(alias: "acme-devmachine", session: "dash")

    private final class Log: @unchecked Sendable {
        var uploaded: [String] = []
        var typed: [String] = []
    }

    private func store(
        log: Log, failOn: String? = nil, typed: XCTestExpectation? = nil
    ) -> PaneUploadStore {
        PaneUploadStore(
            upload: { job, _, policy, progress in
                if job.originalName == failOn { throw FileUploadService.Failure.transferFailed("disk full") }
                log.uploaded.append(job.originalName)
                progress(Int(job.size))
                return "/home/alice/\(policy.directory)/\(job.name.fileName)"
            },
            policy: { _ in .appManaged },
            type: { text, _ in
                log.typed.append(text)
                typed?.fulfill()
            },
            now: { Date(timeIntervalSince1970: 1_790_778_612) })
    }

    private func entry(_ name: String, size: Int64 = 3, directory: Bool = false) -> DroppedEntry {
        DroppedEntry(url: URL(fileURLWithPath: "/Users/alice/Desktop/\(name)"), isDirectory: directory, size: size)
    }

    func testDroppedFilesAreSentInOrderAndTheirPathsTypedTogether() async {
        let log = Log()
        let typed = expectation(description: "typed")
        let store = store(log: log, typed: typed)

        store.receive([entry("b.txt"), entry("a file.png")], on: kind)
        await fulfillment(of: [typed], timeout: 2)

        XCTAssertEqual(log.uploaded, ["b.txt", "a file.png"])
        XCTAssertEqual(log.typed.count, 1)
        XCTAssertTrue(log.typed[0].hasPrefix("/home/alice/.cache/devmachine-app/uploads/b-2026093"))
        XCTAssertTrue(log.typed[0].contains(" '/home/alice/.cache/devmachine-app/uploads/a file-2026093"))
        XCTAssertTrue(log.typed[0].hasSuffix(".png' "))
        XCTAssertNil(store.phases[kind])
    }

    func testAFolderIsRefusedWithAMessageAndNothingIsSent() {
        let log = Log()
        let store = store(log: log)

        store.receive([entry("a.txt"), entry("photos", directory: true)], on: kind)

        guard case let .failed(state)? = store.phases[kind] else { return XCTFail("not refused") }
        XCTAssertEqual(state.title, "Folders can\u{2019}t be dropped yet \u{2014} drop the files inside")
        XCTAssertTrue(log.uploaded.isEmpty)
    }

    func testALargeDropWaitsForConfirmation() async {
        let log = Log()
        let typed = expectation(description: "typed")
        let store = store(log: log, typed: typed)

        store.receive([entry("big.iso", size: FileUpload.confirmationThreshold + 1)], on: kind)
        guard case .confirming? = store.phases[kind] else { return XCTFail("did not ask") }
        XCTAssertTrue(log.uploaded.isEmpty)

        store.confirm(kind)
        await fulfillment(of: [typed], timeout: 2)
        XCTAssertEqual(log.uploaded, ["big.iso"])
    }

    func testCancellingALargeDropSendsNothing() {
        let log = Log()
        let store = store(log: log)

        store.receive([entry("big.iso", size: FileUpload.confirmationThreshold + 1)], on: kind)
        store.dismiss(kind)

        XCTAssertNil(store.phases[kind])
        XCTAssertTrue(log.uploaded.isEmpty)
    }

    func testAFailedUploadShowsTheErrorAndTypesNothing() async throws {
        let log = Log()
        let store = store(log: log, failOn: "a.txt")

        store.receive([entry("a.txt")], on: kind)
        for _ in 0..<100 {
            if case .failed? = store.phases[kind] { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        guard case let .failed(state)? = store.phases[kind] else { return XCTFail("no error shown") }
        XCTAssertEqual(state.title, "Couldn\u{2019}t upload a.txt")
        XCTAssertEqual(state.details, "disk full")
        XCTAssertTrue(log.typed.isEmpty)
    }

    func testAPastedScreenshotGetsAPastedImageName() async {
        let log = Log()
        let typed = expectation(description: "typed")
        let store = store(log: log, typed: typed)

        store.receive(.bitmap(Data([1, 2, 3])), on: kind)
        await fulfillment(of: [typed], timeout: 2)

        XCTAssertTrue(log.typed[0].contains("/uploads/pasted-image-2026093"))
        XCTAssertTrue(log.typed[0].hasSuffix(".png "))
    }
}
