import Foundation

/// The native, in-process port of `devmachine-infer` for the local machine:
/// finds the session's transcript, extracts references, and (optionally)
/// resolves GitHub state, producing the same JSON-shaped result the Python
/// package returns for a remote workspace.
public struct NativeContextEngine: Sendable {
    private let runner: any CommandRunner
    private nonisolated(unsafe) let fileManager: FileManager
    private let resolver: ContextGitHubResolver
    private let githubHosts: [String]
    private let roots: ContextRoots
    private let processNames: [HarnessID: Set<String>]

    /// `processNames` maps each harness to the programs it runs as, so a
    /// pane command names its harness exactly.
    public init(
        runner: any CommandRunner = ProcessRunner(),
        fileManager: FileManager = .default,
        resolver: ContextGitHubResolver = ContextGitHubResolver(),
        githubHosts: [String] = ContextGitHubConfig.allHosts(),
        roots: ContextRoots = ContextRoots(),
        processNames: [HarnessID: Set<String>] = [:]
    ) {
        self.runner = runner
        self.fileManager = fileManager
        self.resolver = resolver
        self.githubHosts = githubHosts
        self.roots = roots
        self.processNames = processNames
    }

    /// `harnesses` are the ones already seen running in the session; their
    /// transcripts win over a newer one another harness wrote here.
    public func buildContext(
        cwd: String, paneCommand: String? = nil, harnesses: Set<HarnessID> = [],
        resolvePRs: Bool = true, now: Date = Date()
    ) -> ContextEngineResult {
        let project = URL(fileURLWithPath: cwd)
        guard let detection = ContextHarnessDetection.detect(
            project: project, paneCommand: paneCommand, harnesses: harnesses, roots: roots,
            processNames: processNames, fileManager: fileManager
        ), let primary = detection.transcripts.first,
            let reader = roots.readers.first(where: { $0.harness == detection.harness })
        else {
            return emptyResult(cwd: project.path, now: now)
        }

        let repo = defaultRepo(project: project)
        var refs = ContextExtractedRefs()
        var primaryPass: ContextHarnessPass?

        for (index, file) in detection.transcripts.enumerated() {
            let pass = reader.pass(for: file)
            refs.merge(contextExtractRefs(blobs: pass.blobs, defaultRepo: repo, githubHosts: githubHosts))
            if index == 0 { primaryPass = pass }
        }
        let pass = primaryPass ?? reader.pass(for: primary)

        let githubRefs = refs.github.values.sorted { $0.repo + "#\($0.num)" < $1.repo + "#\($1.num)" }
        let prs: [ContextEngineResult.PR]
        if resolvePRs {
            prs = contextMapPRs(resolver.resolve(githubRefs, now: now))
        } else {
            prs = contextMapPRs(githubRefs.map(unresolvedPR))
        }

        let links = refs.links
            .map { (url: $0.key, count: $0.value.count, lastTimestamp: $0.value.lastTimestamp) }
            .sorted { $0.url < $1.url }
        let mappedLinks = contextMapLinks(links)

        let plan: ContextEngineResult.Plan? = pass.todoItems.isEmpty
            ? ContextPlanFile.mostRecent(project: project, touchedMarkdown: pass.touchedMarkdown, fileManager: fileManager)
            : ContextEngineResult.Plan(title: "todos", source: "todos", items: pass.todoItems)

        return ContextEngineResult(
            cwd: project.path, harness: detection.harness, updatedAt: isoNow(now), plan: plan, prs: prs,
            links: mappedLinks, agents: pass.agents, monitors: pass.monitors, shells: pass.shells
        )
    }

    private func unresolvedPR(_ ref: ContextGitHubRef) -> ContextGitHubPR {
        ContextGitHubPR(
            host: ref.host, repo: ref.repo, num: ref.num, url: ref.url, lastTimestamp: ref.lastTimestamp,
            title: "", isDraft: false, state: "open", review: nil, ci: "none", threads: nil
        )
    }

    private func emptyResult(cwd: String, now: Date) -> ContextEngineResult {
        ContextEngineResult(cwd: cwd, harness: nil, updatedAt: isoNow(now), plan: nil, prs: [], links: [])
    }

    private func defaultRepo(project: URL) -> String? {
        guard let output = try? runner.run(
            executable: "/usr/bin/env", args: ["git", "-C", project.path, "remote", "get-url", "origin"],
            environment: nil
        ) else { return nil }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let escapedHosts = githubHosts.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        guard let regex = try? NSRegularExpression(pattern: "(?:\(escapedHosts))[:/]([\\w.-]+/[\\w.-]+?)(?:\\.git)?$")
        else { return nil }
        guard let match = regex.matches(in: trimmed).first, let repo = regex.group(match, 1, in: trimmed) else {
            return nil
        }
        return repo
    }
}

private func isoNow(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}
