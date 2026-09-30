import AppKit
import DevmachineCore

struct UploadJob: Sendable {
    let originalName: String
    let name: UploadName
    let size: Int64
    let load: @Sendable () throws -> Data
}

/// Files dropped, pasted or picked for a pane: each one goes to the machine
/// that runs the session, then every path is typed at once, quoted, without
/// Enter. A pane shows its own drop highlight, progress, question or error.
@MainActor
final class PaneUploadStore: ObservableObject {
    typealias Upload = @Sendable (
        UploadJob, TerminalKind, UploadStoragePolicy, @escaping @Sendable (Int) -> Void
    ) throws -> String

    enum Phase: Equatable {
        case confirming(names: [String], totalBytes: Int64)
        case uploading(label: String, done: Int64, total: Int64)
        case failed(DMErrorState)
    }

    static let shared = PaneUploadStore(
        upload: { job, kind, policy, progress in
            let service = FileUploadService(runner: ProcessRunner(), storagePolicy: policy)
            return try service.store(
                try job.load(), name: job.name, on: kind, onBytesWritten: progress)
        },
        policy: { kind in AppModel.shared?.uploadStoragePolicy(for: kind) ?? .appManaged },
        type: { text, kind in TerminalRegistry.shared.type(text, into: kind) },
        now: Date.init)

    @Published var dropTarget: TerminalKind?
    @Published private(set) var phases: [TerminalKind: Phase] = [:]

    private let upload: Upload
    private let policy: (TerminalKind) -> UploadStoragePolicy
    private let type: (String, TerminalKind) -> Void
    private let now: () -> Date
    private var awaitingConfirmation: [TerminalKind: [UploadJob]] = [:]
    private var runs: [TerminalKind: UUID] = [:]

    init(
        upload: @escaping Upload, policy: @escaping (TerminalKind) -> UploadStoragePolicy,
        type: @escaping (String, TerminalKind) -> Void, now: @escaping () -> Date
    ) {
        self.upload = upload
        self.policy = policy
        self.type = type
        self.now = now
    }

    func isBusy(_ kind: TerminalKind) -> Bool {
        if case .uploading? = phases[kind] { return true }
        return false
    }

    func receive(urls: [URL], on kind: TerminalKind) {
        receive(urls.map(Self.entry), on: kind)
    }

    func receive(_ entries: [DroppedEntry], on kind: TerminalKind) {
        guard !isBusy(kind), !entries.isEmpty else { return }
        let items: [UploadItem]
        do {
            items = try FileUpload.plan(entries, date: now())
        } catch let refusal as UploadRefusal {
            phases[kind] = .failed(DMErrorState(
                systemImage: "folder.badge.questionmark", title: refusal.title, cause: nil,
                details: refusal.details))
            return
        } catch {
            phases[kind] = .failed(DMErrorState(title: "Couldn\u{2019}t upload", message: "\(error)"))
            return
        }
        let jobs = items.map { item in
            UploadJob(originalName: item.originalName, name: item.name, size: item.size) {
                try Data(contentsOf: item.source, options: .alwaysMapped)
            }
        }
        let total = items.reduce(Int64(0)) { $0 + $1.size }
        if FileUpload.needsConfirmation(totalBytes: total) {
            awaitingConfirmation[kind] = jobs
            phases[kind] = .confirming(names: items.map(\.originalName), totalBytes: total)
        } else {
            start(jobs, on: kind)
        }
    }

    func receive(_ pasted: FileUploadService.PastedImage, on kind: TerminalKind) {
        switch pasted {
        case let .file(url):
            receive(urls: [url], on: kind)
        case let .bitmap(data):
            guard !isBusy(kind) else { return }
            start([UploadJob(
                originalName: FileUpload.pastedImageName,
                name: UploadName.make(original: FileUpload.pastedImageName, date: now()),
                size: Int64(data.count), load: { data })], on: kind)
        }
    }

    func confirm(_ kind: TerminalKind) {
        guard let jobs = awaitingConfirmation.removeValue(forKey: kind) else { return }
        start(jobs, on: kind)
    }

    func dismiss(_ kind: TerminalKind) {
        awaitingConfirmation[kind] = nil
        guard !isBusy(kind) else { return }
        phases[kind] = nil
    }

    private func start(_ jobs: [UploadJob], on kind: TerminalKind) {
        let run = UUID()
        runs[kind] = run
        let total = jobs.reduce(Int64(0)) { $0 + $1.size }
        let label = TerminalRegistry.sendingLabel(for: kind, names: jobs.map(\.originalName))
        phases[kind] = .uploading(label: label, done: 0, total: total)
        let card = AppModel.shared?.beginTransfer(label: label, total: Int(clamping: total))
        let upload = upload
        let policy = policy(kind)
        Task.detached {
            var paths: [String] = []
            var sent: Int64 = 0
            var failure: (name: String, error: Error)?
            for job in jobs {
                let before = sent
                do {
                    paths.append(try upload(job, kind, policy) { written in
                        Task { @MainActor in
                            self.advance(kind, run: run, done: before + Int64(written), card: card)
                        }
                    })
                } catch {
                    failure = (job.originalName, error)
                    break
                }
                sent += job.size
            }
            await MainActor.run { [paths, failure] in
                self.finish(kind, run: run, paths: paths, failure: failure, card: card)
            }
        }
    }

    private func advance(_ kind: TerminalKind, run: UUID, done: Int64, card: UUID?) {
        guard runs[kind] == run, case let .uploading(label, _, total)? = phases[kind] else { return }
        phases[kind] = .uploading(label: label, done: min(done, total), total: total)
        if let card { AppModel.shared?.advanceTransfer(card, done: Int(clamping: done)) }
    }

    private func finish(
        _ kind: TerminalKind, run: UUID, paths: [String], failure: (name: String, error: Error)?,
        card: UUID?
    ) {
        guard runs[kind] == run else { return }
        runs[kind] = nil
        if let card { AppModel.shared?.endTransfer(card) }
        if let failure {
            phases[kind] = .failed(DMErrorState(
                title: "Couldn\u{2019}t upload \(failure.name)", message: Self.details(of: failure.error)))
            return
        }
        phases[kind] = nil
        type(FileUpload.typedText(for: paths), kind)
    }

    private static func details(of error: Error) -> String {
        switch error {
        case let FileUploadService.Failure.transferFailed(details): return details
        default: return (error as NSError).localizedDescription
        }
    }

    static func entry(for url: URL) -> DroppedEntry {
        let resolved = url.resolvingSymlinksInPath()
        let values = try? resolved.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        return DroppedEntry(
            url: url, isDirectory: values?.isDirectory ?? false,
            size: Int64(values?.fileSize ?? 0))
    }
}
