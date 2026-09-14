import Foundation
import DevmachineCore

struct AddSubdomainStepError: LocalizedError {
    let step: String
    let detail: String
    var errorDescription: String? { "\(step): \(detail)" }
}

private struct ShellExecutor: Sendable {
    let runner: CommandRunner
    let repoPath: String

    func shell(_ command: String) throws -> (stdout: String, stderr: String, exitCode: Int32) {
        let sock = RemoteCommands.onePasswordSocketPath
        let full = "export SSH_AUTH_SOCK='\(sock)'; cd '\(repoPath)' && \(command)"
        return try runner.runCapturing(executable: "/bin/zsh", args: ["-lc", full], environment: nil)
    }
}

private func tail(_ text: String, _ limit: Int = 600) -> String {
    String(text.suffix(limit))
}

@MainActor
final class AddSubdomainRunner {
    private let executor: ShellExecutor
    private let remote: RemoteService
    private let settings: AppSettings

    init(
        settings: AppSettings,
        runner: CommandRunner = ProcessRunner(),
        remote: RemoteService = RemoteService()
    ) {
        self.executor = ShellExecutor(runner: runner, repoPath: settings.opsRepoPath)
        self.remote = remote
        self.settings = settings
    }

    static func stepCount(for req: SubdomainRequest) -> Int {
        req.managedDNS ? 6 : 5
    }

    func run(_ req: SubdomainRequest, progress: @escaping (String, Int) -> Void) async -> Result<Void, Error> {
        var step = 0

        step += 1
        progress("Syncing repo…", step)
        if let error = await Self.syncRepo(executor) {
            return .failure(error)
        }

        if req.managedDNS {
            step += 1
            progress("Adding DNS on Hostinger…", step)
            if let error = await Self.addDNS(executor, req, settings) {
                return .failure(error)
            }
        }

        step += 1
        progress("Editing Caddyfile…", step)
        if let error = await Self.editCaddyfile(executor, req) {
            return .failure(error)
        }

        step += 1
        progress("Applying Caddy…", step)
        if let error = await Self.applyCaddy(executor) {
            return .failure(error)
        }

        step += 1
        progress("Waiting for TLS…", step)
        await Self.waitForTLS(executor, remote, req, settings.hostAlias)

        step += 1
        progress("Committing…", step)
        if let error = await Self.commitAndPush(executor, req) {
            return .failure(error)
        }

        return .success(())
    }

    private nonisolated static func syncRepo(_ executor: ShellExecutor) async -> Error? {
        await Task.detached {
            do {
                let fetch = try executor.shell("git fetch origin")
                if fetch.exitCode != 0 {
                    return AddSubdomainStepError(step: "Sync", detail: tail(fetch.stderr))
                }

                func readState() throws -> (String, String, String) {
                    let head = try executor.shell("git rev-parse HEAD")
                    let remoteHead = try executor.shell("git rev-parse origin/main")
                    let porcelain = try executor.shell("git status --porcelain")
                    return (head.stdout, remoteHead.stdout, porcelain.stdout)
                }

                var (head, remoteHead, porcelain) = try readState()
                if !CaddyAdd.isCleanAndSynced(porcelain: porcelain, localHead: head, remoteHead: remoteHead) {
                    _ = try executor.shell("git rebase origin/main")
                    (head, remoteHead, porcelain) = try readState()
                    if !CaddyAdd.isCleanAndSynced(porcelain: porcelain, localHead: head, remoteHead: remoteHead) {
                        return AddSubdomainStepError(
                            step: "Sync",
                            detail: "working tree not clean or not synced with origin/main; resolve manually"
                        )
                    }
                }
                return nil
            } catch {
                return AddSubdomainStepError(step: "Sync", detail: "\(error)")
            }
        }.value
    }

    private nonisolated static func addDNS(
        _ executor: ShellExecutor, _ req: SubdomainRequest, _ settings: AppSettings
    ) async -> Error? {
        await Task.detached {
            do {
                let curl = CaddyAdd.hostingerCurl(
                    req, baseDomain: settings.baseDomain, ip: settings.publicIP
                )
                let result = try executor.shell(curl)
                let lowerStdout = result.stdout.lowercased()
                if result.exitCode != 0 || lowerStdout.contains("unauthenticated") || lowerStdout.contains("error") {
                    return AddSubdomainStepError(step: "DNS", detail: tail(result.stdout + result.stderr))
                }
                return nil
            } catch {
                return AddSubdomainStepError(step: "DNS", detail: "\(error)")
            }
        }.value
    }

    private nonisolated static func editCaddyfile(_ executor: ShellExecutor, _ req: SubdomainRequest) async -> Error? {
        await Task.detached {
            let path = executor.repoPath + "/ansible/roles/caddy/files/Caddyfile"
            do {
                let content = try String(contentsOfFile: path, encoding: .utf8)
                let updated = try CaddyAdd.appendBlock(to: content, req: req)
                try updated.write(toFile: path, atomically: true, encoding: .utf8)
                return nil
            } catch CaddyAddError.alreadyExists {
                return AddSubdomainStepError(step: "Caddyfile", detail: "subdomain already in Caddyfile")
            } catch {
                return AddSubdomainStepError(step: "Caddyfile", detail: "\(error)")
            }
        }.value
    }

    private nonisolated static func applyCaddy(_ executor: ShellExecutor) async -> Error? {
        await Task.detached {
            do {
                let result = try executor.shell(CaddyAdd.ansibleApply())
                if result.exitCode != 0 {
                    return AddSubdomainStepError(step: "Ansible apply", detail: tail(result.stderr))
                }
                return nil
            } catch {
                return AddSubdomainStepError(step: "Ansible apply", detail: "\(error)")
            }
        }.value
    }

    private nonisolated static func waitForTLS(
        _ executor: ShellExecutor, _ remote: RemoteService, _ req: SubdomainRequest, _ hostAlias: String
    ) async {
        let host = req.host
        for _ in 0..<9 {
            let done: Bool = await Task.detached {
                if let logs = try? remote.run(alias: hostAlias, args: ["journalctl -u caddy -n 40 --no-pager"]) {
                    let lowerLogs = logs.lowercased()
                    if lowerLogs.contains(host.lowercased())
                        && (lowerLogs.contains("acme") || lowerLogs.contains("certificate obtained")) {
                        return true
                    }
                }
                if let result = try? executor.shell("curl -sI https://\(host)"), result.exitCode == 0 {
                    return true
                }
                return false
            }.value

            if done { return }
            try? await Task.sleep(nanoseconds: 10_000_000_000)
        }
    }

    private nonisolated static func commitAndPush(_ executor: ShellExecutor, _ req: SubdomainRequest) async -> Error? {
        await Task.detached {
            do {
                let hostingPath = executor.repoPath + "/docs/hosting.md"
                let existing = (try? String(contentsOfFile: hostingPath, encoding: .utf8)) ?? ""
                let updated = existing + "\n" + CaddyAdd.hostingRow(req)
                try updated.write(toFile: hostingPath, atomically: true, encoding: .utf8)

                let commitMessage = "feat(caddy): \(req.host) (porta \(req.port))"
                let command = "git add ansible/roles/caddy/files/Caddyfile docs/hosting.md"
                    + " && git commit -m '\(commitMessage)'"
                    + " && git push"
                let result = try executor.shell(command)
                if result.exitCode != 0 {
                    return AddSubdomainStepError(step: "Commit", detail: tail(result.stderr))
                }
                return nil
            } catch {
                return AddSubdomainStepError(step: "Commit", detail: "\(error)")
            }
        }.value
    }
}
