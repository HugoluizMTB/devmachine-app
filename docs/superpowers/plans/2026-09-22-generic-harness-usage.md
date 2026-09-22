# Generic Harness Usage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `ClaudeUsageKit` with generic multi-provider usage infrastructure and add token-free Codex account usage to Home and the menu bar.

**Architecture:** A generic `HarnessUsageStore` owns provider states and observer-counted polling. Claude and Codex providers translate their distinct sources into optional presentation sections; reusable SwiftUI components render those sections without provider branches.

**Tech Stack:** Swift 6, SwiftUI, Charts, Foundation `Process`/pipes, JSON-RPC over JSONL, SwiftPM, XCTest.

**Spec:** `docs/superpowers/specs/2026-09-22-generic-coding-harnesses-design.md`

## Global Constraints

- Complete the generic harness foundation plan first.
- All code, identifiers, comments, and commit messages are English.
- No real infrastructure, account details, tokens, or personal data may enter the repository.
- Account reads must not start a model turn or consume inference tokens.
- Views must render generic presentation sections and contain no provider-specific parsing or command rules.
- Polling runs only while a usage surface is visible and never overlaps per provider.
- Tests use fixture JSON and fake transports; they never start real Claude or Codex processes.
- `swift build`, `swift test`, and `scripts/check-real-data.sh` must pass.

---

### Task 1: Rename the reusable usage target

**Files:**
- Modify: `Package.swift`
- Rename: `Sources/ClaudeUsageKit/` to `Sources/HarnessUsageKit/`
- Rename: `Tests/ClaudeUsageKitTests/` to `Tests/HarnessUsageKitTests/`
- Modify imports in: `Sources/DevmachineApp/DevmachineApp.swift`
- Modify imports in: `Sources/DevmachineApp/HomeView.swift`
- Modify imports in: `Sources/DevmachineApp/MenuBarPanel.swift`

**Interfaces:**
- Produces: SwiftPM library `HarnessUsageKit` and test target `HarnessUsageKitTests`.
- Preserves: behavior before generic provider work begins.

- [ ] **Step 1: Mechanically rename target, directories, imports, and test imports**

Use `git mv` for directories and update `Package.swift` product/target/dependency names. Rename public Claude-prefixed types only when Task 2 replaces them.

- [ ] **Step 2: Build and run existing usage tests**

Run: `swift test --filter Usage`

Expected: all existing usage tests pass under the new target name.

- [ ] **Step 3: Commit**

```bash
git add Package.swift Sources/HarnessUsageKit Tests/HarnessUsageKitTests Sources/DevmachineApp
git commit -m "refactor(usage): rename the reusable usage module"
```

### Task 2: Generic usage snapshot, provider, and store

**Files:**
- Create: `Sources/HarnessUsageKit/HarnessUsageProvider.swift`
- Create: `Sources/HarnessUsageKit/HarnessUsageStore.swift`
- Modify: `Sources/HarnessUsageKit/UsageModels.swift`
- Modify: `Sources/HarnessUsageKit/ClaudeUsageStore.swift`
- Modify: `Sources/HarnessUsageKit/UsageProviders.swift`
- Modify: `Tests/HarnessUsageKitTests/ClaudeUsageStoreTests.swift`
- Create: `Tests/HarnessUsageKitTests/HarnessUsageStoreTests.swift`

**Interfaces:**
- Produces: `HarnessUsageSnapshot`, `HarnessUsageProvider`, `HarnessUsageState`, and `HarnessUsageStore`.
- Preserves: Claude parsing through a `ClaudeUsageProvider` adapter.

- [ ] **Step 1: Add failing multi-provider store tests**

Test ordered provider states, independent errors, no overlapping refresh per provider, observer-counted timer lifecycle, and unchanged-state publication avoidance.

```swift
public protocol HarnessUsageProvider: Sendable {
    var harnessID: String { get }
    func fetchSnapshot(previous: HarnessUsageSnapshot?) throws -> HarnessUsageSnapshot
}
```

- [ ] **Step 2: Run focused tests and confirm failure**

Run: `swift test --filter HarnessUsageStoreTests`

Expected: compilation fails because the generic store does not exist.

- [ ] **Step 3: Implement generic state and adapt Claude**

Rename `ClaudeUsageStore` to the provider-neutral store API. Keep Claude source logic inside `ClaudeUsageProvider`; remove Claude names from shared errors and views. A snapshot carries optional `planName`, `[UsageBlock]`, `UsageStats`, and summary metrics.

- [ ] **Step 4: Run usage tests**

Run: `swift test --filter Usage`

Expected: generic store tests and all preserved Claude tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/HarnessUsageKit Tests/HarnessUsageKitTests
git commit -m "refactor(usage): support multiple harness providers"
```

### Task 3: Codex app-server account provider

**Files:**
- Create: `Sources/HarnessUsageKit/Codex/CodexAppServerTransport.swift`
- Create: `Sources/HarnessUsageKit/Codex/CodexUsageModels.swift`
- Create: `Sources/HarnessUsageKit/Codex/CodexUsageProvider.swift`
- Create: `Tests/HarnessUsageKitTests/CodexAppServerTransportTests.swift`
- Create: `Tests/HarnessUsageKitTests/CodexUsageProviderTests.swift`

**Interfaces:**
- Produces: `CodexRPCTransport`, `CodexAppServerTransport`, response DTOs, and `CodexUsageProvider`.
- Consumes: generic `HarnessUsageProvider` from Task 2.

- [ ] **Step 1: Add failing JSON-RPC parsing tests**

Use invented JSONL fixtures containing unrelated notifications plus responses for `account/rateLimits/read` and `account/usage/read`. Cover primary/secondary buckets, multiple limit IDs, nullable summary values, missing daily buckets, RPC errors, malformed JSON, and timeout errors.

- [ ] **Step 2: Run focused tests and confirm failure**

Run: `swift test --filter Codex`

Expected: compilation fails because Codex transport and provider types do not exist.

- [ ] **Step 3: Implement a bounded JSON-RPC transport**

The production transport locates `codex` through an injected executable URL, starts `codex app-server --listen stdio://`, sends `initialize`, `initialized`, `account/rateLimits/read`, and `account/usage/read`, then reads newline-delimited responses by ID. It never calls `thread/start` or `turn/start`. Close stdin and terminate the helper after both responses; enforce a 15-second timeout.

```swift
protocol CodexRPCTransport: Sendable {
    func accountSnapshot() throws -> CodexAccountSnapshot
}
```

- [ ] **Step 4: Translate Codex responses into generic sections**

Create quota bars from rate-limit windows, daily totals from `dailyUsageBuckets`, plan text when present, and summary metric rows for non-null values. Leave model breakdown absent.

- [ ] **Step 5: Run focused tests**

Run: `swift test --filter Codex`

Expected: every transport and translation test passes without starting Codex.

- [ ] **Step 6: Commit**

```bash
git add Sources/HarnessUsageKit/Codex Tests/HarnessUsageKitTests/CodexAppServerTransportTests.swift Tests/HarnessUsageKitTests/CodexUsageProviderTests.swift
git commit -m "feat(usage): read Codex account limits and activity"
```

### Task 4: Generic reusable usage views

**Files:**
- Rename: `Sources/HarnessUsageKit/Views/ClaudeUsagePanel.swift` to `Sources/HarnessUsageKit/Views/HarnessUsagePanel.swift`
- Modify: `Sources/HarnessUsageKit/Views/HarnessUsagePanel.swift`
- Modify: `Sources/HarnessUsageKit/Views/UsageHeaderView.swift`
- Modify: `Sources/HarnessUsageKit/Views/UsageBarsView.swift`
- Modify: `Sources/HarnessUsageKit/Views/UsageModelBreakdownView.swift`
- Create: `Sources/HarnessUsageKit/Views/UsageSummaryView.swift`
- Create: `Tests/HarnessUsageKitTests/HarnessUsagePresentationTests.swift`

**Interfaces:**
- Consumes: `HarnessUsageState` and provider-neutral presentation data.
- Produces: `HarnessUsagePanel` and `HarnessUsageCardContent`, reusable by Home and the menu bar.

- [ ] **Step 1: Add failing presentation tests**

Test header composition without a plan, omitted model breakdown, optional summary rows, provider-scoped error copy, and stable sizing metadata.

- [ ] **Step 2: Run focused tests and confirm failure**

Run: `swift test --filter HarnessUsagePresentationTests`

Expected: compilation fails because generic presentation helpers do not exist.

- [ ] **Step 3: Replace Claude-specific view inputs**

Views receive title, descriptor styling, and optional sections. Remove strings such as `Claude Usage` and `Can't reach Claude` from reusable components. Keep explicit number formatting through `Text(verbatim:)`.

- [ ] **Step 4: Run usage tests**

Run: `swift test --filter Usage`

Expected: all usage view and model tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/HarnessUsageKit/Views Tests/HarnessUsageKitTests/HarnessUsagePresentationTests.swift
git commit -m "refactor(usage): render provider-neutral usage panels"
```

### Task 5: Home cards and menu-bar columns

**Files:**
- Modify: `Sources/DevmachineApp/DevmachineApp.swift`
- Modify: `Sources/DevmachineApp/HomeView.swift`
- Modify: `Sources/DevmachineApp/MenuBarPanel.swift`
- Modify: `Tests/DevmachineAppTests/MenuBarLabelTests.swift`
- Create: `Tests/DevmachineAppTests/UsageLayoutTests.swift`

**Interfaces:**
- Consumes: shared `HarnessUsageStore`, active locally available harness descriptors, and generic usage views.
- Produces: one stacked Home card per harness and adaptive side-by-side menu-bar Usage columns.

- [ ] **Step 1: Add failing layout-policy tests**

Extract pure sizing policy and prove Pull Requests stays 420 points, one Usage column stays 380 points, two Usage columns use the wide value, and width is capped by available screen width.

```swift
XCTAssertEqual(MenuBarSizing.width(for: .pullRequests, usageColumns: 2, available: 1200), 420)
XCTAssertEqual(MenuBarSizing.width(for: .usage, usageColumns: 2, available: 1200), 776)
```

- [ ] **Step 2: Run focused tests and confirm failure**

Run: `swift test --filter UsageLayoutTests`

Expected: compilation fails because sizing policy does not exist.

- [ ] **Step 3: Wire the shared store and Home cards**

Create providers from active, locally available adapters. Inject one store into both surfaces. Replace the single Claude card with `ForEach` generic cards in registry order. Remove the Notifications card.

- [ ] **Step 4: Render adaptive menu-bar columns**

Keep the Pull Requests path unchanged. Usage renders an `HStack` of generic panels with dividers between columns and width from `MenuBarSizing`. One visible harness has no extra selector; two appear simultaneously.

- [ ] **Step 5: Run focused and full tests**

Run: `swift test --filter 'UsageLayoutTests|MenuBarLabelTests'`

Then run: `swift test`

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/DevmachineApp/DevmachineApp.swift Sources/DevmachineApp/HomeView.swift Sources/DevmachineApp/MenuBarPanel.swift Tests/DevmachineAppTests/MenuBarLabelTests.swift Tests/DevmachineAppTests/UsageLayoutTests.swift
git commit -m "feat(usage): show harness cards across app surfaces"
```

### Task 6: Final verification and privacy check

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`

**Interfaces:**
- Verifies: the complete generic harness and usage integration.

- [ ] **Step 1: Search for accidental UI coupling**

Run: `rg -n 'Claude|Codex|claude|codex' Sources/DevmachineApp/SetupPage.swift Sources/DevmachineApp/SidebarView.swift Sources/DevmachineApp/CommandPaletteView.swift Sources/DevmachineApp/HomeView.swift Sources/DevmachineApp/MenuBarPanel.swift`

Expected: no provider-specific executable, parser, path, or selection branches; intentional product copy must come through descriptors.

- [ ] **Step 2: Run complete automated verification**

Run: `swift build`

Run: `swift test`

Run: `scripts/check-real-data.sh`

Expected: build succeeds, every test passes, and the privacy script prints `clean`.

- [ ] **Step 3: Package for manual validation**

Run: `./scripts/package_app.sh`

Expected: `build/DevmachineApp.app` is produced without changing installed applications or live sessions.

- [ ] **Step 4: Record the environment-dependent manual checks**

The final handoff must ask the owner to verify only these behaviors that require installed CLIs or live sessions: enabling each installed harness, rejecting a missing CLI, launching different defaults in two remote workspaces, seeing live Claude/Codex sidebar badges, opening Context with Command-J inside Codex, comparing both Home cards, and viewing the wide two-column menu-bar Usage panel. Do not ask the owner to repeat build, parser, migration, or layout-policy tests covered automatically.

- [ ] **Step 5: Document multi-harness usage and commit**

Update both documents to name the generic usage target, describe locally available harness cards, and record that Codex account reads use app-server without starting model turns.

```bash
git add README.md CLAUDE.md
git commit -m "docs: document multi-harness usage"
```
