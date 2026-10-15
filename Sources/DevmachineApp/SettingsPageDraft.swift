import Foundation
import DevmachineCore

/// What the Settings page holds before Save. It lives on `SettingsStore`, not
/// in the page's `@State`: a font size preview rebuilds the whole window, and
/// the page must come back with every unsaved field as it was.
@MainActor
final class SettingsPageDraft: ObservableObject {
    /// Set once the page filled the fields from the saved settings, so a
    /// rebuild does not fill them again over the person's edits.
    var isLoaded = false

    @Published var section: SettingsSection
    /// Set by "Packages on this machine" in Settings → Machines.
    @Published var packagesPage: PackagesPageState?

    @Published var opsRepoPath = ""
    @Published var hostAlias = ""
    @Published var publicIP = ""
    @Published var baseDomain = ""
    @Published var sshAgentSocket = ""
    @Published var wallpaper = WallpaperChoice.bundled
    @Published var themeID: String?
    /// The last photo and gradient picked, so going to the map and back
    /// returns to them instead of a default.
    @Published var lastPhoto: WallpaperChoice?
    @Published var lastGradient: WallpaperChoice?
    @Published var terminalOpacity = Appearance.defaultTerminalOpacity
    @Published var terminalFontSize = Appearance.defaultTerminalFontSize
    @Published var uiFontScale = Appearance.defaultUIFontScale
    @Published var keptTerminals = Appearance.defaultKeptTerminals
    @Published var debugLogging = false
    @Published var remoteTerminalMode = RemoteTerminalMode.automatic
    @Published var copyOnSelect = true
    @Published var showsHarnessIcons = false
    @Published var showsBusySpinner = true
    @Published var showsBranch = true
    @Published var showsSessionAge = true
    @Published var showsAttention = true
    @Published var harnessIconStyle = HarnessIconStyle.color
    @Published var linkOpening = LinkOpening.defaultBrowser
    @Published var hiddenWorkspaces: [String] = []
    @Published var enabledHarnesses = AppSettings.empty.enabledHarnesses
    @Published var localSessionProgram = SessionLaunchChoice.terminal
    @Published var remoteSessionProgram = SessionLaunchChoice.terminal
    @Published var workspaceSessionPrograms: [String: SessionLaunchChoice] = [:]
    @Published var operatorProgram: SessionLaunchChoice?
    @Published var operatorSessionEnabled = true
    @Published var harnessErrors: [HarnessID: String] = [:]
    /// Connection fields opened for typing. A field with a value shows it
    /// read-only until "Edit": what the CLI reports is rarely changed.
    @Published var editing: Set<SettingsIssue.Field> = []

    init(section: SettingsSection = .general) {
        self.section = section
    }
}
