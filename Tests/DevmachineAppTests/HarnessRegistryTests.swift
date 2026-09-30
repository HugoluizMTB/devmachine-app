import XCTest
import DevmachineCore
@testable import DevmachineApp

final class HarnessRegistryTests: XCTestCase {
    func testBuiltInAdaptersAreRegisteredInPresentationOrder() {
        let registry = HarnessRegistry.builtIn

        XCTAssertEqual(registry.adapters.map(\.id), [.claude, .codex])
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
