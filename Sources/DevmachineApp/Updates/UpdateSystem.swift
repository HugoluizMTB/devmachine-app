import AppKit
import DevmachineCore
import Foundation
import Security

struct URLSessionHTTPFetcher: HTTPFetching {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration)
    }()

    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        var fields: [String: String] = [:]
        for case let (key as String, value as String) in http.allHeaderFields { fields[key] = value }
        return HTTPResponse(status: http.statusCode, headers: fields, body: data)
    }
}

protocol UpdateDownloading: Sendable {
    func download(
        _ url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL
}

final class URLSessionDownloader: NSObject, UpdateDownloading, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var destination: URL?
    private var progress: (@Sendable (Double) -> Void)?
    private var continuation: CheckedContinuation<URL, Error>?
    private var moveError: Error?

    func download(
        _ url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                self.destination = destination
                self.progress = progress
                self.continuation = continuation
                self.moveError = nil
            }
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let report = lock.withLock { progress }
        report?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let destination = lock.withLock { self.destination }
        guard let destination else { return }
        do {
            if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
                throw ReleaseFeedError.httpStatus(http.statusCode)
            }
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            lock.withLock { moveError = error }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let (continuation, destination, moveError) = lock.withLock {
            defer { self.continuation = nil }
            return (self.continuation, self.destination, self.moveError)
        }
        if let failure = error ?? moveError {
            continuation?.resume(throwing: failure)
        } else if let destination {
            continuation?.resume(returning: destination)
        }
    }
}

/// Reads signatures through the Security framework and runs Apple's own
/// `codesign` and `spctl`. It only reads: no keychain item is created or
/// changed.
struct SystemCodeSignatureChecker: CodeSignatureChecking {
    var runner: any CommandRunner = ProcessRunner()

    func verifySignature(of app: URL) throws {
        let result = try runner.runCapturing(
            executable: "/usr/bin/codesign", args: ["--verify", "--deep", "--strict", app.path], environment: nil)
        guard result.exitCode == 0 else {
            throw UpdateInstallError.signatureInvalid(Self.detail(result))
        }
    }

    func teamIdentifier(of app: URL) throws -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else {
            throw UpdateInstallError.signatureInvalid("the Security framework could not read \(app.lastPathComponent)")
        }
        return Self.teamIdentifier(of: code)
    }

    func assessGatekeeper(of app: URL) throws {
        let result = try runner.runCapturing(
            executable: "/usr/sbin/spctl", args: ["--assess", "--type", "execute", app.path], environment: nil)
        guard result.exitCode == 0 else {
            throw UpdateInstallError.gatekeeperRejected(Self.detail(result))
        }
    }

    static func runningTeamIdentifier() -> String? {
        var running: SecCode?
        var code: SecStaticCode?
        guard SecCodeCopySelf([], &running) == errSecSuccess, let running,
              SecCodeCopyStaticCode(running, [], &code) == errSecSuccess, let code
        else { return nil }
        return teamIdentifier(of: code)
    }

    private static func teamIdentifier(of code: SecStaticCode) -> String? {
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
                == errSecSuccess,
              let info = info as? [String: Any]
        else { return nil }
        return info[kSecCodeInfoTeamIdentifier as String] as? String
    }

    private static func detail(_ result: (stdout: String, stderr: String, exitCode: Int32)) -> String {
        let text = (result.stderr.isEmpty ? result.stdout : result.stderr)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "exit status \(result.exitCode)" : text
    }
}

struct DiskImageUpdateInstaller: AppUpdateInstalling {
    let currentApp: URL
    let bundleID: String
    let runningTeamID: String?
    var signatures: any CodeSignatureChecking = SystemCodeSignatureChecker()
    var swapper = BundleSwapper()
    var downloader: any UpdateDownloading = URLSessionDownloader()
    var fetcher: any HTTPFetching = URLSessionHTTPFetcher()
    var runner: any CommandRunner = ProcessRunner()

    func install(
        release: GitHubRelease, progress: @escaping @Sendable (UpdateProgress) -> Void
    ) async throws -> ManualInstallOutcome {
        guard let version = release.version, let image = release.appDiskImage else {
            throw UpdateInstallError.noDiskImage(version: release.version?.description ?? release.tagName)
        }
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("devmachine-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        do {
            let dmg = try await downloader.download(
                image.downloadURL, to: work.appendingPathComponent(image.name),
                progress: { progress(.downloading($0)) })
            progress(.verifying)
            if let expected = try await expectedDigest(release) {
                try ReleaseDigest.verify(fileAt: dmg, expected: expected)
            }
            let outcome = try installMounted(dmg, work: work, version: version, progress: progress)
            if case .replaced = outcome { try? FileManager.default.removeItem(at: work) }
            return outcome
        } catch {
            try? FileManager.default.removeItem(at: work)
            throw error
        }
    }

    private func installMounted(
        _ dmg: URL, work: URL, version: SemanticVersion, progress: @Sendable (UpdateProgress) -> Void
    ) throws -> ManualInstallOutcome {
        let mountPoint = try mount(dmg, in: work)
        defer { _ = try? runner.runCapturing(
            executable: "/usr/bin/hdiutil", args: DiskImage.detachArguments(mountPoint: mountPoint), environment: nil) }
        let app = try appBundle(in: mountPoint)
        try UpdateBundleVerifier(expectedBundleID: bundleID, runningTeamID: runningTeamID, signatures: signatures)
            .verify(app: app, info: BundleInfo.read(appAt: app), expectedVersion: version)

        progress(.installing)
        guard swapper.canReplace(currentApp) else {
            let copy = work.appendingPathComponent(app.lastPathComponent)
            try FileManager.default.copyItem(at: app, to: copy)
            return .needsManualMove(copy)
        }
        let staged = try swapper.stage(app, beside: currentApp)
        do {
            try signatures.verifySignature(of: staged)
        } catch {
            try? FileManager.default.removeItem(at: staged)
            throw error
        }
        try swapper.swap(staged, into: currentApp)
        return .replaced(currentApp)
    }

    /// The `.sha256` asset wins; releases made before it existed carry the
    /// digest in their notes. When the asset is there it must be readable.
    private func expectedDigest(_ release: GitHubRelease) async throws -> String? {
        guard let asset = release.appDiskImageDigest else { return release.bodyDigest }
        let response = try await fetcher.get(asset.downloadURL, headers: ["User-Agent": "Devmachine"])
        guard response.status == 200, let digest = ReleaseDigest.parse(String(decoding: response.body, as: UTF8.self))
        else { throw UpdateInstallError.digestMismatch(expected: "a readable \(asset.name)", actual: "HTTP \(response.status)") }
        return digest
    }

    private func mount(_ dmg: URL, in work: URL) throws -> URL {
        let root = work.appendingPathComponent("mount")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let result = try runner.runCapturing(
            executable: "/usr/bin/hdiutil", args: DiskImage.attachArguments(image: dmg, mountRoot: root),
            environment: nil)
        guard result.exitCode == 0, let point = DiskImage.mountPoint(fromAttachOutput: Data(result.stdout.utf8)) else {
            throw UpdateInstallError.mountFailed(result.stderr.isEmpty ? "hdiutil exited \(result.exitCode)" : result.stderr)
        }
        return point
    }

    private func appBundle(in mountPoint: URL) throws -> URL {
        let preferred = mountPoint.appendingPathComponent("Devmachine.app")
        if FileManager.default.fileExists(atPath: preferred.path) { return preferred }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: mountPoint.path)) ?? []
        guard let name = names.first(where: { $0.hasSuffix(".app") }) else { throw UpdateInstallError.noAppInImage }
        return mountPoint.appendingPathComponent(name)
    }
}

/// Runs `brew upgrade --cask` in the background and hands every line of its
/// output back as it comes.
struct ProcessHomebrewUpgrader: HomebrewUpgrading {
    func upgrade(brew: String, output: @escaping @Sendable (String) -> Void) async throws {
        var environment = ProcessInfo.processInfo.environment
        let brewBin = URL(fileURLWithPath: brew).deletingLastPathComponent().path
        environment["PATH"] = "\(brewBin):/usr/bin:/bin:/usr/sbin:/sbin"
        environment["HOMEBREW_NO_ENV_HINTS"] = "1"
        environment["HOMEBREW_NO_COLOR"] = "1"
        let status = try await StreamingProcess.run(
            executable: brew, arguments: HomebrewAppUpgrade.arguments, environment: environment, output: output)
        guard status == 0 else { throw UpdateInstallError.homebrewFailed(status) }
    }
}

/// Runs `devmachine update --cli-only` in the background, never in a
/// terminal session, and hands every line of its output back as it comes.
struct ProcessCLIUpdater: CLIUpdating {
    var executable: @Sendable () throws -> String = { try DevmachineCLI.resolve().executable }
    var environment: [String: String] = ProcessInfo.processInfo.environment

    func updateCLI(output: @escaping @Sendable (String) -> Void) async throws {
        let status = try await StreamingProcess.run(
            executable: try executable(), arguments: CLISelfUpdate.arguments,
            environment: CLISelfUpdate.environment(base: environment), output: output)
        guard status == 0 else { throw CLIUpdateError.exited(status) }
    }
}

/// stdout and stderr share one pipe, so the lines keep the order they were
/// written in. stdin is closed, so a prompt fails instead of waiting forever.
enum StreamingProcess {
    static func run(
        executable: String, arguments: [String], environment: [String: String],
        output: @escaping @Sendable (String) -> Void
    ) async throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let lines = LineSplitter(emit: output)
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                lines.append(data)
            }
        }
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
        pipe.fileHandleForReading.readabilityHandler = nil
        lines.append(pipe.fileHandleForReading.readDataToEndOfFile())
        lines.flush()
        return status
    }
}

private final class LineSplitter: @unchecked Sendable {
    private let emit: @Sendable (String) -> Void
    private let lock = NSLock()
    private var buffer = Data()

    init(emit: @escaping @Sendable (String) -> Void) {
        self.emit = emit
    }

    func append(_ data: Data) {
        let complete: [String] = lock.withLock {
            buffer.append(data)
            var found: [String] = []
            while let newline = buffer.firstIndex(of: 0x0A) {
                found.append(String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self))
                buffer.removeSubrange(buffer.startIndex...newline)
            }
            return found
        }
        complete.filter { !$0.isEmpty }.forEach(emit)
    }

    func flush() {
        let rest = lock.withLock {
            defer { buffer.removeAll() }
            return String(decoding: buffer, as: UTF8.self)
        }
        if !rest.isEmpty { emit(rest) }
    }
}

/// Starts the helper that reopens the app, then quits. AppKit refuses to
/// quit while any window has a sheet attached ("App termination blocked by
/// modal sheet"), and the update dialog is one, so every sheet is ended first.
@MainActor
struct AppRelauncher {
    var spawnHelper: (RelaunchCommand) throws -> Void = { command in
        try DetachedProcess.spawn(executable: command.executable, arguments: command.arguments)
    }
    var closeSheets: () -> Void = { SheetCloser.closeAll(in: NSApp.windows) }
    var terminate: () -> Void = { NSApp.terminate(nil) }
    var processID = ProcessInfo.processInfo.processIdentifier

    func relaunch(_ app: URL) throws {
        try spawnHelper(RelaunchCommand(appPath: app.path, processID: processID))
        closeSheets()
        terminate()
    }
}

enum SheetCloser {
    @MainActor
    static func closeAll(in windows: [NSWindow]) {
        for window in windows {
            guard let sheet = window.attachedSheet else { continue }
            closeAll(in: [sheet])
            window.endSheet(sheet)
        }
    }
}

extension UpdateController {
    static func live() -> UpdateController {
        let bundle = Bundle.main
        let version = (bundle.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap { SemanticVersion($0) }
        let isPackaged = bundle.bundleURL.pathExtension == "app"
        let userAgent = "Devmachine/\(version?.description ?? "dev")"
        let fetcher = URLSessionHTTPFetcher()
        let team = SystemCodeSignatureChecker.runningTeamIdentifier()
        let appURL = bundle.bundleURL
        #if DEBUG
        if let replacement = RelaunchRehearsal.replacement {
            return RelaunchRehearsal.controller(replacing: appURL, with: replacement)
        }
        #endif
        return UpdateController(dependencies: UpdateDependencies(
            currentVersion: isPackaged && !DemoMode.isActive ? version : nil,
            appFeed: ReleaseFeed(url: ReleaseFeed.appReleases, fetcher: fetcher, userAgent: userAgent),
            cliFeed: ReleaseFeed(url: ReleaseFeed.cliReleases, fetcher: fetcher, userAgent: userAgent),
            preferences: UpdatePreferences(),
            detectInstallMethod: { AppInstallMethodDetector(bundlePath: appURL.path).detect() },
            runningTeamID: team,
            cliVersion: {
                guard let cli = try? DevmachineCLI.resolve(), let output = try? cli.version() else { return nil }
                let resolved = URL(fileURLWithPath: cli.executable).resolvingSymlinksInPath().path
                return CLIVersionReading(output: output, method: CLIUpdateAdvice.installMethod(resolvedPath: resolved))
            },
            installer: DiskImageUpdateInstaller(
                currentApp: appURL, bundleID: bundle.bundleIdentifier ?? "app.devmachine.mac", runningTeamID: team),
            homebrew: ProcessHomebrewUpgrader(),
            cliUpdater: ProcessCLIUpdater(),
            currentAppURL: appURL,
            relaunch: { try AppRelauncher().relaunch($0) }))
    }
}
