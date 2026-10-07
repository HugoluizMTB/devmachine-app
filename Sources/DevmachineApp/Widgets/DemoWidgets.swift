import Foundation
import DevmachineCore

extension DemoData {
    /// Demo-only sample catalog, so website screenshots draw Home without a
    /// CLI. Real Home always reads the catalog from `devmachine widgets list`.
    static let widgetCatalog = WidgetCatalog(engine: "1.0", packagesRelease: "v39", widgets: [
        CatalogWidget(
            name: "devmachine-app/clock", summary: "The time, the date and this Mac's name.",
            source: CatalogSource(name: "app/clock", every: "60s"), viewKind: "app.clock",
            sizes: ["small", "medium", "wide"], defaultSize: "medium"),
        CatalogWidget(
            name: "devmachine-app/summary", summary: "Sessions, harness sessions and workspaces.",
            source: CatalogSource(name: "app/summary", every: "30s"), viewKind: "app.summary",
            sizes: ["medium", "wide"], defaultSize: "wide"),
        CatalogWidget(
            name: "devmachine-app/machines", summary: "Each machine's load, memory and disk.",
            source: CatalogSource(name: "app/machines", every: "90s"), viewKind: "app.machines",
            sizes: ["medium", "large", "tall"], defaultSize: "large"),
        demoUsage(package: "claude-code", harness: "claude"),
        demoUsage(package: "codex", harness: "codex"),
        CatalogWidget(
            name: "github/open-prs", summary: "Pull requests waiting on you.",
            source: CatalogSource(name: "github/open-prs", every: "5m"), viewKind: "list",
            sizes: ["medium", "tall"], defaultSize: "medium", available: false,
            unavailableReason: "add the package: devmachine packages add github --machine <name>"),
    ])

    private static func demoUsage(package: String, harness: String) -> CatalogWidget {
        CatalogWidget(
            name: "\(package)/usage", summary: "Coding-harness usage windows.",
            source: CatalogSource(name: "app/harness-usage", with: ["harness": harness], every: "60s"),
            viewKind: "app.harness-usage", sizes: ["small", "medium", "wide"], defaultSize: "medium",
            path: "/Users/alice/.config/devmachine/cache/packages/v39/\(package)/widgets/usage")
    }
}
