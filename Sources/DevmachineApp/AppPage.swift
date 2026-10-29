import Foundation
import DevmachineCore
enum AppPage: Hashable {
    case setup
    case stats
    case subdomains
    case scheduled
    case sessionGrid([SessionRef])
    /// The Add machine wizard.
    case addMachine
    /// Starting the Operator: which installed harness to run, `last` selected.
    case operatorChooser([HarnessID], last: SessionLaunchChoice?)
}

enum AppMode: String {
    case chats
    case code
    case schedule

    private static let key = "appMode"

    static func saved(_ defaults: UserDefaults = .standard) -> AppMode {
        guard !DemoMode.isActive, NSClassFromString("XCTestCase") == nil else { return .code }
        return AppMode(rawValue: defaults.string(forKey: key) ?? "") ?? .code
    }

    static func save(_ mode: AppMode, _ defaults: UserDefaults = .standard) {
        guard !DemoMode.isActive, NSClassFromString("XCTestCase") == nil else { return }
        defaults.set(mode.rawValue, forKey: key)
    }
}
