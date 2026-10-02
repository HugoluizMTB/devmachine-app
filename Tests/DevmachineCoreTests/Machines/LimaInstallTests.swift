import XCTest
@testable import DevmachineCore

final class LimaInstallTests: XCTestCase {
    private let armDigest = String(repeating: "a", count: 64)
    private let intelDigest = String(repeating: "b", count: 64)

    private var sums: String {
        """
        \(armDigest)  lima-2.2.0-Darwin-arm64.tar.gz
        \(intelDigest) *lima-2.2.0-Darwin-x86_64.tar.gz
        \(String(repeating: "c", count: 64))  lima-additional-guestagents-2.2.0-Darwin-arm64.tar.gz

        """
    }

    func testTheReleaseIsTheTarballForThisMacsProcessor() throws {
        let release = try XCTUnwrap(LimaInstall.release(tag: "v2.2.0", machine: "arm64"))
        XCTAssertEqual(release.version, "2.2.0")
        XCTAssertEqual(release.asset, "lima-2.2.0-Darwin-arm64.tar.gz")
        XCTAssertEqual(
            release.tarballURL.absoluteString,
            "https://github.com/lima-vm/lima/releases/download/v2.2.0/lima-2.2.0-Darwin-arm64.tar.gz")
        XCTAssertEqual(
            release.checksumsURL.absoluteString,
            "https://github.com/lima-vm/lima/releases/download/v2.2.0/SHA256SUMS")

        XCTAssertEqual(LimaInstall.release(tag: "2.2.0", machine: "x86_64")?.asset, "lima-2.2.0-Darwin-x86_64.tar.gz")
    }

    func testAnUnknownProcessorOrAMalformedTagHasNoRelease() {
        XCTAssertNil(LimaInstall.release(tag: "v2.2.0", machine: "ppc"))
        XCTAssertNil(LimaInstall.release(tag: "v2.2.0; rm -rf", machine: "arm64"))
        XCTAssertNil(LimaInstall.release(tag: "", machine: "arm64"))
    }

    func testTheLatestTagIsReadFromGitHubsAnswer() {
        let json = Data(#"{"tag_name":"v2.2.0","name":"v2.2.0","assets":[]}"#.utf8)
        XCTAssertEqual(LimaInstall.tag(fromLatestRelease: json), "v2.2.0")
        XCTAssertNil(LimaInstall.tag(fromLatestRelease: Data("rate limited".utf8)))
    }

    func testTheExpectedDigestIsTheLineForThatExactFile() {
        XCTAssertEqual(LimaInstall.expectedDigest(sums: sums, asset: "lima-2.2.0-Darwin-arm64.tar.gz"), armDigest)
        XCTAssertEqual(LimaInstall.expectedDigest(sums: sums, asset: "lima-2.2.0-Darwin-x86_64.tar.gz"), intelDigest)
        XCTAssertNil(LimaInstall.expectedDigest(sums: sums, asset: "lima-2.2.0-Linux-aarch64.tar.gz"))
    }

    func testOnlyADigestEqualToTheListedOneIsVerified() {
        let asset = "lima-2.2.0-Darwin-arm64.tar.gz"
        XCTAssertEqual(LimaInstall.check(digest: armDigest, sums: sums, asset: asset), .verified)
        XCTAssertEqual(LimaInstall.check(digest: armDigest.uppercased(), sums: sums, asset: asset), .verified)
        XCTAssertEqual(
            LimaInstall.check(digest: intelDigest, sums: sums, asset: asset),
            .mismatch(expected: armDigest, actual: intelDigest))
        XCTAssertEqual(LimaInstall.check(digest: armDigest, sums: "", asset: asset), .notListed)
    }

    func testTheDigestOfTheBytesIsSHA256() {
        XCTAssertEqual(
            LimaInstall.sha256(Data("abc".utf8)),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testEveryCheckFailureSaysWhatWentWrong() {
        XCTAssertNil(LimaInstall.Check.verified.problem)
        XCTAssertTrue(LimaInstall.Check.mismatch(expected: "a", actual: "b").problem?.contains("does not match") == true)
        XCTAssertTrue(LimaInstall.Check.notListed.problem?.contains("SHA256SUMS") == true)
    }

    func testItUnpacksIntoTheAccountsOwnLocalFolder() {
        XCTAssertEqual(LimaInstall.prefix(home: "/Users/alice"), "/Users/alice/.local")
        XCTAssertEqual(LimaInstall.limactl(home: "/Users/alice"), "/Users/alice/.local/bin/limactl")
        XCTAssertEqual(
            LimaInstall.extractArguments(tarball: "/tmp/lima.tar.gz", home: "/Users/alice"),
            ["-xzf", "/tmp/lima.tar.gz", "-C", "/Users/alice/.local"])
    }

    func testTheReleaseComesFirstAndHomebrewOnlyWhenItIsThere() {
        XCTAssertEqual(LimaInstall.methods(brew: nil), [.release])
        XCTAssertEqual(
            LimaInstall.methods(brew: "/opt/homebrew/bin/brew"), [.release, .homebrew(brew: "/opt/homebrew/bin/brew")])
        XCTAssertEqual(LimaInstall.homebrewArguments, ["install", "lima"])
    }

    func testTheCLIFindsLimaInTheLocalFolderThroughItsPath() {
        let environment = LimaInstall.environment(base: ["PATH": "/usr/bin:/bin", "HOME": "/x"], home: "/Users/alice")
        XCTAssertEqual(environment["PATH"], "/Users/alice/.local/bin:/usr/bin:/bin")
        XCTAssertEqual(environment["HOME"], "/x")

        let already = LimaInstall.environment(base: ["PATH": "/Users/alice/.local/bin:/bin"], home: "/Users/alice")
        XCTAssertEqual(already["PATH"], "/Users/alice/.local/bin:/bin")
        XCTAssertEqual(LimaInstall.environment(base: [:], home: "/Users/alice")["PATH"],
                       "/Users/alice/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin")
    }
}

final class LimaToolLocalTests: XCTestCase {
    func testLimaUnpackedIntoTheLocalFolderIsFoundToo() {
        XCTAssertEqual(
            LimaTool.find(home: "/Users/alice", exists: { $0 == "/Users/alice/.local/bin/limactl" }),
            "/Users/alice/.local/bin/limactl")
    }
}
