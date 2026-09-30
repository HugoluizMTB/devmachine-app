import Foundation

public enum DiskImage {
    public static func attachArguments(image: URL, mountRoot: URL) -> [String] {
        ["attach", "-nobrowse", "-readonly", "-noautoopen", "-noverify",
         "-mountroot", mountRoot.path, "-plist", image.path]
    }

    public static func detachArguments(mountPoint: URL) -> [String] {
        ["detach", mountPoint.path, "-force"]
    }

    public static func mountPoint(fromAttachOutput data: Data) -> URL? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]]
        else { return nil }
        return entities.lazy.compactMap { $0["mount-point"] as? String }.first.map(URL.init(fileURLWithPath:))
    }
}

/// Opens a new copy once this process has quit. The path and the pid are
/// arguments, never part of the script text, so no character of either
/// reaches the shell as code.
public struct RelaunchCommand: Equatable, Sendable {
    public let executable = "/bin/sh"
    public let arguments: [String]

    public init(appPath: String, processID: Int32) {
        let script = """
        i=0; while kill -0 "$1" 2>/dev/null && [ $i -lt 100 ]; do sleep 0.2; i=$((i+1)); done; \
        sleep 1; /usr/bin/open -n "$0"
        """
        arguments = ["-c", script, appPath, String(processID)]
    }
}
