import Foundation

public protocol FileMoving: Sendable {
    func copyItem(at source: URL, to destination: URL) throws
    func moveItem(at source: URL, to destination: URL) throws
    func removeItem(at url: URL) throws
}

extension FileManager: @retroactive @unchecked Sendable {}
extension FileManager: FileMoving {}

/// Replaces an app bundle in two renames inside one folder, so the app is
/// never half copied: the new copy is staged beside the old one first, and a
/// failed second rename puts the old bundle back.
public struct BundleSwapper: Sendable {
    let files: any FileMoving
    let isWritable: @Sendable (String) -> Bool

    public init(
        files: any FileMoving = FileManager.default,
        isWritable: @escaping @Sendable (String) -> Bool = { FileManager.default.isWritableFile(atPath: $0) }
    ) {
        self.files = files
        self.isWritable = isWritable
    }

    public func canReplace(_ current: URL) -> Bool {
        isWritable(current.deletingLastPathComponent().path) && isWritable(current.path)
    }

    public func stage(_ source: URL, beside current: URL) throws -> URL {
        let staged = sibling(of: current, tag: "update")
        do {
            try files.copyItem(at: source, to: staged)
        } catch {
            try? files.removeItem(at: staged)
            throw error
        }
        return staged
    }

    public func swap(_ staged: URL, into current: URL) throws {
        let aside = sibling(of: current, tag: "old")
        do {
            try files.moveItem(at: current, to: aside)
        } catch {
            try? files.removeItem(at: staged)
            throw UpdateInstallError.swapFailed(rolledBack: false, reason: error.localizedDescription)
        }
        do {
            try files.moveItem(at: staged, to: current)
        } catch {
            let rolledBack = (try? files.moveItem(at: aside, to: current)) != nil
            try? files.removeItem(at: staged)
            throw UpdateInstallError.swapFailed(rolledBack: rolledBack, reason: error.localizedDescription)
        }
        try? files.removeItem(at: aside)
    }

    private func sibling(of current: URL, tag: String) -> URL {
        current.deletingLastPathComponent()
            .appendingPathComponent(".\(current.lastPathComponent).\(tag)-\(UUID().uuidString)")
    }
}
