import Foundation
import DevmachineCore

struct FileService: Sendable {
    let host: HostRunner

    init(host: HostRunner = HostRunner()) {
        self.host = host
    }

    func list(_ target: CommandTarget, path: String) throws -> [FileEntry] {
        let output = try host.runCapturingAnywhere(target, listCommand(path: path)).stdout
        return FileListParser.parse(output)
    }

    // A single quoted remote command string, since ssh joins argv into one
    // shell command on the remote side — passing "path" as a separate ssh
    // argv element would not stop the remote shell from re-splitting it.
    func listCommand(path: String) -> String {
        "ls -Ap -- \(RemoteCommands.shellSingleQuoted(path))"
    }

    // scp reuses the ssh config's ControlMaster automatically, so no extra
    // connection options are needed here. The remote path is expanded by a
    // shell on the remote host, so it gets the same single-quoting as the
    // ssh command string in `listCommand` (the local path is a plain argv
    // element to /usr/bin/scp and needs no quoting).
    func downloadArgs(alias: String, remotePath: String, localPath: String) -> [String] {
        ["\(alias):\(RemoteCommands.shellSingleQuoted(remotePath))", localPath]
    }

    func uploadArgs(alias: String, localPath: String, remotePath: String) -> [String] {
        [localPath, "\(alias):\(RemoteCommands.shellSingleQuoted(remotePath))"]
    }
}
