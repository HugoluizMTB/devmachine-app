import Foundation
import WebKit
import DevmachineCore

/// Saves what a preview downloads into the Downloads folder, under a name
/// that never replaces a file already there, and says where it went.
@MainActor
final class PreviewDownloader: NSObject, WKDownloadDelegate {
    private let folder: @MainActor () -> URL
    private let fileExists: (URL) -> Bool
    private let finished: @MainActor (URL) -> Void
    private let failed: @MainActor (String) -> Void
    private var reserved: Set<URL> = []
    private var destinations: [ObjectIdentifier: URL] = [:]

    init(
        folder: @escaping @MainActor () -> URL = { PreviewDownloader.downloadsFolder() },
        fileExists: @escaping (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
        finished: @escaping @MainActor (URL) -> Void = { PreviewDownloader.announce($0) },
        failed: @escaping @MainActor (String) -> Void = { PreviewDownloader.announceFailure($0) }
    ) {
        self.folder = folder
        self.fileExists = fileExists
        self.finished = finished
        self.failed = failed
    }

    /// Two downloads with the same name at once would both find it free, so a
    /// name is taken here from the moment it is handed out.
    func destination(for suggested: String) -> URL {
        let url = DownloadName.available(suggested, in: folder()) { [reserved, fileExists] in
            reserved.contains($0) || fileExists($0)
        }
        reserved.insert(url)
        return url
    }

    func release(_ url: URL) {
        reserved.remove(url)
    }

    nonisolated func download(
        _ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
        completionHandler: @escaping @MainActor @Sendable (URL?) -> Void
    ) {
        MainActor.assumeIsolated {
            let url = destination(for: suggestedFilename)
            destinations[ObjectIdentifier(download)] = url
            completionHandler(url)
        }
    }

    nonisolated func downloadDidFinish(_ download: WKDownload) {
        MainActor.assumeIsolated {
            guard let url = destinations.removeValue(forKey: ObjectIdentifier(download)) else { return }
            release(url)
            finished(url)
        }
    }

    nonisolated func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        MainActor.assumeIsolated {
            if let url = destinations.removeValue(forKey: ObjectIdentifier(download)) { release(url) }
            failed(error.localizedDescription)
        }
    }

    /// `DEVMACHINE_PREVIEW_DOWNLOADS` points a demo build's downloads at a
    /// scratch folder, so a check never writes into the real Downloads.
    static func downloadsFolder() -> URL {
        if DemoMode.isActive, let path = ProcessInfo.processInfo.environment["DEVMACHINE_PREVIEW_DOWNLOADS"],
           !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    }

    /// The same card a download from the Files tab shows.
    static func announce(_ url: URL) {
        FileTransferStore.shared.show(TransferNotice(
            title: "Saved to \(FileTransfer.displayPath(url.path))", detail: nil, reveal: url, failed: false))
    }

    static func announceFailure(_ reason: String) {
        FileTransferStore.shared.show(TransferNotice(
            title: "Could not download the file", detail: reason, reveal: nil, failed: true))
    }
}
