# Generic Harness Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Claude-specific session, settings, sidebar, and context assumptions with generic coding-harness facades supporting Claude Code and OpenAI Codex.

**Architecture:** Pure harness identifiers and launch settings live in `DevmachineCore`. Provider-specific commands and process matching live behind `CodingHarnessAdapter` instances in the app target. SwiftUI consumes presentation values from facades, while a small `DevmachineServices` boundary wraps current external context access for later replacement by `devmachine-cli`.

**Tech Stack:** Swift 6, SwiftUI, AppKit, SwiftPM, XCTest.

**Spec:** `docs/superpowers/specs/2026-09-22-generic-coding-harnesses-design.md`

## Global Constraints

- All code, identifiers, comments, and commit messages are English.
- No real infrastructure or personal data may enter code, tests, fixtures, docs, comments, screenshots, or assets.
- SwiftUI views must not contain Claude/Codex executable names, paths, parsers, or provider-selection switches.
- Tests never spawn SSH, Claude, or Codex.
- Remote harness configuration is declarative and never probes or modifies the VPS.
- Existing settings must decode without losing the previous session-launch behavior.
- `swift build`, `swift test`, and `scripts/check-real-data.sh` must pass.

---

### Task 1: Harness identifiers and settings migration

**Files:**
- Create: `Sources/DevmachineCore/CodingHarness.swift`
- Modify: `Sources/DevmachineCore/AppSettings.swift`
- Modify: `Tests/DevmachineCoreTests/AppSettingsTests.swift`

**Interfaces:**
- Produces: `HarnessID`, `SessionLaunchChoice`, `AppSettings.enabledHarnesses`, `localSessionProgram`, `remoteSessionProgram`, `workspaceSessionPrograms`, and `sessionProgram(for:)`.
- Preserves: decoding the legacy `newSessionProgram` key and its `.shell`/`.claude` values.

- [ ] **Step 1: Add failing model and migration tests**

Add tests proving multiple enabled IDs round-trip, local and per-workspace defaults are independent, a missing override uses the remote fallback, disabling an ID normalizes references to Terminal, and legacy `.claude` settings migrate to an enabled Claude harness with matching local and remote defaults.

```swift
func testLegacyClaudeProgramMigratesToHarnessSettings() throws {
    let data = Data(#"{"opsRepoPath":"/tmp","hostAlias":"h","publicIP":"203.0.113.10","baseDomain":"example.com","newSessionProgram":"claude"}"#.utf8)
    let settings = try JSONDecoder().decode(AppSettings.self, from: data)
    XCTAssertEqual(settings.enabledHarnesses, [.claude])
    XCTAssertEqual(settings.localSessionProgram, .harness(.claude))
    XCTAssertEqual(settings.remoteSessionProgram, .harness(.claude))
}
```

- [ ] **Step 2: Run the focused tests and confirm failure**

Run: `swift test --filter AppSettingsTests`

Expected: compilation fails because the generic harness types and fields do not exist.

- [ ] **Step 3: Implement the pure domain types and custom decoding**

Use stable string-backed identifiers and a launch choice that can represent future harnesses without changing an enum declaration.

```swift
public struct HarnessID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let claude = HarnessID(rawValue: "claude")
    public static let codex = HarnessID(rawValue: "codex")
}

public enum SessionLaunchChoice: Codable, Equatable, Sendable {
    case terminal
    case harness(HarnessID)
}
```

Add normalization on `AppSettings` so disabled defaults become `.terminal`. Decode new keys first; when absent, map the legacy key to the new fields. Keep encoding the legacy key out of new payloads.

- [ ] **Step 4: Run focused tests**

Run: `swift test --filter AppSettingsTests`

Expected: all settings and migration tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/DevmachineCore/CodingHarness.swift Sources/DevmachineCore/AppSettings.swift Tests/DevmachineCoreTests/AppSettingsTests.swift
git commit -m "refactor(settings): model generic coding harnesses"
```

### Task 2: Harness adapters and local activation

**Files:**
- Create: `Sources/DevmachineApp/Harnesses/CodingHarnessAdapter.swift`
- Create: `Sources/DevmachineApp/Harnesses/HarnessRegistry.swift`
- Create: `Sources/DevmachineApp/Harnesses/HarnessSettingsFacade.swift`
- Test: `Tests/DevmachineAppTests/HarnessRegistryTests.swift`
- Test: `Tests/DevmachineAppTests/HarnessSettingsFacadeTests.swift`

**Interfaces:**
- Consumes: `HarnessID`, `SessionLaunchChoice`, and `AppSettings` from Task 1.
- Produces: `HarnessDescriptor`, `CodingHarnessAdapter`, `ExecutableLocating`, `HarnessRegistry`, and `HarnessSettingsFacade`.

- [ ] **Step 1: Write failing registry and activation tests**

Use a fake executable locator. Prove both built-in adapters are registered, descriptors provide all UI values, enabling a missing CLI returns a presentation error without changing settings, and enabling an available CLI updates the enabled set.

```swift
func testMissingCLIIsNotEnabled() {
    let facade = HarnessSettingsFacade(registry: registry, locator: FakeLocator(available: []))
    let result = facade.enable(.codex, in: &settings)
    XCTAssertEqual(result, .failure(.cliNotFound("OpenAI Codex")))
    XCTAssertFalse(settings.enabledHarnesses.contains(.codex))
}
```

- [ ] **Step 2: Run focused tests and confirm failure**

Run: `swift test --filter Harness`

Expected: compilation fails because the adapter and facade types do not exist.

- [ ] **Step 3: Implement descriptors, adapters, registry, and locator**

The adapter protocol owns provider rules; descriptors are ready for generic views.

```swift
protocol CodingHarnessAdapter: Sendable {
    var id: HarnessID { get }
    var descriptor: HarnessDescriptor { get }
    var executableName: String { get }
    var processNames: Set<String> { get }
    var startupCommand: String { get }
}

protocol ExecutableLocating: Sendable {
    func executable(named name: String) -> URL?
}
```

Implement `ClaudeHarnessAdapter` and `CodexHarnessAdapter`. `HarnessRegistry` exposes ordered adapters and lookup by ID. `HarnessSettingsFacade` performs mutation only after local validation and returns generic descriptors/options for Settings.

- [ ] **Step 4: Run focused tests**

Run: `swift test --filter Harness`

Expected: all registry and activation tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/DevmachineApp/Harnesses Tests/DevmachineAppTests/HarnessRegistryTests.swift Tests/DevmachineAppTests/HarnessSettingsFacadeTests.swift
git commit -m "feat(harnesses): add adapters and activation facade"
```

### Task 3: Generic Settings interface and per-workspace defaults

**Files:**
- Modify: `Sources/DevmachineApp/SetupPage.swift`
- Modify: `Sources/DevmachineApp/SettingsStore.swift`
- Modify: `Sources/DevmachineApp/DevmachineApp.swift`
- Modify: `Tests/DevmachineAppTests/SettingsStoreTests.swift`
- Modify: `Tests/DevmachineAppTests/SetupPageTests.swift`
- Modify: `Tests/DevmachineAppTests/SetupPageRenderTests.swift`

**Interfaces:**
- Consumes: `HarnessSettingsFacade` and generic launch choices from Tasks 1-2.
- Produces: a Settings Harnesses section with multi-enable controls, one local default, one remote fallback, and one override per workspace.

- [ ] **Step 1: Add failing Settings behavior tests**

Test that draft/save/load preserves enabled harnesses and per-workspace choices, options contain Terminal plus enabled harness descriptors only, and disabling a harness normalizes affected choices.

- [ ] **Step 2: Run focused tests and confirm failure**

Run: `swift test --filter 'SettingsStoreTests|SetupPageTests'`

Expected: tests fail because Settings still exposes `NewSessionProgram`.

- [ ] **Step 3: Replace the Agents block with generic facade-driven controls**

Inject one shared `HarnessSettingsFacade` through the environment. Render adapters with `ForEach(facade.harnesses)` and generic descriptor fields. Bind local, remote fallback, and per-workspace pickers to `SessionLaunchChoice`. Do not spell `claude`, `codex`, executable names, or provider colors inside `SetupPage`.

- [ ] **Step 4: Run focused tests**

Run: `swift test --filter 'SettingsStoreTests|SetupPageTests|SetupPageRenderTests'`

Expected: all Settings tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/DevmachineApp/SetupPage.swift Sources/DevmachineApp/SettingsStore.swift Sources/DevmachineApp/DevmachineApp.swift Tests/DevmachineAppTests/SettingsStoreTests.swift Tests/DevmachineAppTests/SetupPageTests.swift Tests/DevmachineAppTests/SetupPageRenderTests.swift
git commit -m "feat(settings): configure harnesses per environment"
```

### Task 4: Generic remote and local session detection

**Files:**
- Modify: `Sources/DevmachineCore/TmuxSession.swift`
- Modify: `Sources/DevmachineCore/TmuxListParser.swift`
- Modify: `Sources/DevmachineCore/ProcessTree.swift`
- Create: `Sources/DevmachineApp/Harnesses/SessionHarnessFacade.swift`
- Modify: `Sources/DevmachineApp/AppModel.swift`
- Modify: `Tests/DevmachineCoreTests/TmuxListParserTests.swift`
- Modify: `Tests/DevmachineCoreTests/ProcessListTests.swift`
- Modify: `Tests/DevmachineAppTests/AppModelTests.swift`

**Interfaces:**
- Consumes: active adapters and their `processNames`.
- Produces: `TmuxSession.harnesses: Set<HarnessID>`, local session harness mappings, and generic session presentation/badges.

- [ ] **Step 1: Add failing detection tests**

Cover Claude, Codex, no harness, more than one recognized process, unknown commands, and one shared local `ps` parse. Replace assertions on `hasClaude` with harness-set assertions.

- [ ] **Step 2: Run focused tests and confirm failure**

Run: `swift test --filter 'TmuxListParserTests|ProcessListTests|AppModelTests'`

Expected: compilation or assertions fail against the old Boolean model.

- [ ] **Step 3: Implement catalog-driven detection**

Make `TmuxListParser.parse` accept a process-name catalog rather than knowing Claude. Extend `ProcessTree` with one traversal that returns matching program names for every root. Store local results by session name. `SessionHarnessFacade` converts IDs to ordered, ready-to-render badges.

- [ ] **Step 4: Use per-target launch defaults**

Change `startProgram(in:)` and `confirmNewSession` to resolve a `SessionLaunchChoice` through `HarnessSettingsFacade`, then ask the registry for its startup command. Local uses `localSessionProgram`; remote uses the workspace override or remote fallback.

- [ ] **Step 5: Run focused tests**

Run: `swift test --filter 'TmuxListParserTests|ProcessListTests|AppModelTests'`

Expected: all session detection and launch tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/DevmachineCore/TmuxSession.swift Sources/DevmachineCore/TmuxListParser.swift Sources/DevmachineCore/ProcessTree.swift Sources/DevmachineApp/Harnesses/SessionHarnessFacade.swift Sources/DevmachineApp/AppModel.swift Tests/DevmachineCoreTests/TmuxListParserTests.swift Tests/DevmachineCoreTests/ProcessListTests.swift Tests/DevmachineAppTests/AppModelTests.swift
git commit -m "refactor(sessions): detect active coding harnesses"
```

### Task 5: Generic session presentation across the app

**Files:**
- Modify: `Sources/DevmachineApp/SidebarView.swift`
- Modify: `Sources/DevmachineApp/CommandPaletteView.swift`
- Modify: `Sources/DevmachineApp/HomeView.swift`
- Modify: `Sources/DevmachineApp/AppModel.swift`
- Modify: `Tests/DevmachineAppTests/AppModelTests.swift`

**Interfaces:**
- Consumes: generic badge presentation from `SessionHarnessFacade`.
- Produces: provider-blind sidebar rows, palette rows, and session counts.

- [ ] **Step 1: Add failing presentation tests**

Verify palette items carry descriptors rather than a Claude Boolean, local items receive detected badges, and session counts include every detected coding harness.

- [ ] **Step 2: Run focused tests and confirm failure**

Run: `swift test --filter AppModelTests`

Expected: failures against `PaletteItem.claude` and `hasClaude`.

- [ ] **Step 3: Render generic badges**

Change row APIs to receive `[HarnessBadgePresentation]`. Preserve the hover-only display and client-count layout. Tooltip, color, and icon come from presentation values. Remove provider names and colors from views.

- [ ] **Step 4: Run focused tests**

Run: `swift test --filter AppModelTests`

Expected: all AppModel presentation tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/DevmachineApp/SidebarView.swift Sources/DevmachineApp/CommandPaletteView.swift Sources/DevmachineApp/HomeView.swift Sources/DevmachineApp/AppModel.swift Tests/DevmachineAppTests/AppModelTests.swift
git commit -m "refactor(ui): render generic harness sessions"
```

### Task 6: Context facade and future external-data boundary

**Files:**
- Create: `Sources/DevmachineApp/Services/DevmachineServices.swift`
- Create: `Sources/DevmachineApp/Services/WorkspaceSource.swift`
- Create: `Sources/DevmachineApp/Services/SessionSource.swift`
- Create: `Sources/DevmachineApp/Services/ContextSource.swift`
- Create: `Sources/DevmachineApp/Harnesses/ContextFacade.swift`
- Modify: `Sources/DevmachineApp/ContextState.swift`
- Modify: `Sources/DevmachineApp/ContextStore.swift`
- Modify: `Sources/DevmachineApp/ContentView.swift`
- Modify: `Sources/DevmachineApp/AppModel.swift`
- Modify: `Tests/DevmachineAppTests/ContextStateTests.swift`
- Modify: `Tests/DevmachineAppTests/ContextStoreTests.swift`
- Modify: `Tests/DevmachineAppTests/AppModelTests.swift`
- Create: `Tests/DevmachineAppTests/DevmachineServicesTests.swift`

**Interfaces:**
- Produces: `WorkspaceSource`, `SessionSource`, `ContextSource`, their current implementations, `DevmachineServices`, and `ContextFacade`.
- Preserves: current `devmachine-infer` behavior behind `CommandContextSource`.
- Prepares: replacement with a future `devmachine-cli` source.

- [ ] **Step 1: Add failing context compatibility tests**

Test decoding `harness: "claude"`, legacy `isClaude: true`, missing harness data, and the visibility of the panel for Claude, Codex, and terminal-only sessions. Test `ContextStore` with a fake `ContextSource`, not a fake command runner. Test `AppModel` workspace/session loading with fake domain sources so the model no longer owns their transport.

- [ ] **Step 2: Run focused tests and confirm failure**

Run: `swift test --filter 'ContextStateTests|ContextStoreTests|AppModelTests'`

Expected: failures because context is Claude-gated and directly owns command execution.

- [ ] **Step 3: Introduce the external source boundary**

```swift
protocol ContextSource: Sendable {
    func context(for target: CommandTarget) throws -> ContextState?
}

struct DevmachineServices {
    let workspaceSource: any WorkspaceSource
    let sessionSource: any SessionSource
    let contextSource: any ContextSource
}
```

Move current SSH-config workspace discovery, `SessionStore` polling, and context command execution behind the three domain sources. Make `AppModel` and `ContextStore` depend on `DevmachineServices`. Decode a generic optional harness ID while retaining the legacy field. Preserve the current concrete implementations as the default services.

- [ ] **Step 4: Remove Claude-only panel gating**

Mount `ContextPanel` for every selected local or remote session. Keep Command-J. Poll provider-specific context only when the Context tab is visible; Files and Git remain available even when no context provider returns data.

- [ ] **Step 5: Run focused and full tests**

Run: `swift test --filter 'ContextStateTests|ContextStoreTests|AppModelTests'`

Then run: `swift test`

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/DevmachineApp/Services Sources/DevmachineApp/Harnesses/ContextFacade.swift Sources/DevmachineApp/ContextState.swift Sources/DevmachineApp/ContextStore.swift Sources/DevmachineApp/ContentView.swift Sources/DevmachineApp/AppModel.swift Tests/DevmachineAppTests/ContextStateTests.swift Tests/DevmachineAppTests/ContextStoreTests.swift Tests/DevmachineAppTests/AppModelTests.swift
git commit -m "refactor(context): read through a generic source"
```

### Task 7: Harness-neutral image storage and terminal policy

**Files:**
- Modify: `Sources/DevmachineCore/ImagePaste.swift`
- Modify: `Sources/DevmachineApp/ImagePasteService.swift`
- Modify: `Sources/DevmachineApp/TerminalRegistry.swift`
- Modify: `Sources/DevmachineCore/TerminalReplyFilter.swift`
- Modify: `Tests/DevmachineCoreTests/ImagePasteTests.swift`
- Modify: `Tests/DevmachineAppTests/ImagePasteServiceTests.swift`
- Modify: `Tests/DevmachineAppTests/TerminalKeyboardTests.swift`

**Interfaces:**
- Consumes: the focused session's generic harness presentation and adapter policies.
- Produces: `ImageStoragePolicy` selected through the harness facade and provider-neutral terminal comments/tests.

- [ ] **Step 1: Add failing image-policy tests**

Prove Claude retains its managed cache path, Codex and terminal-only sessions use an app-managed cache path, and `ImagePasteService` accepts a policy rather than referring to Claude internally.

- [ ] **Step 2: Run focused tests and confirm failure**

Run: `swift test --filter 'ImagePasteTests|ImagePasteServiceTests|TerminalKeyboardTests'`

Expected: tests fail because image storage is a single Claude-specific constant.

- [ ] **Step 3: Route image paste through a generic policy**

Add a pure `ImageStoragePolicy` with the directory supplied by the selected adapter/facade. Keep the existing Claude directory for Claude and use `.cache/devmachine-app/images` otherwise. Do not add provider switches to `ImagePasteService` or `TerminalRegistry`.

- [ ] **Step 4: Make terminal documentation provider-neutral**

Keep the kitty/XTVERSION filtering global. Describe Shift-Return as sending a newline byte understood by supported coding harnesses, rather than as a Claude-only rule. Preserve behavior.

- [ ] **Step 5: Run focused tests**

Run: `swift test --filter 'ImagePasteTests|ImagePasteServiceTests|TerminalKeyboardTests'`

Expected: all image and keyboard tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/DevmachineCore/ImagePaste.swift Sources/DevmachineApp/ImagePasteService.swift Sources/DevmachineApp/TerminalRegistry.swift Sources/DevmachineCore/TerminalReplyFilter.swift Tests/DevmachineCoreTests/ImagePasteTests.swift Tests/DevmachineAppTests/ImagePasteServiceTests.swift Tests/DevmachineAppTests/TerminalKeyboardTests.swift
git commit -m "refactor(terminal): apply generic harness policies"
```

### Task 8: Foundation verification and documentation

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`

**Interfaces:**
- Documents: generic harness structure, local-only validation, declarative remote defaults, and future `devmachine-cli` boundary.

- [ ] **Step 1: Update documentation terminology**

Describe coding harness support without removing historical terminal-workaround explanations that are still technically accurate.

- [ ] **Step 2: Run verification**

Run: `swift build`

Run: `swift test`

Run: `scripts/check-real-data.sh`

Expected: build succeeds, every test passes, and the privacy script prints `clean`.

- [ ] **Step 3: Commit**

```bash
git add README.md CLAUDE.md
git commit -m "docs: describe generic coding harnesses"
```
