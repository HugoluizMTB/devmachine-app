import XCTest
@testable import DevmachineCore

final class FileUploadTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let date = Date(timeIntervalSince1970: 1_790_778_612)

    private func entry(_ name: String, size: Int64 = 10, directory: Bool = false) -> DroppedEntry {
        DroppedEntry(url: URL(fileURLWithPath: "/Users/alice/Desktop/\(name)"), isDirectory: directory, size: size)
    }

    private func stored(_ original: String) -> String {
        UploadName.make(original: original, date: date, timeZone: utc).fileName
    }

    func testTheStampGoesBeforeTheExtension() {
        XCTAssertEqual(stored("report.pdf"), "report-20260930-143012.pdf")
        XCTAssertEqual(stored("photo.final.png"), "photo.final-20260930-143012.png")
    }

    func testANameWithoutExtensionAndADotfileKeepTheirWholeName() {
        XCTAssertEqual(stored("Makefile"), "Makefile-20260930-143012")
        XCTAssertEqual(stored(".env"), ".env-20260930-143012")
    }

    func testSpacesAndUnicodeAreKept() {
        XCTAssertEqual(stored("my café ☕.jpg"), "my café ☕-20260930-143012.jpg")
    }

    func testOnlyWhatBreaksAPathIsReplaced() {
        XCTAssertEqual(stored("a/b.txt"), "a_b-20260930-143012.txt")
        XCTAssertEqual(stored("a\nb\rc.txt"), "a_b_c-20260930-143012.txt")
        XCTAssertEqual(stored("a\u{0}b.txt"), "a_b-20260930-143012.txt")
        XCTAssertEqual(stored(""), "file-20260930-143012")
        XCTAssertEqual(stored(".."), "file-20260930-143012")
    }

    func testAPastedImageGetsASensibleName() {
        XCTAssertEqual(stored(FileUpload.pastedImageName), "pasted-image-20260930-143012.png")
    }

    func testANumberedNameKeepsTheExtensionLast() {
        let name = UploadName.make(original: "report.pdf", date: date, timeZone: utc)
        XCTAssertEqual(name.numbered(1), "report-20260930-143012.pdf")
        XCTAssertEqual(name.numbered(2), "report-20260930-143012-2.pdf")
    }

    func testGenericUploadsGoToTheUploadsFolder() {
        XCTAssertEqual(UploadStoragePolicy.appManaged.directory, ".cache/devmachine-app/uploads")
    }

    func testTheCommandWritesUnderThePolicyFolderAndPrintsThePath() {
        let policy = UploadStoragePolicy(directory: ".claude/image-cache/devmachine-app")
        let name = UploadName.make(original: "report.pdf", date: date, timeZone: utc)
        let command = FileUpload.writeCommand(name: name, policy: policy)
        XCTAssertTrue(command.hasPrefix("d=\"$HOME\"/'.claude/image-cache/devmachine-app'"))
        XCTAssertTrue(command.contains(Data("report-20260930-143012".utf8).base64EncodedString()))
        XCTAssertTrue(command.contains(Data(".pdf".utf8).base64EncodedString()))
        XCTAssertTrue(command.contains("mkdir -p \"$d\""))
        XCTAssertTrue(command.contains("cat > \"$f\""))
        XCTAssertTrue(command.hasSuffix("printf '%s\\n' \"$f\""))
    }

    func testTheCommandNeverOverwritesAnEarlierUpload() {
        let command = FileUpload.writeCommand(
            name: UploadName.make(original: "a.txt", date: date, timeZone: utc), policy: .appManaged)
        XCTAssertTrue(command.contains("while [ -e \"$f\" ]"))
    }

    func testTheNameNeverReachesTheShellAsText() {
        let hostile = "x'; rm -rf ~; echo '$(id)`id`\".txt"
        let command = FileUpload.writeCommand(
            name: UploadName.make(original: hostile, date: date, timeZone: utc), policy: .appManaged)
        XCTAssertFalse(command.contains("rm -rf"))
        XCTAssertFalse(command.contains("$(id)"))
        XCTAssertFalse(command.contains("`id`"))
    }

    func testPlainPathsAreTypedAsTheyAre() {
        XCTAssertEqual(FileUpload.shellQuoted("/home/alice/a-b_c.1.png"), "/home/alice/a-b_c.1.png")
    }

    func testPathsWithSpacesQuotesDollarsAndUnicodeAreQuoted() {
        XCTAssertEqual(FileUpload.shellQuoted("/home/alice/my file.png"), "'/home/alice/my file.png'")
        XCTAssertEqual(FileUpload.shellQuoted("/home/alice/it's.txt"), "'/home/alice/it'\\''s.txt'")
        XCTAssertEqual(FileUpload.shellQuoted("/home/alice/$HOME.md"), "'/home/alice/$HOME.md'")
        XCTAssertEqual(FileUpload.shellQuoted("/home/alice/café.jpg"), "'/home/alice/café.jpg'")
    }

    func testSeveralPathsAreTypedInOrderSpaceSeparatedWithoutEnter() {
        let text = FileUpload.typedText(for: ["/home/alice/b.txt", "/home/alice/a file.txt"])
        XCTAssertEqual(text, "/home/alice/b.txt '/home/alice/a file.txt' ")
        XCTAssertFalse(text.contains("\n"))
        XCTAssertFalse(text.contains("\r"))
    }

    func testAFolderInTheDropRefusesTheWholeDrop() {
        let entries = [entry("a.txt"), entry("photos", directory: true)]
        XCTAssertThrowsError(try FileUpload.plan(entries, date: date, timeZone: utc)) { error in
            XCTAssertEqual(error as? UploadRefusal, .folders(["photos"]))
        }
    }

    func testTheFolderRefusalSaysWhatToDo() {
        XCTAssertEqual(
            UploadRefusal.folders(["photos"]).title,
            "Folders can\u{2019}t be dropped yet \u{2014} drop the files inside")
    }

    func testThePlanKeepsTheDropOrderAndTheOriginalNames() throws {
        let items = try FileUpload.plan(
            [entry("z.txt", size: 1), entry("a.png", size: 2), entry("m.pdf", size: 3)],
            date: date, timeZone: utc)
        XCTAssertEqual(items.map(\.originalName), ["z.txt", "a.png", "m.pdf"])
        XCTAssertEqual(items.map(\.name.fileName), [
            "z-20260930-143012.txt", "a-20260930-143012.png", "m-20260930-143012.pdf",
        ])
        XCTAssertEqual(items.map(\.size), [1, 2, 3])
    }

    func testTwoFilesWithTheSameNameInOneDropDoNotCollide() throws {
        let items = try FileUpload.plan(
            [entry("a.txt"), DroppedEntry(url: URL(fileURLWithPath: "/Users/alice/Other/a.txt"),
                                          isDirectory: false, size: 1)],
            date: date, timeZone: utc)
        XCTAssertEqual(items.map(\.name.fileName), ["a-20260930-143012.txt", "a-20260930-143012-2.txt"])
    }

    func testTheSizeConfirmationStartsAbove200MB() {
        XCTAssertFalse(FileUpload.needsConfirmation(totalBytes: 200 * 1024 * 1024))
        XCTAssertTrue(FileUpload.needsConfirmation(totalBytes: 200 * 1024 * 1024 + 1))
    }

    func testTheHostAnswerMustBeAPathToTheFileItWrote() {
        let name = UploadName.make(original: "a b.txt", date: date, timeZone: utc)
        XCTAssertEqual(
            FileUpload.writtenPath(
                from: "/home/alice/.cache/devmachine-app/uploads/a b-20260930-143012-2.txt\n", name: name),
            "/home/alice/.cache/devmachine-app/uploads/a b-20260930-143012-2.txt")
        XCTAssertNil(FileUpload.writtenPath(from: "ssh: connect to host\n", name: name))
        XCTAssertNil(FileUpload.writtenPath(from: "/home/alice/other.txt\n", name: name))
    }

    func testBytesReadTheSameInEveryLocale() {
        XCTAssertEqual(FileUpload.byteText(512), "512 B")
        XCTAssertEqual(FileUpload.byteText(1_572_864), "1.5 MB")
        XCTAssertEqual(FileUpload.byteText(3 * 1024 * 1024 * 1024), "3.0 GB")
    }
}
