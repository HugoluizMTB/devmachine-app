import Foundation

/// A copy of one harness's fixture home (`Tests/Fixtures/Context/<name>`,
/// laid out as under `$HOME`) in a temporary folder, so a test may change
/// it and nothing reads the real home.
enum ContextFixtureHome {
    static let widgets = URL(fileURLWithPath: "/Users/alice/dev/widgets")
    static let gadgets = URL(fileURLWithPath: "/Users/alice/dev/gadgets")

    static func copy(_ name: String) throws -> URL {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Context").appendingPathComponent(name)
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("context-\(name)-" + UUID().uuidString)
        try FileManager.default.copyItem(at: source, to: home)
        return home
    }
}
