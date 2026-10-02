import XCTest
@testable import DevmachineCore

/// Runs each real shell through its integration in a pseudo-terminal, the way
/// a local pane does, with a throwaway home folder.
final class ShellIntegrationShellTests: XCTestCase {
    private var home: URL!
    private var integration: URL!

    override func setUpWithError() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("dm-shell-\(UUID().uuidString)")
        home = root.appendingPathComponent("home")
        integration = root.appendingPathComponent("integration dir")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try ShellIntegration.install(in: integration)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home.deletingLastPathComponent())
    }

    func testZshTurnsMouseReportingOffAtThePromptAndKeepsTheUsersConfiguration() throws {
        try put(".zshenv", "export DM_ENV=1\n")
        try put(".zshrc", "alias dmcheck='echo RC_LOADED'\n")
        let output = try run("/bin/zsh", input: [
            "printf '\\033[?1003h'; false",
            "echo STATUS:$? ZD:${ZDOTDIR-unset} ENV:$DM_ENV; dmcheck",
            "exit"
        ])
        assertResetFollowsEnable(output)
        XCTAssertTrue(output.contains("STATUS:1 ZD:unset ENV:1"), output)
        XCTAssertTrue(output.contains("RC_LOADED"), output)
    }

    func testBashTurnsMouseReportingOffAtThePromptAndReadsTheLoginProfile() throws {
        try put(".bash_profile", "PROMPT_COMMAND='echo -n'\nalias dmcheck='echo RC_LOADED'\n")
        let output = try run("/bin/bash", input: [
            "printf '\\033[?1003h'; false",
            "echo STATUS:$?; dmcheck",
            "exit"
        ])
        assertResetFollowsEnable(output)
        XCTAssertTrue(output.contains("STATUS:1"), output)
        XCTAssertTrue(output.contains("RC_LOADED"), output)
    }

    func testFishTurnsMouseReportingOffAtThePromptAndKeepsTheUsersConfiguration() throws {
        guard let fish = ["/opt/homebrew/bin/fish", "/usr/local/bin/fish"]
            .first(where: FileManager.default.isExecutableFile(atPath:))
        else { throw XCTSkip("fish is not installed") }
        try put(".config/fish/config.fish", "function dmcheck; echo RC_LOADED; end\n")
        let output = try run(fish, input: [
            "printf '\\033[?1003h'; false",
            "echo STATUS:$status; dmcheck",
            "exit"
        ])
        assertResetFollowsEnable(output)
        XCTAssertTrue(output.contains("STATUS:1"), output)
        XCTAssertTrue(output.contains("RC_LOADED"), output)
    }

    private func assertResetFollowsEnable(_ output: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let enable = output.range(of: "\u{1b}[?1003h") else {
            return XCTFail("the shell never ran the command: \(output.debugDescription)", file: file, line: line)
        }
        XCTAssertNotNil(
            output.range(of: ShellIntegration.resetModes, range: enable.upperBound..<output.endIndex),
            "no reset after the program turned reporting on: \(output.debugDescription)", file: file, line: line)
    }

    private func put(_ path: String, _ content: String) throws {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func run(_ shell: String, input: [String]) throws -> String {
        let launch = ShellIntegration.launch(shell: shell, integrationDirectory: integration.path)
        var primary: Int32 = 0
        var secondary: Int32 = 0
        XCTAssertEqual(openpty(&primary, &secondary, nil, nil, nil), 0)
        let process = Process()
        // script(1) gives the shell a controlling terminal, which fish needs
        // and Process cannot set up; `exec -a` keeps the pane's login name.
        process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        process.arguments = ["-q", "/dev/null", "/bin/bash", "-c", #"exec -a "$0" "$@""#,
                             launch.execName, launch.executable] + launch.arguments
        process.environment = Dictionary(uniqueKeysWithValues: (launch.environment + [
            "HOME=\(home.path)", "TERM=xterm-256color", "PATH=/usr/bin:/bin", "XDG_CONFIG_HOME=\(home.path)/.config"
        ]).map { entry -> (String, String) in
            let parts = entry.split(separator: "=", maxSplits: 1)
            return (String(parts[0]), String(parts[1]))
        })
        let tty = FileHandle(fileDescriptor: secondary, closeOnDealloc: true)
        process.standardInput = tty
        process.standardOutput = tty
        process.standardError = tty
        try process.run()
        try tty.close()

        defer { close(primary) }
        let lines = input
        let descriptorForInput = primary
        DispatchQueue.global().async {
            for line in lines {
                Thread.sleep(forTimeInterval: 0.8)
                _ = (line + "\r").withCString { write(descriptorForInput, $0, strlen($0)) }
            }
        }
        var output = [UInt8]()
        var buffer = [UInt8](repeating: 0, count: 4096)
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            var descriptor = pollfd(fd: primary, events: Int16(POLLIN), revents: 0)
            guard poll(&descriptor, 1, 200) >= 0 else { break }
            if descriptor.revents == 0 { continue }
            let count = read(primary, &buffer, buffer.count)
            if count <= 0 { break }
            output.append(contentsOf: buffer[0..<count])
        }
        if process.isRunning { process.terminate() }
        return String(decoding: output, as: UTF8.self)
    }
}
