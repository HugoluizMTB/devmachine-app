import Foundation

/// Deleting a worktree that holds files the session's account does not own,
/// as the machine's admin. Offered only for a remote devmachine machine and a
/// path inside the account's home (`/home/<user>`, `/Users/<user>` on a Mac);
/// everything else gets the commands to run by
/// hand. The admin deletes the folder and nothing else: pruning git's record
/// and the branch stay with the user.
public enum WorktreeAdminRemoval {
    public struct Machine: Equatable, Sendable {
        public let name: String
        public let isSelf: Bool
        /// The system the CLI last read from it (`Linux`, `Darwin`); nil
        /// when it was never read.
        public let system: String?

        public init(name: String, isSelf: Bool, system: String? = nil) {
            self.name = name
            self.isSelf = isSelf
            self.system = system
        }
    }

    public enum ManualReason: Equatable, Sendable {
        case thisMac, selfMachine, noCLI, outsideHome

        public var text: String {
            switch self {
            case .thisMac: return "On this Mac the app never deletes as an administrator."
            case .selfMachine: return "This machine is this computer, so the app does not act as its admin."
            case .noCLI: return "The devmachine CLI can't reach this machine's admin from here."
            case .outsideHome: return "The worktree is outside the account's home folder."
            }
        }
    }

    public enum Route: Equatable, Sendable {
        case admin(machine: String)
        case manual(ManualReason)
    }

    public static func route(
        isLocalSession: Bool, machine: Machine?, user: String, path: String, mainWorktree: String
    ) -> Route {
        if isLocalSession { return .manual(.thisMac) }
        let root = MachineHome.root(system: machine?.system)
        guard isInsideHome(path, user: user, homeRoot: root), isInsideHome(mainWorktree, user: user, homeRoot: root),
              WorktreeRemoval.isRemovablePath(path, mainWorktree: mainWorktree)
        else { return .manual(.outsideHome) }
        guard let machine else { return .manual(.noCLI) }
        if machine.isSelf { return .manual(.selfMachine) }
        return .admin(machine: machine.name)
    }

    public static func canRemove(_ check: WorktreeCheck, options: WorktreeRemoval.Options, route: Route) -> Bool {
        guard case .admin = route, options.removeAsAdmin else { return false }
        return WorktreeRemoval.canRemove(check, options: options)
    }

    private static let userPattern = #"^[a-z_][a-z0-9_-]{0,31}$"#

    /// Strictly below `<homeRoot>/<user>/`, written the way `realpath` prints
    /// it: no `.` or `..` part, no empty part, no trailing slash, no newline.
    public static func isInsideHome(_ path: String, user: String, homeRoot: String = "/home") -> Bool {
        guard user.range(of: userPattern, options: .regularExpression) != nil else { return false }
        let home = "\(homeRoot)/\(user)/"
        guard path.hasPrefix(home), !path.hasSuffix("/"), !path.contains("\n") else { return false }
        let parts = path.dropFirst(home.count).split(separator: "/", omittingEmptySubsequences: false)
        return !parts.isEmpty && parts.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    /// `sh -c` with the values as base64 arguments, so no character of a path
    /// reaches a shell as syntax. It checks again on the machine, as root,
    /// before deleting: both paths canonical and inside the home, the folder
    /// not a mount point, and its `.git` file pointing into the main
    /// checkout's `.git/worktrees`. git deletes that file early when a remove
    /// fails halfway, so a folder with no `.git` at all passes only directly
    /// inside the main checkout's `.worktrees`. A folder already gone is
    /// success. On a Mac (`system` Darwin) the home is under `/Users` and
    /// the tools are BSD's.
    public static func script(path: String, mainWorktree: String, user: String, system: String? = nil) -> String? {
        script(path: path, mainWorktree: mainWorktree, user: user, homeRoot: MachineHome.root(system: system),
               tools: system == "Darwin" ? .bsd : .gnu)
    }

    static func script(path: String, mainWorktree: String, user: String, homeRoot: String, tools: Tools) -> String? {
        guard isInsideHome(path, user: user, homeRoot: homeRoot),
              isInsideHome(mainWorktree, user: user, homeRoot: homeRoot),
              WorktreeRemoval.isRemovablePath(path, mainWorktree: mainWorktree)
        else { return nil }
        let values = [path, mainWorktree, user].map { Data($0.utf8).base64EncodedString() }
        return "sh -c " + RemoteCommands.shellSingleQuoted(body(homeRoot: homeRoot, tools: tools))
            + " sh " + values.joined(separator: " ")
    }

    /// GNU and BSD spell the same checks differently: a Mac has no
    /// `realpath -e` or `mountpoint`, its `rm` stays on one file system with
    /// `-x`, and before macOS 13 `base64 -d` meant debug, not decode.
    struct Tools {
        let decode: String
        let resolve: @Sendable (String) -> String
        let isMountPoint: String
        let oneFileSystem: String

        static let gnu = Tools(
            decode: "base64 -d",
            resolve: { "$r realpath -e -- \"\($0)\"" },
            isMountPoint: "$r mountpoint -q -- \"$p\"",
            oneFileSystem: "--one-file-system")

        static let bsd = Tools(
            decode: "base64 -D",
            resolve: { "$r sh -c 'cd -P -- \"$1\" && pwd -P' sh \"\($0)\"" },
            isMountPoint: "[ \"$($r stat -f %d -- \"$p\")\" != \"$($r stat -f %d -- \"$(dirname -- \"$p\")\")\" ]",
            oneFileSystem: "-x")
    }

    private static func body(homeRoot: String, tools: Tools) -> String {
        let decode = tools.decode
        return """
        set -eu
        p=$(printf %s "$1" | \(decode)); m=$(printf %s "$2" | \(decode)); u=$(printf %s "$3" | \(decode))
        fail() { printf 'refused: %s\\n' "$*" >&2; exit 3; }
        if [ "$(id -u)" -eq 0 ]; then r=; else r='sudo -n'; fi
        h=\(RemoteCommands.shellSingleQuoted(homeRoot))/$u
        id -u -- "$u" >/dev/null 2>&1 || fail "no account named $u"
        $r test -e "$p" || { echo "already gone: $p"; exit 0; }
        [ "$(\(tools.resolve("$p")))" = "$p" ] || fail "$p is not a plain path (a link on the way?)"
        [ "$(\(tools.resolve("$m")))" = "$m" ] || fail "$m is not a plain path (a link on the way?)"
        case "$p" in "$h"/*) ;; *) fail "$p is outside $h";; esac
        case "$m" in "$h"/*) ;; *) fail "$m is outside $h";; esac
        case "$m/" in "$p"/*) fail "$p holds the main checkout";; esac
        $r test -d "$m/.git" || fail "$m is not a repository"
        $r test -d "$p" || fail "$p is not a folder"
        if \(tools.isMountPoint); then fail "$p is a mount point"; fi
        if $r test -f "$p/.git"; then
          g=$($r sed -n 's/^gitdir: //p' "$p/.git" | head -n 1)
          case "$g" in "$m"/.git/worktrees/*) ;; *) fail "$p is not a worktree of $m";; esac
        elif $r test -e "$p/.git"; then
          fail "$p holds its own repository"
        elif [ "$(dirname -- "$p")" != "$m/.worktrees" ]; then
          fail "$p has no .git file and is not in $m/.worktrees, so it can't be proved to be a worktree"
        fi
        $r rm -rf \(tools.oneFileSystem) -- "$p"
        echo "removed: $p"
        """
    }

    /// Back as the user, after the admin deleted the folder: git's record
    /// goes with `prune`, which skips a locked worktree, so a consented lock
    /// is lifted first.
    public static func afterAdminCommand(path: String, mainWorktree: String, unlock: Bool, branch: String?) -> String {
        var command = "cd \(quote(mainWorktree))"
        if unlock {
            command += " && { git worktree unlock -- \(quote(path)) 2>/dev/null || true; }"
        }
        command += " && git worktree prune"
        if let branch {
            command += " && git branch -d -- \(quote(branch))"
        }
        return command
    }

    public struct ManualSteps: Equatable, Sendable {
        public let asAdmin: String
        public let asUser: String
    }

    /// What to run by hand when the app will not: GNU `rm` stays on one file
    /// system; the Mac's `rm` has no such flag.
    public static func manualSteps(
        path: String, mainWorktree: String, isLocalSession: Bool, system: String? = nil
    ) -> ManualSteps {
        let gnu = !isLocalSession && system != "Darwin"
        return ManualSteps(
            asAdmin: "sudo rm -rf" + (gnu ? " --one-file-system" : "") + " -- \(quote(path))",
            asUser: "git -C \(quote(mainWorktree)) worktree prune")
    }

    private static func quote(_ value: String) -> String {
        RemoteCommands.shellSingleQuoted(value)
    }
}
