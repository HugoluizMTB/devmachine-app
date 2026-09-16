import XCTest
import DevmachineCore
@testable import DevmachineApp

private final class FakeRunner: CommandRunner, @unchecked Sendable {
    var args: [String]?
    let output: String

    init(output: String = "") {
        self.output = output
    }

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        self.args = args
        return output
    }
}

final class FileServiceTests: XCTestCase {
    func testListSendsSingleQuotedRemoteCommand() throws {
        let fake = FakeRunner(output: "dir1/\nfile.txt\n")
        let service = FileService(host: HostRunner(remote: RemoteService(runner: fake)))

        let entries = try service.list(.host(alias: "acme-devmachine"), path: "/home/acme/dev")

        XCTAssertEqual(entries, [
            FileEntry(name: "dir1", isDir: true),
            FileEntry(name: "file.txt", isDir: false)
        ])
        XCTAssertEqual(fake.args?.last, "ls -Ap -- '/home/acme/dev'")
    }

    func testListCommandQuotesPathWithSpaceAndQuoteSafely() {
        let service = FileService(host: HostRunner(remote: RemoteService(runner: FakeRunner())))

        let command = service.listCommand(path: "my folder/it's here")

        XCTAssertEqual(command, "ls -Ap -- 'my folder/it'\\''s here'")
    }

    func testDownloadArgsBuildsScpSourceAndDestination() {
        let service = FileService(host: HostRunner(remote: RemoteService(runner: FakeRunner())))

        let args = service.downloadArgs(alias: "acme-devmachine", remotePath: "/home/acme/file.txt", localPath: "/tmp/file.txt")

        XCTAssertEqual(args, ["acme-devmachine:'/home/acme/file.txt'", "/tmp/file.txt"])
    }

    func testUploadArgsBuildsScpSourceAndDestination() {
        let service = FileService(host: HostRunner(remote: RemoteService(runner: FakeRunner())))

        let args = service.uploadArgs(alias: "acme-devmachine", localPath: "/tmp/file.txt", remotePath: "/home/acme/file.txt")

        XCTAssertEqual(args, ["/tmp/file.txt", "acme-devmachine:'/home/acme/file.txt'"])
    }

    func testDownloadArgsSingleQuotesSpaceInRemotePath() {
        let service = FileService(host: HostRunner(remote: RemoteService(runner: FakeRunner())))

        let args = service.downloadArgs(alias: "acme-devmachine", remotePath: "/home/acme/my folder/file.txt", localPath: "/tmp/file.txt")

        XCTAssertEqual(args.first, "acme-devmachine:'/home/acme/my folder/file.txt'")
    }

    func testDownloadArgsNeutralizesDollarSignInRemotePath() {
        let service = FileService(host: HostRunner(remote: RemoteService(runner: FakeRunner())))

        let args = service.downloadArgs(alias: "acme-devmachine", remotePath: "/home/acme/$(whoami).txt", localPath: "/tmp/file.txt")

        XCTAssertEqual(args.first, "acme-devmachine:'/home/acme/$(whoami).txt'")
    }

    func testDownloadArgsNeutralizesBacktickInRemotePath() {
        let service = FileService(host: HostRunner(remote: RemoteService(runner: FakeRunner())))

        let args = service.downloadArgs(alias: "acme-devmachine", remotePath: "/home/acme/`whoami`.txt", localPath: "/tmp/file.txt")

        XCTAssertEqual(args.first, "acme-devmachine:'/home/acme/`whoami`.txt'")
    }

    func testUploadArgsNeutralizesSemicolonInRemotePath() {
        let service = FileService(host: HostRunner(remote: RemoteService(runner: FakeRunner())))

        let args = service.uploadArgs(alias: "acme-devmachine", localPath: "/tmp/file.txt", remotePath: "/home/acme/file.txt; rm -rf ~")

        XCTAssertEqual(args.last, "acme-devmachine:'/home/acme/file.txt; rm -rf ~'")
    }
}
