import Foundation

/// A workspace's name is its Linux account's (`useradd` on the machine), so
/// it follows the CLI's `linuxUserName` rule and Linux's 32-character limit,
/// and cannot be an account the machine already has. The Add machine
/// wizard's first workspace and the Workspaces page both check it here.
public enum WorkspaceName {
    public static let pattern = "^[a-z_][a-z0-9_-]*$"
    public static let maxLength = 32
    public static let example = "acme"
    public static let systemAccounts: Set<String> = [
        "root", "daemon", "bin", "sys", "sync", "games", "man", "lp", "mail", "news", "uucp", "proxy",
        "www-data", "backup", "list", "irc", "nobody", "messagebus", "sshd", "syslog", "ubuntu", "admin",
        "caddy", "docker", "lima",
    ]

    /// What the CLI would refuse about `name`, or nil. `adminUser` is the
    /// machine's admin login, an account there too.
    public static func problem(_ name: String, adminUser: String? = nil, existing: [String]) -> String? {
        let name = name.trimmingCharacters(in: .whitespaces)
        if name.isEmpty {
            return "Give the workspace a name, like \(example)."
        }
        if name.range(of: pattern, options: .regularExpression) == nil {
            return "Start with a letter, then use lower-case letters, digits, - and _."
        }
        if name.count > maxLength {
            return "Use \(maxLength) characters or fewer: it becomes an account name on the machine."
        }
        if systemAccounts.contains(name) || name == adminUser {
            return "\(name) is already an account on the machine. Pick another, like \(example)."
        }
        if existing.contains(name) {
            return "A workspace named \(name) already exists."
        }
        return nil
    }
}
