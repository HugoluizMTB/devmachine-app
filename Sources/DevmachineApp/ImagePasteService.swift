import AppKit
import DevmachineCore

/// Puts an image from the Mac's clipboard where the session's agent can read
/// it, and answers with the absolute path to hand over.
struct ImagePasteService {
    let runner: CommandRunner
    let storagePolicy: ImageStoragePolicy

    enum Failure: Error {
        case noImage
        case transferFailed(String)
    }

    /// PNG bytes plus the extension to store them under. A screenshot arrives
    /// as bitmap data; an image copied in Finder arrives as a file URL.
    static func image(from pasteboard: NSPasteboard) -> (data: Data, fileExtension: String)? {
        if let url = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
           let file = url.first,
           ["png", "jpg", "jpeg", "gif", "webp"].contains(file.pathExtension.lowercased()),
           let data = try? Data(contentsOf: file) {
            return (data, file.pathExtension.lowercased())
        }
        if let png = pasteboard.data(forType: .png) { return (png, "png") }
        if let tiff = pasteboard.data(forType: .tiff),
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            return (png, "png")
        }
        return nil
    }

    /// Writes the bytes on the machine that runs the session and returns the
    /// path there. A remote write goes through one ssh command that also prints
    /// the path, so the app never has to guess the remote home.
    func store(
        _ data: Data, fileExtension: String, on kind: TerminalKind,
        onBytesWritten: (@Sendable (Int) -> Void)? = nil
    ) throws -> String {
        let name = ImagePaste.fileName(date: Date(), fileExtension: fileExtension, tail: Self.tail())
        switch kind {
        case let .remote(alias, _):
            let out = try runner.run(
                executable: "/usr/bin/ssh",
                args: RemoteCommands.sshBaseArgs(alias: alias) + [
                    ImagePaste.writeCommand(fileName: name, policy: storagePolicy)
                ],
                environment: RemoteCommands.sshEnvironment(),
                input: data,
                onBytesWritten: onBytesWritten
            )
            let path = out.trimmingCharacters(in: .whitespacesAndNewlines)
            guard path.hasPrefix("/") else { throw Failure.transferFailed(path) }
            return path
        case .local:
            let dir = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent(storagePolicy.directory)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent(name)
            try data.write(to: file)
            onBytesWritten?(data.count)
            return file.path
        }
    }

    private static func tail() -> String {
        String(format: "%04x", UInt16.random(in: 0...UInt16.max))
    }
}
