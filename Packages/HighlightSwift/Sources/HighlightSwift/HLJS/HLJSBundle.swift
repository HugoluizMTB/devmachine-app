import Foundation

// Not `Bundle.module`: SwiftPM's generated accessor calls `fatalError` when the
// bundle is neither at the .app root, where codesign forbids files, nor at the
// build machine's path baked in at compile time, so every shipped app crashed.
enum HLJSBundle {
    static let name = "HighlightSwift_HighlightSwift.bundle"

    static var candidateDirectories: [URL] {
        var directories = [Bundle.main.resourceURL, Bundle.main.bundleURL].compactMap { $0 }
        for bundle in [Bundle.main, Bundle(for: Highlight.self)] where bundle.bundleURL.pathExtension == "xctest" {
            directories.append(bundle.bundleURL.deletingLastPathComponent())
        }
        return directories
    }

    static func scriptPath(in directories: [URL] = candidateDirectories) throws -> String {
        for directory in directories {
            if let path = Bundle(url: directory.appendingPathComponent(name))?
                .path(forResource: "highlight.min", ofType: "js") {
                return path
            }
        }
        throw HLJSError.fileNotFound
    }
}
