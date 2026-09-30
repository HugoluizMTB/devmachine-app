import AppKit
import DevmachineCore

/// Puts a file where the session's agent can read it, under its own name plus
/// the time, and answers with the absolute path to hand over.
struct FileUploadService {
    let runner: CommandRunner
    let storagePolicy: UploadStoragePolicy
    var localHome = URL(fileURLWithPath: NSHomeDirectory())

    enum Failure: Error, Equatable {
        case transferFailed(String)
    }

    enum PastedImage: Equatable {
        case file(URL)
        case bitmap(Data)
    }

    /// A screenshot arrives as bitmap data; an image copied in Finder arrives
    /// as a file URL, and keeps its name.
    static func pastedImage(from pasteboard: NSPasteboard) -> PastedImage? {
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let file = urls.first,
           ["png", "jpg", "jpeg", "gif", "webp"].contains(file.pathExtension.lowercased()) {
            return .file(file)
        }
        if let png = pasteboard.data(forType: .png) { return .bitmap(png) }
        if let tiff = pasteboard.data(forType: .tiff),
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            return .bitmap(png)
        }
        return nil
    }

    /// Writes the bytes on the machine that runs the session and returns the
    /// path there. A remote write is one ssh command that also prints the path,
    /// so the app never has to guess the remote home.
    func store(
        _ data: Data, name: UploadName, on kind: TerminalKind,
        onBytesWritten: (@Sendable (Int) -> Void)? = nil
    ) throws -> String {
        switch kind {
        case let .remote(alias, _):
            let command = FileUpload.writeCommand(name: name, policy: storagePolicy)
            let result = try runner.runCapturing(
                executable: "/usr/bin/ssh",
                args: RemoteCommands.sshBaseArgs(alias: alias) + [command],
                environment: RemoteCommands.sshEnvironment(),
                input: data,
                onBytesWritten: onBytesWritten
            )
            guard result.exitCode == 0,
                  let path = FileUpload.writtenPath(from: result.stdout, name: name)
            else {
                let details = [result.stderr, result.stdout]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
                throw Failure.transferFailed(
                    details.isEmpty ? "ssh exited with status \(result.exitCode)" : details)
            }
            return path
        case .local:
            let dir = localHome.appendingPathComponent(storagePolicy.directory)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var n = 1
            while FileManager.default.fileExists(atPath: dir.appendingPathComponent(name.numbered(n)).path) {
                n += 1
            }
            let file = dir.appendingPathComponent(name.numbered(n))
            try data.write(to: file, options: .withoutOverwriting)
            onBytesWritten?(data.count)
            return file.path
        }
    }
}
