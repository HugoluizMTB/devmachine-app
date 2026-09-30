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

/// Opens the app once this process has quit. The path, the pid and the
/// opener are arguments, never part of the script text, so no character of
/// them reaches the shell as code. If this process is still running when the
/// wait ends, it opens nothing: a second copy beside a stuck one is worse
/// than none, and the app offers "Quit and Reopen" instead.
public struct RelaunchCommand: Equatable, Sendable {
    public let executable = "/bin/sh"
    public let arguments: [String]

    public init(
        appPath: String, processID: Int32, attempts: Int = 150, settle: Int = 1, opener: String = "/usr/bin/open"
    ) {
        let script = """
        i=0; while kill -0 "$1" 2>/dev/null; do \
        [ $i -ge \(attempts) ] && exit 1; sleep 0.2; i=$((i+1)); done; \
        sleep \(settle); exec "$2" "$0"
        """
        arguments = ["-c", script, appPath, String(processID), opener]
    }
}
