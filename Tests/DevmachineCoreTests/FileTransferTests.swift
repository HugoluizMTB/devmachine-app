import XCTest
@testable import DevmachineCore

final class FileTransferTests: XCTestCase {
    func testDownloadArgumentsNameTheWorkspaceTheFolderAndEveryPathAfterTheFlags() {
        XCTAssertEqual(
            FileTransfer.downloadArguments(
                paths: ["/home/acme/proj/a.png", "/home/acme/proj/site"], workspace: "acme",
                to: "/Users/alice/Downloads"),
            ["--format", "json", "download", "--workspace", "acme", "--to", "/Users/alice/Downloads", "--",
             "/home/acme/proj/a.png", "/home/acme/proj/site"])
    }

    func testPathsTravelAsTheyAreWithSpacesQuotesUnicodeAndLeadingDashes() {
        let hostile = ["/home/acme/it's a \"report\" ção.txt", "-rf", "$(id) `id`.txt"]
        let args = FileTransfer.downloadArguments(paths: hostile, workspace: "acme", to: "/tmp/x")
        XCTAssertEqual(Array(args.suffix(4)), ["--"] + hostile)
    }

    func testUploadArgumentsPointDirAtTheFolderDroppedOn() {
        XCTAssertEqual(
            FileTransfer.uploadArguments(
                files: ["/Users/alice/Desktop/my photo.png"], workspace: "acme", directory: "/home/acme/proj/assets"),
            ["--format", "json", "upload", "--workspace", "acme", "--dir", "/home/acme/proj/assets", "--",
             "/Users/alice/Desktop/my photo.png"])
    }

    func testParseDownloadsReadsSuccessesAndFailures() {
        let json = """
        [{"remote":"/home/acme/a.png","local":"/Users/alice/Downloads/a.png","bytes":42,"folder":false},
         {"remote":"/home/acme/site","local":"/Users/alice/Downloads/site.tar.gz","bytes":9,"folder":true},
         {"remote":"/home/acme/gone","bytes":0,"folder":false,"error":"/home/acme/gone does not exist"}]
        """
        XCTAssertEqual(FileTransfer.parseDownloads(json), [
            DownloadedFile(remote: "/home/acme/a.png", local: "/Users/alice/Downloads/a.png", bytes: 42, folder: false, error: nil),
            DownloadedFile(remote: "/home/acme/site", local: "/Users/alice/Downloads/site.tar.gz", bytes: 9, folder: true, error: nil),
            DownloadedFile(remote: "/home/acme/gone", local: nil, bytes: 0, folder: false, error: "/home/acme/gone does not exist"),
        ])
    }

    func testParseDownloadsRefusesWhatIsNotTheJSONList() {
        XCTAssertNil(FileTransfer.parseDownloads("Error: no machine\n"))
        XCTAssertNil(FileTransfer.parseDownloads(""))
    }

    func testParseUploadsReadsTheRemotePath() {
        let json = #"[{"local":"/Users/alice/a.png","remote":"/home/acme/proj/a-20260930-143012.png","bytes":3}]"#
        XCTAssertEqual(FileTransfer.parseUploads(json), [
            UploadedFile(local: "/Users/alice/a.png", remote: "/home/acme/proj/a-20260930-143012.png", bytes: 3, error: nil)
        ])
    }

    func testAnOlderCLIIsToldApartFromAFailedDownload() {
        XCTAssertTrue(FileTransfer.isUnknownCommand(
            "Error: unknown command \"download\" for \"devmachine\"\n", "download"))
        XCTAssertFalse(FileTransfer.isUnknownCommand("Error: /x does not exist\n", "download"))
    }

    func testDisplayPathShortensTheHome() {
        XCTAssertEqual(FileTransfer.displayPath("/Users/alice/Downloads/a.png", home: "/Users/alice"), "~/Downloads/a.png")
        XCTAssertEqual(FileTransfer.displayPath("/Users/alicette/a.png", home: "/Users/alice"), "/Users/alicette/a.png")
        XCTAssertEqual(FileTransfer.displayPath("/tmp/a.png", home: "/Users/alice"), "/tmp/a.png")
    }

    func testNumberedMatchesTheCLICounter() {
        XCTAssertEqual(FileTransfer.numbered("report.pdf", 1), "report.pdf")
        XCTAssertEqual(FileTransfer.numbered("report.pdf", 2), "report-2.pdf")
        XCTAssertEqual(FileTransfer.numbered("photo.final.png", 3), "photo.final-3.png")
        XCTAssertEqual(FileTransfer.numbered("Makefile", 2), "Makefile-2")
        XCTAssertEqual(FileTransfer.numbered(".env", 2), ".env-2")
        XCTAssertEqual(FileTransfer.numbered("site.tar.gz", 2), "site-2.tar.gz")
        XCTAssertEqual(FileTransfer.numbered("relatório final.txt", 2), "relatório final-2.txt")
    }

    func testFreeNameSkipsEveryTakenName() {
        let taken: Set = ["a.txt", "a-2.txt"]
        XCTAssertEqual(FileTransfer.freeName("a.txt", taken: taken.contains), "a-3.txt")
        XCTAssertEqual(FileTransfer.freeName("b.txt", taken: taken.contains), "b.txt")
    }

    func testAFolderIsPromisedAsAnArchive() {
        XCTAssertEqual(FileTransfer.promisedName(of: "/home/acme/site", isDirectory: true), "site.tar.gz")
        XCTAssertEqual(FileTransfer.promisedName(of: "/home/acme/a b.png", isDirectory: false), "a b.png")
    }

    func testProgressArgumentsAskForProgressBeforeThePaths() {
        let args = FileTransfer.downloadArguments(paths: ["-rf"], workspace: "acme", to: "/tmp/x", progress: true)
        XCTAssertEqual(args, ["--format", "json", "download", "--workspace", "acme", "--to", "/tmp/x", "--progress", "--", "-rf"])
    }

    func testParseProgressReadsALineAndNothingElse() {
        XCTAssertEqual(
            FileTransfer.parseProgress(#"{"remote":"/home/acme/a.png","done":512,"total":2048}"#),
            DownloadProgress(remote: "/home/acme/a.png", done: 512, total: 2048))
        XCTAssertNil(FileTransfer.parseProgress("error: 1 of 2 paths were not downloaded"))
        XCTAssertNil(FileTransfer.parseProgress(""))
    }

    func testAnOlderCLIWithoutProgressIsToldApart() {
        XCTAssertTrue(FileTransfer.isUnknownFlag(
            "Error: unknown flag: --progress\nUsage: ...", FileTransfer.progressFlag))
        XCTAssertFalse(FileTransfer.isUnknownFlag("Error: /x does not exist\n", FileTransfer.progressFlag))
    }

    func testWithoutProgressKeepsOnlyWhatAPersonShouldRead() {
        let stderr = #"{"remote":"/a","done":0,"total":3}"# + "\nerror: /b does not exist\n"
        XCTAssertEqual(FileTransfer.withoutProgress(stderr), "error: /b does not exist\n")
    }

    func testTallyAddsEveryFileAndKeepsTheLatestCountOfEach() {
        var tally = DownloadTally()
        tally.record(DownloadProgress(remote: "/a", done: 0, total: 100))
        tally.record(DownloadProgress(remote: "/b", done: 0, total: 300))
        tally.record(DownloadProgress(remote: "/a", done: 60, total: 100))
        tally.record(DownloadProgress(remote: "/a", done: 100, total: 100))
        tally.record(DownloadProgress(remote: "/b", done: 50, total: 300))
        XCTAssertEqual(tally.done, 150)
        XCTAssertEqual(tally.total, 400)
    }

    func testTallyHasNoTotalWhileAFolderIsAmongThem() {
        var tally = DownloadTally()
        XCTAssertNil(tally.total)
        tally.record(DownloadProgress(remote: "/a", done: 10, total: 100))
        tally.record(DownloadProgress(remote: "/site", done: 4096, total: 0))
        XCTAssertNil(tally.total)
        XCTAssertEqual(tally.done, 4106)
    }
}
