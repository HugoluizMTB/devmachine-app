import Foundation

/// What the Local workspace shows: what the app remembers, plus whatever the
/// multiplexer is already running.
public enum LocalSessionScan {
    /// Remembered sessions keep their place and their folder. A session the
    /// multiplexer has and the app does not — started from a shell, or left by
    /// an older version — is appended, so the sidebar shows the machine as it
    /// is, not as the app last wrote it down.
    public static func merge(
        stored: [LocalSession], live: [ZmxSession], fallbackPath: String,
        socketDirectory: String = Zmx.socketDirectory()
    ) -> [LocalSession] {
        var seen = Set<String>()
        let rows = stored.filter { seen.insert($0.handle).inserted }
        let known = Set(rows.map {
            Zmx.sessionName(from: $0.handle, socketDirectory: socketDirectory)
        })
        let extra = live
            .filter { !known.contains($0.name) }
            .map { LocalSession(name: $0.name, path: $0.directory ?? fallbackPath) }
        return rows + extra
    }

    /// The multiplexer name a session runs under, which is what `zmx ls` prints.
    public static func multiplexerName(
        of session: LocalSession, socketDirectory: String = Zmx.socketDirectory()
    ) -> String {
        Zmx.sessionName(from: session.handle, socketDirectory: socketDirectory)
    }
}
