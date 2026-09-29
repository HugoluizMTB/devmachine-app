import Foundation

/// Which context user a container or a port belongs to. The app hides what
/// belongs to a workspace you turned off, and for that it has to know the
/// owner of each row, which neither `docker stats` nor the Caddyfile says.
public enum Ownership {
    /// `/home/<user>/…` is how this host lays out context users, so the folder
    /// a container was started from names its owner.
    public static func user(fromHome path: String) -> String? {
        guard path.hasPrefix("/home/") else { return nil }
        let rest = path.dropFirst("/home/".count)
        let name = rest.prefix { $0 != "/" }
        return name.isEmpty ? nil : String(name)
    }

    /// The owner of a container: the folder it was started from, or its name
    /// when that begins with a context user's name — `acme-pg` and the like,
    /// started by hand and carrying no label. A name that matches no known user
    /// is left without an owner rather than guessed at.
    public static func owner(
        ofContainer name: String, labelled: String?, knownUsers: Set<String>
    ) -> String? {
        if let labelled { return labelled }
        for user in knownUsers where name.hasPrefix(user + "-") || name == user {
            return user
        }
        return nil
    }

}

/// The port a Caddy site forwards to, which is how a domain is tied to whoever
/// runs that port.
public enum CaddySiteOwnership {
    public static func port(of target: String) -> Int? {
        guard let colon = target.lastIndex(of: ":") else { return nil }
        let digits = target[target.index(after: colon)...].prefix { $0.isNumber }
        return Int(digits)
    }
}
