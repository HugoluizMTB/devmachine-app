import XCTest
import DevmachineCore
@testable import DevmachineApp

final class HarnessRegistryTests: XCTestCase {
    func testBuiltInAdaptersAreRegisteredInPresentationOrder() {
        let registry = HarnessRegistry.builtIn

        XCTAssertEqual(registry.adapters.map(\.id), [.claude, .codex, .pi, .antigravity, .opencode, .kimi, .cline, .herdr])
        XCTAssertNil(registry.adapter(for: HarnessID(rawValue: "unknown")))
    }

    func testBuiltInDescriptorsProvideGenericUIValues() throws {
        let registry = HarnessRegistry.builtIn
        let claude = try XCTUnwrap(registry.adapter(for: .claude))
        let codex = try XCTUnwrap(registry.adapter(for: .codex))

        XCTAssertEqual(claude.descriptor.id, .claude)
        XCTAssertEqual(claude.descriptor.title, "Claude Code")
        XCTAssertEqual(claude.descriptor.shortTitle, "Claude")
        XCTAssertFalse(claude.descriptor.systemImage.isEmpty)
        XCTAssertFalse(claude.descriptor.helpText.isEmpty)
        XCTAssertEqual(claude.executableName, "claude")
        XCTAssertEqual(claude.processNames, ["claude"])
        XCTAssertEqual(claude.startupCommand, "claude")
        XCTAssertEqual(claude.uploadStoragePolicy.directory, ".claude/image-cache/devmachine-app")

        XCTAssertEqual(codex.descriptor.id, .codex)
        XCTAssertEqual(codex.descriptor.title, "OpenAI Codex")
        XCTAssertEqual(codex.descriptor.shortTitle, "Codex")
        XCTAssertFalse(codex.descriptor.systemImage.isEmpty)
        XCTAssertFalse(codex.descriptor.helpText.isEmpty)
        XCTAssertEqual(codex.executableName, "codex")
        XCTAssertEqual(codex.processNames, ["codex"])
        XCTAssertEqual(codex.startupCommand, "codex")
        XCTAssertEqual(codex.uploadStoragePolicy, .appManaged)
    }

    func testEveryOtherHarnessLaunchesItsCLIAndIsKnownByItsPrograms() throws {
        let expected: [(HarnessID, String, String, String, Set<String>)] = [
            (.pi, "Pi", "Pi", "pi", ["pi"]),
            (.antigravity, "Antigravity CLI", "Antigravity", "agy", ["agy"]),
            (.opencode, "opencode", "opencode", "opencode", ["opencode"]),
            (.kimi, "Kimi Code", "Kimi", "kimi", ["kimi", "kimi-code"]),
            (.cline, "Cline", "Cline", "cline", ["cline", ".cline"]),
            (.herdr, "Herdr", "Herdr", "herdr", ["herdr"]),
        ]
        for (id, title, shortTitle, executable, programs) in expected {
            let adapter = try XCTUnwrap(HarnessRegistry.builtIn.adapter(for: id), id.rawValue)
            XCTAssertEqual(adapter.descriptor.title, title)
            XCTAssertEqual(adapter.descriptor.shortTitle, shortTitle)
            XCTAssertFalse(adapter.descriptor.helpText.isEmpty)
            XCTAssertEqual(adapter.executableName, executable)
            XCTAssertEqual(adapter.startupCommand, executable)
            XCTAssertEqual(adapter.processNames, programs)
            XCTAssertEqual(adapter.uploadStoragePolicy, .appManaged)
            XCTAssertNil(adapter.usageProvider(locator: SystemExecutableLocator(
                path: "/missing", knownDirectories: [], loginShellLookup: nil)))
        }
    }

    func testNoTwoHarnessesShareAColorOrAProgram() {
        let adapters = HarnessRegistry.builtIn.adapters
        XCTAssertEqual(Set(adapters.map { "\($0.descriptor.color)" }).count, adapters.count)
        let programs = adapters.flatMap(\.processNames)
        XCTAssertEqual(Set(programs).count, programs.count)
    }

    func testTheRegistryListsEveryProgramOfEveryHarness() {
        let names = HarnessRegistry.builtIn.processNames
        XCTAssertEqual(names[.kimi], ["kimi", "kimi-code"])
        XCTAssertEqual(names[.antigravity], ["agy"])
        XCTAssertEqual(names.count, HarnessRegistry.builtIn.adapters.count)
    }

    func testALocalSessionIsDetectedByTheNativeChildTheLauncherStarts() {
        let sessions = [
            ZmxSession(name: "a", pid: 10, clients: 1, directory: nil),
            ZmxSession(name: "b", pid: 20, clients: 1, directory: nil),
            ZmxSession(name: "c", pid: 30, clients: 1, directory: nil),
        ]
        let entries = [
            ProcessTree.Entry(pid: 11, parent: 10, command: "node"),
            ProcessTree.Entry(pid: 12, parent: 11, command: "/Users/alice/.npm/lib/node_modules/cline/bin/.cline"),
            ProcessTree.Entry(pid: 21, parent: 20, command: "kimi-code"),
            ProcessTree.Entry(pid: 31, parent: 30, command: "pip"),
        ]

        let detected = SessionHarnessFacade(registry: .builtIn).detect(
            sessions: sessions, entries: entries)

        XCTAssertEqual(detected, ["a": [.cline], "b": [.kimi], "c": []])
    }

    func testASessionRunningHerdrIsDetectedAsHerdr() {
        let sessions = [ZmxSession(name: "a", pid: 10, clients: 1, directory: nil)]
        let entries = [ProcessTree.Entry(pid: 11, parent: 10, command: "/Users/alice/.local/bin/herdr")]

        let detected = SessionHarnessFacade(registry: .builtIn).detect(sessions: sessions, entries: entries)

        XCTAssertEqual(detected, ["a": [.herdr]])
    }

    func testHerdrCannotBeTurnedOnAsACodingAgent() throws {
        let herdr = try XCTUnwrap(HarnessRegistry.builtIn.adapter(for: .herdr))
        XCTAssertNil(herdr.descriptor.packageName)
    }

    func testUploadPolicyUsesRegistryOrderAndFallsBackToAppStorage() {
        let facade = SessionHarnessFacade(registry: .builtIn)

        XCTAssertEqual(facade.uploadStoragePolicy(for: [.codex]), .appManaged)
        XCTAssertEqual(
            facade.uploadStoragePolicy(for: [.claude, .codex]).directory,
            ".claude/image-cache/devmachine-app")
        XCTAssertEqual(facade.uploadStoragePolicy(for: []), .appManaged)
        XCTAssertEqual(
            facade.uploadStoragePolicy(for: [.codex]).directory, ".cache/devmachine-app/uploads")
    }
}
