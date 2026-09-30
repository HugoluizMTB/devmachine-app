import Darwin
import Foundation

public enum DetachedProcessError: Error, LocalizedError, Equatable {
    case spawnFailed(executable: String, code: Int32)

    public var errorDescription: String? {
        switch self {
        case .spawnFailed(let executable, let code):
            return "could not start \(executable): \(String(cString: strerror(code)))"
        }
    }
}

/// Starts a program that must outlive the app, such as the relaunch helper.
/// It gets its own session, so nothing aimed at the app's process group
/// reaches it, and none of the app's open files, so it holds no terminal or
/// socket open after the app has quit.
public enum DetachedProcess {
    @discardableResult
    public static func spawn(executable: String, arguments: [String]) throws -> pid_t {
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        for descriptor in [STDIN_FILENO, STDOUT_FILENO, STDERR_FILENO] {
            posix_spawn_file_actions_addopen(
                &actions, descriptor, "/dev/null", descriptor == STDIN_FILENO ? O_RDONLY : O_WRONLY, 0)
        }

        let argv = ([executable] + arguments).map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var pid: pid_t = 0
        let code = posix_spawn(&pid, executable, &actions, &attributes, argv, environ)
        guard code == 0 else { throw DetachedProcessError.spawnFailed(executable: executable, code: code) }
        DispatchQueue.global(qos: .utility).async {
            var status: Int32 = 0
            _ = waitpid(pid, &status, 0)
        }
        return pid
    }
}
