import AppKit
import DevmachineCore

struct OpenPanelOptions: Equatable {
    var allowsMultipleSelection: Bool
    var allowsDirectories: Bool
}

struct Credentials: Equatable {
    let user: String
    let password: String
}

/// Every question a page makes the browser ask. A bare web view answers none
/// of them: an alert vanished, a confirm said no, a file input did nothing.
@MainActor
protocol PreviewPrompting: AnyObject {
    func alert(title: String, message: String, in window: NSWindow?, done: @escaping () -> Void)
    func ask(_ message: PreviewDialogText.Message, confirm: String, in window: NSWindow?, done: @escaping (Bool) -> Void)
    func prompt(title: String, message: String, defaultText: String?, in window: NSWindow?,
                done: @escaping (String?) -> Void)
    func credentials(_ message: PreviewDialogText.Message, in window: NSWindow?, done: @escaping (Credentials?) -> Void)
    func openFiles(_ options: OpenPanelOptions, in window: NSWindow?, done: @escaping ([URL]?) -> Void)
}

/// Sheets on the window the page is in, so a question never outlives or
/// hides behind it.
@MainActor
class SheetPreviewPrompts: PreviewPrompting {
    func alert(title: String, message: String, in window: NSWindow?, done: @escaping () -> Void) {
        let alert = Self.makeAlert(title: title, message: message, buttons: ["OK"])
        present(alert, in: window) { _ in done() }
    }

    func ask(_ message: PreviewDialogText.Message, confirm: String, in window: NSWindow?, done: @escaping (Bool) -> Void) {
        let alert = Self.makeAlert(title: message.title, message: message.body, buttons: [confirm, "Cancel"])
        present(alert, in: window) { done($0 == .alertFirstButtonReturn) }
    }

    func prompt(title: String, message: String, defaultText: String?, in window: NSWindow?,
                done: @escaping (String?) -> Void) {
        let alert = Self.makeAlert(title: title, message: message, buttons: ["OK", "Cancel"])
        let field = NSTextField(string: defaultText ?? "")
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 22)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        present(alert, in: window) { done($0 == .alertFirstButtonReturn ? field.stringValue : nil) }
    }

    func credentials(_ message: PreviewDialogText.Message, in window: NSWindow?, done: @escaping (Credentials?) -> Void) {
        let alert = Self.makeAlert(title: message.title, message: message.body, buttons: ["Log In", "Cancel"])
        let user = NSTextField(string: "")
        user.placeholderString = "User name"
        let password = NSSecureTextField(string: "")
        password.placeholderString = "Password"
        let stack = NSStackView(views: [user, password])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 280, height: 52)
        for field in [user, password] {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: 280).isActive = true
        }
        alert.accessoryView = stack
        alert.window.initialFirstResponder = user
        present(alert, in: window) { response in
            guard response == .alertFirstButtonReturn else { return done(nil) }
            done(Credentials(user: user.stringValue, password: password.stringValue))
        }
    }

    func openFiles(_ options: OpenPanelOptions, in window: NSWindow?, done: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = options.allowsMultipleSelection
        panel.canChooseDirectories = options.allowsDirectories
        panel.canChooseFiles = true
        let finish: (NSApplication.ModalResponse) -> Void = { done($0 == .OK ? panel.urls : nil) }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            panel.begin(completionHandler: finish)
        }
    }

    static func makeAlert(title: String, message: String, buttons: [String]) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        for button in buttons { alert.addButton(withTitle: button) }
        return alert
    }

    private func present(_ alert: NSAlert, in window: NSWindow?,
                         done: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window {
            alert.beginSheetModal(for: window, completionHandler: done)
        } else {
            done(alert.runModal())
        }
    }
}
