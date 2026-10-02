import Foundation
import DevmachineCore

struct LimaInstallError: LocalizedError, Equatable {
    let message: String
    var errorDescription: String? { message }
}

/// Installs Lima for a machine on this Mac, the way `LimaInstall` says: the
/// release tarball, checked against `SHA256SUMS` before a byte of it is
/// unpacked, or `brew install lima`. Every system call is a closure, so a
/// test downloads, runs and writes nothing.
struct LimaInstaller: Sendable {
    var home: String
    /// What `uname -m` would say for this Mac's processor.
    var machine: String
    var fetch: @Sendable (URL) async throws -> Data
    /// Runs a program with each line of its output as it comes; answers the exit status.
    var run: @Sendable (String, [String], @escaping @Sendable (String) -> Void) async throws -> Int32
    /// Writes the checked tarball to a temporary file and answers its path.
    var write: @Sendable (Data) throws -> String
    var makeDirectory: @Sendable (String) throws -> Void
    var exists: @Sendable (String) -> Bool

    func install(_ method: LimaInstall.Method, output: @escaping @Sendable (String) -> Void) async throws {
        switch method {
        case .release: try await installRelease(output: output)
        case let .homebrew(brew): try await installWithHomebrew(brew, output: output)
        }
        guard let limactl = LimaTool.find(home: home, exists: exists) else {
            throw LimaInstallError(message: "Lima was installed, but limactl is not where it should be.")
        }
        _ = try? await run(limactl, ["--version"], output)
    }

    private func installRelease(output: @escaping @Sendable (String) -> Void) async throws {
        output("Asking GitHub for Lima's latest release…")
        guard let tag = LimaInstall.tag(fromLatestRelease: try await fetch(LimaInstall.latestReleaseURL)),
              let release = LimaInstall.release(tag: tag, machine: machine)
        else { throw LimaInstallError(message: "GitHub did not say which Lima release is the latest.") }
        output("Downloading \(release.asset) and its checksums…")
        let sums = String(decoding: try await fetch(release.checksumsURL), as: UTF8.self)
        let tarball = try await fetch(release.tarballURL)
        output(String(format: "Downloaded %.1f MB.", Double(tarball.count) / 1_000_000))
        let digest = LimaInstall.sha256(tarball)
        let check = LimaInstall.check(digest: digest, sums: sums, asset: release.asset)
        if let problem = check.problem { throw LimaInstallError(message: problem) }
        output("SHA-256 matches Lima's SHA256SUMS: \(digest)")
        let path = try write(tarball)
        try makeDirectory(LimaInstall.prefix(home: home))
        output("Unpacking into \(LimaInstall.prefix(home: home))…")
        let status = try await run("/usr/bin/tar", LimaInstall.extractArguments(tarball: path, home: home), output)
        guard status == 0 else { throw LimaInstallError(message: "tar could not unpack Lima (exit \(status)).") }
    }

    private func installWithHomebrew(_ brew: String, output: @escaping @Sendable (String) -> Void) async throws {
        output("$ brew install lima")
        let status = try await run(brew, LimaInstall.homebrewArguments, output)
        guard status == 0 else {
            throw LimaInstallError(message: "brew install lima ended with exit code \(status). The log shows why.")
        }
    }
}

extension LimaInstaller {
    static let brewPaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]

    static func findBrew(exists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> String? {
        brewPaths.first(where: exists)
    }

    /// Apple silicon answers yes even to a process under Rosetta.
    static var thisMac: String {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let found = sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0
        return found && value == 1 ? "arm64" : "x86_64"
    }

    static var live: LimaInstaller {
        LimaInstaller(
            home: NSHomeDirectory(), machine: thisMac,
            fetch: { url in
                let (data, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw LimaInstallError(message: "\(url.host ?? "GitHub") answered \(http.statusCode) for \(url.lastPathComponent).")
                }
                return data
            },
            run: { executable, arguments, output in
                try await StreamingProcess.run(
                    executable: executable, arguments: arguments,
                    environment: CLISelfUpdate.environment(base: ProcessInfo.processInfo.environment),
                    output: output)
            },
            write: { data in
                let file = FileManager.default.temporaryDirectory
                    .appendingPathComponent("lima-\(UUID().uuidString).tar.gz")
                try data.write(to: file)
                return file.path
            },
            makeDirectory: { try FileManager.default.createDirectory(atPath: $0, withIntermediateDirectories: true) },
            exists: { FileManager.default.isExecutableFile(atPath: $0) })
    }
}
