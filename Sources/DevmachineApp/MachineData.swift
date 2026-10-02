import Foundation
import DevmachineCore

/// What the Subdomains page reads once for every machine, kept whole in the
/// cache so the page draws its machines, domain and owners at once.
struct SitesContextSnapshot: Codable, Equatable, Sendable {
    var machines: [CLIMachine]
    var domain: String
    var workspaces: [CLIWorkspace]
    var installedPackages: [CLIPackage]?

    var context: SitesContext {
        SitesContext(domain: domain, workspaces: workspaces, installedPackages: installedPackages)
    }
}

/// Every key the app caches machine data under. Two views that show the
/// same data read the same key, so one fetch serves both.
enum MachineDataKeys {
    static let workspaces = CacheKey<[CLIWorkspace]>(.workspaces, "cli")
    static let sitesContext = CacheKey<SitesContextSnapshot>(.sitesContext, "cli")

    static func sites(_ machine: String) -> CacheKey<ExposureListing> { .init(.sites, machine) }
    static func dnsProviders(_ machine: String) -> CacheKey<[DNSProviderAnswer]> { .init(.dnsProviders, machine) }
    static func dnsRecords(machine: String, provider: String, zone: String) -> CacheKey<[DNSRecordRow]> {
        .init(.dnsRecords, "\(machine)|\(provider)|\(zone)")
    }
    static func dnsRecordsPrefix(machine: String) -> String { "\(machine)|" }
    static func sessions(_ alias: String) -> CacheKey<[TmuxSession]> { .init(.sessions, alias) }
    static func context(_ targetKey: String) -> CacheKey<ContextState> { .init(.context, targetKey) }
}

extension DataCache {
    /// The cache every store of the running app shares, on disk next to the
    /// stats cache. Under XCTest it stays in memory, so no test reads or
    /// writes the owner's file.
    static let shared = DataCache(
        file: NSClassFromString("XCTestCase") == nil ? CacheFile(fileURL: CacheFile.defaultFileURL) : nil)
}
