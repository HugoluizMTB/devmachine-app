import Foundation

/// Deleting a worktree that holds files the session's account does not own,
/// as the machine's admin. Offered only for a remote devmachine machine and a
/// path inside `/home/<user>`; everything else gets the commands to run by
/// hand. The admin deletes the folder and nothing else: pruning git's record
/// and the branch stay with the user.
public enum WorktreeAdminRemoval {
    public struct Machine: Equatable, Sendable {
        public let name: String
        public let isSelf: Bool

        public init(name: String, isSelf: Bool) {
            self.name = name
            self.isSelf = isSelf
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
        guard isInsideHome(path, user: user), isInsideHome(mainWorktree, user: user),
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

    /// Strictly below `/home/<user>/`, written the way `realpath` prints it:
    /// no `.` or `..` part, no empty part, no trailing slash, no newline.
    public static func isInsideHome(_ path: String, user: String) -> Bool {
        guard user.range(of: userPattern, options: .regularExpression) != nil else { return false }
        let home = "/home/\(user)/"
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
    /// success.
    public static func script(path: String, mainWorktree: String, user: String) -> String? {
        guard isInsideHome(path, user: user), isInsideHome(mainWorktree, user: user),
              WorktreeRemoval.isRemovablePath(path, mainWorktree: mainWorktree)
        else { return nil }
        let values = [path, mainWorktree, user].map { Data($0.utf8).base64EncodedString() }
        return "sh -c " + RemoteCommands.shellSingleQuoted(body) + " sh " + values.joined(separator: " ")
    }

    private static let body = """
        set -eu
        p=$(printf %s "$1" | base64 -d); m=$(printf %s "$2" | base64 -d); u=$(printf %s "$3" | base64 -d)
        fail() { printf 'refused: %s\\n' "$*" >&2; exit 3; }
        if [ "$(id -u)" -eq 0 ]; then r=; else r='sudo -n'; fi
        h=/home/$u
        id -u -- "$u" >/dev/null 2>&1 || fail "no account named $u"
        $r test -e "$p" || { echo "already gone: $p"; exit 0; }
        [ "$($r realpath -e -- "$p")" = "$p" ] || fail "$p is not a plain path (a link on the way?)"
        [ "$($r realpath -e -- "$m")" = "$m" ] || fail "$m is not a plain path (a link on the way?)"
        case "$p" in "$h"/*) ;; *) fail "$p is outside $h";; esac
        case "$m" in "$h"/*) ;; *) fail "$m is outside $h";; esac
        case "$m/" in "$p"/*) fail "$p holds the main checkout";; esac
        $r test -d "$m/.git" || fail "$m is not a repository"
        $r test -d "$p" || fail "$p is not a folder"
        if $r mountpoint -q -- "$p"; then fail "$p is a mount point"; fi
        if $r test -f "$p/.git"; then
          g=$($r sed -n 's/^gitdir: //p' "$p/.git" | head -n 1)
          case "$g" in "$m"/.git/worktrees/*) ;; *) fail "$p is not a worktree of $m";; esac
        elif $r test -e "$p/.git"; then
          fail "$p holds its own repository"
        elif [ "$(dirname -- "$p")" != "$m/.worktrees" ]; then
          fail "$p has no .git file and is not in $m/.worktrees, so it can't be proved to be a worktree"
        fi
        $r rm -rf --one-file-system -- "$p"
        echo "removed: $p"
        """

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
    public static func manualSteps(path: String, mainWorktree: String, isLocalSession: Bool) -> ManualSteps {
        ManualSteps(
            asAdmin: "sudo rm -rf" + (isLocalSession ? "" : " --one-file-system") + " -- \(quote(path))",
            asUser: "git -C \(quote(mainWorktree)) worktree prune")
    }

    private static func quote(_ value: String) -> String {
        RemoteCommands.shellSingleQuoted(value)
    }
}
