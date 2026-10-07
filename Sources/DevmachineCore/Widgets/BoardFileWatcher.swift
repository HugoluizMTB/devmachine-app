import Foundation

/// Watches a board's folder (the CLI and the store save by renaming a
/// temporary file) and the file itself (an editor that writes in place).
/// Bursts settle briefly so one save is one reload.
@MainActor
public final class BoardFileWatcher {
    public static let settle: TimeInterval = 0.15

    public let fileURL: URL
    private let onChange: @MainActor () -> Void
    private var folderSource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?

    public init(fileURL: URL, onChange: @escaping @MainActor () -> Void) {
        self.fileURL = fileURL
        self.onChange = onChange
        folderSource = source(fileURL.deletingLastPathComponent().path)
        watchFile()
    }

    public var isWatching: Bool { folderSource != nil }

    deinit {
        folderSource?.cancel()
        fileSource?.cancel()
    }

    private func watchFile() {
        fileSource?.cancel()
        fileSource = source(fileURL.path)
    }

    private func source(_ path: String) -> DispatchSourceFileSystemObject? {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .rename, .delete, .extend], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.changed() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return source
    }

    private func changed() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.watchFile()
                self?.onChange()
            }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settle, execute: work)
    }
}
