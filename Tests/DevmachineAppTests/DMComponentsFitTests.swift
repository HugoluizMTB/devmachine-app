import XCTest
import SwiftUI
import DevmachineCore
@testable import DevmachineApp

@MainActor
final class DMComponentsFitTests: XCTestCase {
    func testTheCheckCatchesTextThatSpillsOutOfAFixedFrame() {
        let result = DMFitCheck.render(scale: 1) {
            Text(verbatim: "Update and Relaunch").font(.system(size: 30)).lineLimit(1)
                .fixedSize().frame(width: 60, height: 10)
        }
        XCTAssertGreaterThan(result.spilledPixels, 0)
    }

    func testButtonsFitAtEveryTextSize() {
        for size in DMButtonSize.allCases {
            for variant in DMButtonVariant.allCases {
                DMFitCheck.assertFits("button \(variant) \(size)") {
                    DMButton("Update and Relaunch", systemImage: "arrow.down", variant: variant, size: size) {}
                }
            }
            DMFitCheck.assertFits("icon button \(size)") {
                DMButton(icon: "xmark", label: "Close", size: size) {}
            }
            DMFitCheck.assertFits("loading button \(size)") {
                DMButton("Publish", size: size, isLoading: true) {}
            }
        }
        DMFitCheck.assertFits("full-width button", width: DMCardWidth.banner) {
            DMButton("Update and Relaunch", size: .small, fillsWidth: true) {}
        }
    }

    func testIconButtonsAndChipsFitAtEveryTextSize() {
        DMFitCheck.assertFits("icon button") {
            DMIconButton(systemImage: "arrow.clockwise", size: 11, hitSize: DMHitSize.compact) {}
        }
        DMFitCheck.assertFits("footer icon button") {
            DMIconButton(systemImage: "gearshape", size: DMMetrics.baseFontSize, hitSize: DMHitSize.footer) {}
        }
        DMFitCheck.assertFits("chip button") {
            Button("Commit") {}.buttonStyle(.dmChip).font(.dm(11))
        }
        DMFitCheck.assertFits("selected chip button") {
            Button("Tools") {}.buttonStyle(.dmChip(selected: true)).font(.dm(11))
        }
        DMFitCheck.assertFits("resting chip button") {
            Button("Other") {}.buttonStyle(.dmChip(selected: false)).font(.dm(11))
        }
        DMFitCheck.assertFits("chip") { DMChip(title: "Nature", selected: true) {} }
        DMFitCheck.assertFits("key cap") { DMKeyCap(key: "⌘") }
    }

    func testLabelsFitAtEveryTextSize() {
        DMFitCheck.assertFits("pill") { DMPill(text: "CI passing", color: .green) }
        DMFitCheck.assertFits("kind label") { DMKindLabel(text: "CNAME") }
        DMFitCheck.assertFits("dropdown") {
            DMDropdown(label: "Machine", options: [.init(value: "main", title: "main")], selection: .constant("main"))
        }
        DMFitCheck.assertFits("PR state") { DMPRStateIcon(state: .merged) }
        DMFitCheck.assertFits("section label") { DMSectionLabel(text: "WORKSPACES") }
        DMFitCheck.assertFits("choice card", width: DMCardWidth.banner) {
            DMChoiceCard(
                title: "docker", systemImage: "shippingbox", detail: "Docker Engine and Compose.",
                badge: "YOURS", selected: true, multiple: true) {}
        }
        DMFitCheck.assertFits("locked choice card", width: DMCardWidth.banner) {
            DMChoiceCard(
                title: "essentials", detail: "Base tools.", badge: "ALWAYS INSTALLED", note: "Includes base, git.",
                selected: true, multiple: true, locked: true) {}
        }
        DMFitCheck.assertFits("log", width: DMCardWidth.sheet) {
            DMLogView(lines: ["$ devmachine sync --machine lab --yes", "TASK [base : apt] ok"])
        }
    }

    func testRowsAndSectionsFitAtEveryTextSize() {
        DMFitCheck.assertFits("row", width: DMPaneWidth.sidebar.ideal) {
            DMRow(
                systemImage: "circle.fill", title: "claude — payments refactor", selected: true,
                trailing: AnyView(Text(verbatim: "3").font(.dm(11))))
        }
        DMFitCheck.assertFits("section", width: DMPaneWidth.context.ideal) {
            DMSection(padding: DMSectionInset.panel) {
                DMSectionLabel(text: "PULL REQUESTS")
            } trailing: {
                DMSectionValue(text: "5")
            } content: {
                DMRow(title: "#415 acme/api")
            }
        }
        DMFitCheck.assertFits("table row", width: DMPaneWidth.context.ideal) {
            DMTableRow(index: 1) {
                Text(verbatim: "app.example.com").font(.dm(12)).padding(DMMetrics.current.space.md)
            }
        }
    }

    func testTabStripsFitAtEveryTextSize() {
        DMFitCheck.assertFits("tab strip") {
            DMTabStrip(tabs: ["Context", "Preview", "Files", "Git"], selection: .constant("Context"),
                       title: { $0 }).fixedSize()
        }
        DMFitCheck.assertFits("grouped tab strip") {
            DMTabStrip(tabs: ["Sites", "cloudflare"], selection: .constant("Sites"), title: { $0 },
                       fontSize: 11, horizontalPadding: 10, verticalPadding: 3, grouped: true).fixedSize()
        }
    }

    func testStatesFitAtEveryTextSize() {
        DMFitCheck.assertFits("error state", width: DMCardWidth.errorState) {
            DMErrorStateView(
                state: DMErrorState(title: "Couldn't load this", message: "ssh: connect to host timed out"),
                retry: {}, startsExpanded: true)
        }
        DMFitCheck.assertFits("empty state", width: DMCardWidth.sheet) {
            DMStatusView(kind: .empty(systemImage: "tray", text: "Nothing here yet"), fillsHeight: false)
        }
        DMFitCheck.assertFits("banner", width: DMCardWidth.sheet) {
            DMBanner(message: "Showing the last good read.") {
                DMButton("Retry", variant: .outline, size: .small) {}
            }
        }
    }

    func testCommandsFieldsAndBarsFitAtEveryTextSize() {
        DMFitCheck.assertFits("command block", width: DMCardWidth.sheet) {
            DMCommandBlock(["devmachine packages add docker --machine main", "devmachine sync --machine main"])
        }
        DMFitCheck.assertFits("search field", width: DMCardWidth.sheetSmall) {
            DMSearchField(prompt: "Find a file", text: .constant("dash")) {
                Text(verbatim: "42").font(.dm(10))
            }
        }
        DMFitCheck.assertFits("field", width: DMCardWidth.sheetSmall) {
            TextField("example.com", text: .constant("example.com")).dmField()
        }
        DMFitCheck.assertFits("progress bar", width: DMCardWidth.toast) {
            DMProgressBar(done: 3, total: 8)
        }
        DMFitCheck.assertFits("flow layout", width: DMCardWidth.toast) {
            FlowLayout {
                ForEach(["review", "test", "plan", "commit", "publish"], id: \.self) { title in
                    DMChip(title: title, selected: false) {}
                }
            }
        }
    }

    func testCardsFitAtEveryTextSize() {
        DMFitCheck.assertFits("toast") {
            DMToastCard(task: BGTask(id: UUID(), label: "Sending mockup.png", completed: 3, total: 8))
        }
        DMFitCheck.assertFits("job card") {
            DMJobCard(title: "Publishing app.example.com…", status: .attention, steps: [
                DMJobStep(id: "dns", title: "Create the DNS record by hand", state: .attention, detail: "app A 203.0.113.10"),
                DMJobStep(id: "caddy", title: "Caddy route pending", state: .attention, detail: "box could not be reached"),
            ])
        }
        let phases: [(String, MachineJob, Bool)] = [
            ("pending", MachineJobFixtures.job(.pending), false),
            ("pending full", MachineJobFixtures.job(.pending), true),
            ("queued", MachineJobFixtures.job(.queued), false),
            ("running", MachineJobFixtures.job(.running(step: 0)), false),
            ("running expanded", MachineJobFixtures.job(.running(step: 0), expanded: true), false),
            ("succeeded", MachineJobFixtures.succeeded, false),
            ("failed", MachineJobFixtures.failed, false),
        ]
        for (name, job, startsFull) in phases {
            DMFitCheck.assertFits("machine job \(name)") {
                MachineJobToast(job: job, startsFull: startsFull, actions: MachineJobFixtures.actions)
            }
        }
        DMFitCheck.assertFits("age label") {
            DMAgeLabel(since: Date().addingTimeInterval(-600))
        }
        DMFitCheck.assertFits("stat bubble", width: 180) {
            DMStatBubble(value: "14.8 / 31 GB", label: "Memory")
        }
    }

    func testSkeletonsFitAtEveryTextSize() {
        DMFitCheck.assertFits("skeleton", width: DMPaneWidth.sidebar.ideal) {
            DMSkeleton {
                VStack(alignment: .leading, spacing: DMSpace.sm) {
                    DMSkeletonText(size: 13, width: .fraction(0.6))
                    DMSkeletonText(size: 11, width: .fixed(54))
                    DMSkeletonBlock(width: .fixed(40), height: 12)
                }
            }
        }
    }
}
