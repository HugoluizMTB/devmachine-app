@testable import DevmachineCore

enum CatalogFixtures {
    static let clock = CatalogWidget(
        name: "devmachine-app/clock", summary: "The time.", source: CatalogSource(name: "app/clock", every: "60s"),
        viewKind: "app.clock", sizes: ["small", "medium"], defaultSize: "medium")
    static let summary = CatalogWidget(
        name: "devmachine-app/summary", summary: "Counts.", source: CatalogSource(name: "app/summary", every: "30s"),
        viewKind: "app.summary", sizes: ["medium", "wide"], defaultSize: "wide")
    static let machines = CatalogWidget(
        name: "devmachine-app/machines", summary: "Machines.", source: CatalogSource(name: "app/machines", every: "90s"),
        viewKind: "app.machines", sizes: ["medium", "large", "tall"], defaultSize: "large")

    static func usage(package: String, harness: String) -> CatalogWidget {
        CatalogWidget(
            name: "\(package)/usage", summary: "Coding-harness usage windows.",
            inputs: ["harness": CatalogInput(type: "string", defaultValue: .string(harness), summary: "Which harness.")],
            source: CatalogSource(name: "app/harness-usage", with: ["harness": "{{inputs.harness}}"], every: "60s"),
            viewKind: "app.harness-usage", sizes: ["small", "medium", "wide"], defaultSize: "medium")
    }

    static func catalog(_ widgets: [CatalogWidget], release: String = "v39") -> WidgetCatalog {
        WidgetCatalog(engine: "1.0", packagesRelease: release, widgets: widgets)
    }
}
