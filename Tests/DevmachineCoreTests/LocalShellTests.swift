import XCTest
@testable import DevmachineCore

final class LocalShellTests: XCTestCase {
    func testTheAccountShellWins() {
        let shell = LocalShell.resolve(
            account: "/opt/homebrew/bin/fish", environment: "/bin/bash", isExecutable: { _ in true })
        XCTAssertEqual(shell, "/opt/homebrew/bin/fish")
    }

    func testAMissingAccountShellFallsBackToTheEnvironment() {
        let shell = LocalShell.resolve(
            account: "/opt/homebrew/bin/fish", environment: "/bin/bash",
            isExecutable: { $0 == "/bin/bash" })
        XCTAssertEqual(shell, "/bin/bash")
    }

    func testNothingUsableFallsBackToZsh() {
        XCTAssertEqual(LocalShell.resolve(account: nil, environment: "", isExecutable: { _ in false }), "/bin/zsh")
        XCTAssertEqual(LocalShell.resolve(account: "", environment: nil, isExecutable: { _ in true }), "/bin/zsh")
    }

    func testTheKindComesFromTheProgramName() {
        XCTAssertEqual(ShellKind(path: "/bin/zsh"), .zsh)
        XCTAssertEqual(ShellKind(path: "/opt/homebrew/bin/bash"), .bash)
        XCTAssertEqual(ShellKind(path: "/usr/local/bin/fish"), .fish)
        XCTAssertEqual(ShellKind(path: "/bin/tcsh"), .other)
    }
}

final class ShellIntegrationLaunchTests: XCTestCase {
    private let dir = "/Users/alice/Library/Application Support/Devmachine/shell-integration"

    func testZshReadsItsStartupFilesThroughTheIntegrationFolder() {
        let launch = ShellIntegration.launch(shell: "/bin/zsh", integrationDirectory: dir)
        XCTAssertEqual(launch.executable, "/bin/zsh")
        XCTAssertEqual(launch.execName, "-zsh")
        XCTAssertEqual(launch.arguments, ["-i"])
        XCTAssertEqual(launch.environment, ["SHELL=/bin/zsh", "ZDOTDIR=\(dir)/zsh"])
        XCTAssertEqual(launch.multiplexerCommand, [])
    }

    func testBashRunsTheIntegrationAsItsInitFile() {
        let launch = ShellIntegration.launch(shell: "/opt/homebrew/bin/bash", integrationDirectory: dir)
        let arguments = ["--init-file", "\(dir)/bash/devmachine.bash", "-i"]
        XCTAssertEqual(launch.execName, "bash")
        XCTAssertEqual(launch.arguments, arguments)
        XCTAssertEqual(launch.environment, ["SHELL=/opt/homebrew/bin/bash"])
        XCTAssertEqual(launch.multiplexerCommand, ["/opt/homebrew/bin/bash"] + arguments)
    }

    func testFishSourcesTheIntegrationAfterItsOwnConfiguration() {
        let launch = ShellIntegration.launch(shell: "/opt/homebrew/bin/fish", integrationDirectory: dir)
        let arguments = ["-l", "-i", "-C", "source '\(dir)/fish/devmachine.fish'"]
        XCTAssertEqual(launch.execName, "-fish")
        XCTAssertEqual(launch.arguments, arguments)
        XCTAssertEqual(launch.multiplexerCommand, ["/opt/homebrew/bin/fish"] + arguments)
    }

    func testAQuoteInTheFolderIsEscapedForFish() {
        let launch = ShellIntegration.launch(shell: "/usr/local/bin/fish", integrationDirectory: "/Users/o'neil/x")
        XCTAssertEqual(launch.arguments.last, #"source '/Users/o\'neil/x/fish/devmachine.fish'"#)
    }

    func testAnotherShellStartsAsAPlainLoginShell() {
        let launch = ShellIntegration.launch(shell: "/bin/tcsh", integrationDirectory: dir)
        XCTAssertEqual(launch.execName, "-tcsh")
        XCTAssertEqual(launch.arguments, ["-i"])
        XCTAssertEqual(launch.environment, ["SHELL=/bin/tcsh"])
        XCTAssertEqual(launch.multiplexerCommand, [])
    }

    func testWithoutTheIntegrationEveryShellStartsPlain() {
        for shell in ["/bin/zsh", "/bin/bash", "/opt/homebrew/bin/fish"] {
            let launch = ShellIntegration.launch(shell: shell, integrationDirectory: nil)
            let name = (shell as NSString).lastPathComponent
            XCTAssertEqual(launch.execName, "-\(name)")
            XCTAssertEqual(launch.arguments, ["-i"])
            XCTAssertEqual(launch.environment, ["SHELL=\(shell)"])
            XCTAssertEqual(launch.multiplexerCommand, [])
        }
    }
}

final class ShellIntegrationInstallTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testInstallWritesOneFileForEachShell() throws {
        try ShellIntegration.install(in: root)
        for (path, content) in ShellIntegration.files {
            let written = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            XCTAssertEqual(written, content)
        }
        XCTAssertEqual(Set(ShellIntegration.files.keys), ["zsh/.zshenv", "bash/devmachine.bash", "fish/devmachine.fish"])
    }

    func testInstallReplacesAFileThatChanged() throws {
        try ShellIntegration.install(in: root)
        let file = root.appendingPathComponent("zsh/.zshenv")
        try "stale".write(to: file, atomically: true, encoding: .utf8)
        try ShellIntegration.install(in: root)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), ShellIntegration.files["zsh/.zshenv"])
    }

    func testEveryScriptTurnsOffTheReportingModes() {
        for content in ShellIntegration.files.values {
            XCTAssertTrue(content.contains(ShellIntegration.resetModesLiteral))
        }
    }
}
