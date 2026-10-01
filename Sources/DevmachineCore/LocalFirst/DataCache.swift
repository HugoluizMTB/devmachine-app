import Foundation

/// Every kind of data the app reads from machines and keeps between reads.
/// The kind sets how long a value counts as fresh and how many are kept.
public enum CacheKind: String, Codable, Sendable, CaseIterable {
    case workspaces
    case sitesContext
    case sites
    case dnsProviders
    case dnsRecords
    case ports
    case sessions
    case context
}

public struct CachePolicy: Sendable {
    public var ttls: [CacheKind: TimeInterval]
    public var limits: [CacheKind: Int]

    public init(ttls: [CacheKind: TimeInterval], limits: [CacheKind: Int]) {
        self.ttls = ttls
        self.limits = limits
    }

    /// Ports move when a dev server starts, sites when someone publishes,
    /// DNS almost never: each is asked again only once its own age runs out.
    public static let standard = CachePolicy(
        ttls: [
            .ports: 45, .sites: 60, .dnsProviders: 300, .dnsRecords: 300,
            .workspaces: 300, .sitesContext: 300, .sessions: 60, .context: 10,
        ],
        limits: [.context: 24, .sessions: 64, .dnsRecords: 32, .dnsProviders: 16, .sites: 16])

    public func ttl(for kind: CacheKind) -> TimeInterval { ttls[kind] ?? 60 }
    public func maxEntries(for kind: CacheKind) -> Int { limits[kind] ?? 64 }
}

/// Names one cached value and the type it holds. `scope` says whose value it
/// is: a machine, a workspace, `machine|provider|zone`.
public struct CacheKey<Value: Codable & Sendable & Equatable>: Hashable, Sendable {
    public let kind: CacheKind
    public let scope: String

    public init(_ kind: CacheKind, _ scope: String) {
        self.kind = kind
        self.scope = scope
    }

    public var id: String { "\(kind.rawValue):\(scope)" }
    public var entry: CacheEntryID { CacheEntryID(kind: kind, scope: scope) }
}

/// A key without its value type, for observers and invalidation.
public struct CacheEntryID: Hashable, Sendable {
    public let kind: CacheKind
    public let scope: String
    public var id: String { "\(kind.rawValue):\(scope)" }
}

public struct Cached<Value> {
    public let value: Value
    public let fetchedAt: Date
    public let isStale: Bool
}

extension Cached: Equatable where Value: Equatable {}
extension Cached: Sendable where Value: Sendable {}

/// What a background refresh brought back. `changed` is false when the
/// answer equals what was already there: only its age moved.
public struct CacheUpdate<Value> {
    public let cached: Cached<Value>
    public let changed: Bool
}

/// One value as it sits on disk: its JSON text, so a type that changed shape
/// between versions fails on its own read and costs only that entry.
public struct CacheFileEntry: Codable, Equatable, Sendable {
    public let kind: String
    public let scope: String
    public let fetchedAt: Date
    public let payload: String
}

/// Every cached machine value in one small JSON file. A file that cannot be
/// read is no cache: it only ever costs one read per key to rebuild.
public struct CacheFile: Sendable {
    private struct File: Codable {
        let version: Int
        let entries: [CacheFileEntry]
    }

    private static let version = 1

    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static var defaultFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return support.appendingPathComponent("Devmachine/machine-cache.json")
    }

    public func load() -> [CacheFileEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(File.self, from: data), file.version == Self.version else {
            return []
        }
        return file.entries
    }

    public func save(_ entries: [CacheFileEntry]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(File(version: Self.version, entries: entries))
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}

/// The app-wide stale-while-revalidate cache for machine data. A reader gets
/// what is cached at once, and a refresh runs in the background only when
/// the value is older than its kind's TTL, was invalidated, or the person
/// asked. One fetch per key runs at a time; every other caller joins it.
@MainActor
public final class DataCache {
    private struct Slot {
        let kind: CacheKind
        let scope: String
        var fetchedAt: Date
        var value: (any Sendable)?
        var payload: String?
        var invalidated = false
        var error: String?
    }

    public let policy: CachePolicy
    private let file: CacheFile?
    private let now: @MainActor () -> Date
    private var slots: [String: Slot] = [:]
    private var inFlight: [String: Task<any Sendable, Error>] = [:]
    private var background: [UUID: Task<Void, Never>] = [:]
    private var observers: [@MainActor (CacheEntryID) -> Void] = []
    private let writeQueue = DispatchQueue(label: "app.devmachine.datacache.write")

    public init(file: CacheFile? = nil, policy: CachePolicy = .standard, now: @escaping @MainActor () -> Date = { Date() }) {
        self.file = file
        self.policy = policy
        self.now = now
        for entry in file?.load() ?? [] {
            guard let kind = CacheKind(rawValue: entry.kind) else { continue }
            let key = "\(kind.rawValue):\(entry.scope)"
            slots[key] = Slot(kind: kind, scope: entry.scope, fetchedAt: entry.fetchedAt, payload: entry.payload)
        }
    }

    // MARK: Reading

    public func cached<V>(_ key: CacheKey<V>) -> Cached<V>? {
        guard let slot = slots[key.id] else { return nil }
        if let value = slot.value as? V {
            return Cached(value: value, fetchedAt: slot.fetchedAt, isStale: !isFresh(slot))
        }
        guard let payload = slot.payload,
              let value = try? Self.decoder.decode(V.self, from: Data(payload.utf8)) else {
            return nil
        }
        slots[key.id]?.value = value
        return Cached(value: value, fetchedAt: slot.fetchedAt, isStale: !isFresh(slot))
    }

    public func isFresh<V>(_ key: CacheKey<V>) -> Bool {
        guard let slot = slots[key.id], cached(key) != nil else { return false }
        return isFresh(slot)
    }

    public func isRefreshing<V>(_ key: CacheKey<V>) -> Bool { inFlight[key.id] != nil }

    public func lastError<V>(_ key: CacheKey<V>) -> String? { slots[key.id]?.error }

    public func count(of kind: CacheKind) -> Int { slots.values.filter { $0.kind == kind }.count }

    private func isFresh(_ slot: Slot) -> Bool {
        !slot.invalidated && now().timeIntervalSince(slot.fetchedAt) < policy.ttl(for: slot.kind)
    }

    // MARK: Fetching

    /// The cached value when it is fresh, else the answer of one fetch that
    /// every concurrent caller of this key shares. `force` skips the TTL but
    /// still joins a fetch already running.
    public func value<V>(
        _ key: CacheKey<V>, force: Bool = false, fetch: @escaping @Sendable () async throws -> V
    ) async throws -> V {
        if !force, isFresh(key), let cached = cached(key) { return cached.value }
        return try await refresh(key, fetch: fetch).value
    }

    /// Hands back what is cached now, and starts a background fetch when it
    /// is stale, missing, invalidated or `force`d. `onUpdate` hears the
    /// answer, with `changed` false when it equals what was there.
    @discardableResult
    public func revalidate<V>(
        _ key: CacheKey<V>, force: Bool = false,
        fetch: @escaping @Sendable () async throws -> V,
        onUpdate: @escaping @MainActor (CacheUpdate<V>) -> Void,
        onError: (@MainActor (Error) -> Void)? = nil
    ) -> Cached<V>? {
        let current = cached(key)
        guard force || !isFresh(key) else { return current }
        let before = current?.value
        let running = startFetch(key, fetch: fetch)
        let id = UUID()
        background[id] = Task {
            defer { self.background[id] = nil }
            do {
                let fresh = try await self.await(running, key)
                onUpdate(CacheUpdate(cached: fresh, changed: fresh.value != before))
            } catch {
                onError?(error)
            }
        }
        return current
    }

    private func refresh<V>(
        _ key: CacheKey<V>, fetch: @escaping @Sendable () async throws -> V
    ) async throws -> Cached<V> {
        try await self.await(startFetch(key, fetch: fetch), key)
    }

    /// Starts the key's fetch now, so `isRefreshing` is true from this call
    /// on, or hands back the one already running.
    private func startFetch<V>(
        _ key: CacheKey<V>, fetch: @escaping @Sendable () async throws -> V
    ) -> Task<any Sendable, Error> {
        let id = key.id
        if let running = inFlight[id] { return running }
        let task = Task<any Sendable, Error> {
            defer { self.inFlight[id] = nil }
            do {
                let value = try await fetch()
                self.put(key, value)
                return value
            } catch {
                self.slots[id]?.error = Self.describe(error)
                throw error
            }
        }
        inFlight[id] = task
        return task
    }

    private func await<V>(_ task: Task<any Sendable, Error>, _ key: CacheKey<V>) async throws -> Cached<V> {
        guard let value = try await task.value as? V else {
            throw CacheError.typeMismatch(key.id)
        }
        return Cached(value: value, fetchedAt: slots[key.id]?.fetchedAt ?? now(), isStale: false)
    }

    /// Waits until every background fetch has answered. Tests use it; the
    /// app never waits on the cache.
    public func settle() async {
        while true {
            if let task = background.values.first {
                await task.value
            } else if let running = inFlight.values.first {
                _ = try? await running.value
                await Task.yield()
            } else {
                return
            }
        }
    }

    // MARK: Writing

    public func put<V>(_ key: CacheKey<V>, _ value: V) {
        let previous = slots[key.id].flatMap { $0.value as? V } ?? cachedValueIgnoringShape(key)
        var slot = Slot(kind: key.kind, scope: key.scope, fetchedAt: now(), value: value)
        if file != nil, let data = try? Self.encoder.encode(value) {
            slot.payload = String(decoding: data, as: UTF8.self)
        }
        slots[key.id] = slot
        prune(key.kind)
        if previous != value {
            for observer in observers { observer(key.entry) }
        }
        persist()
    }

    private func cachedValueIgnoringShape<V: Decodable>(_ key: CacheKey<V>) -> V? {
        guard let payload = slots[key.id]?.payload else { return nil }
        return try? Self.decoder.decode(V.self, from: Data(payload.utf8))
    }

    public func invalidate(_ kind: CacheKind, scope: String? = nil) {
        for (id, slot) in slots where slot.kind == kind && (scope == nil || slot.scope == scope) {
            slots[id]?.invalidated = true
        }
    }

    public func invalidate(_ kind: CacheKind, scopePrefix: String) {
        for (id, slot) in slots where slot.kind == kind && slot.scope.hasPrefix(scopePrefix) {
            slots[id]?.invalidated = true
        }
    }

    public func observe(_ handler: @escaping @MainActor (CacheEntryID) -> Void) {
        observers.append(handler)
    }

    public func waitForPendingWrites() {
        writeQueue.sync {}
    }

    private func prune(_ kind: CacheKind) {
        let limit = policy.maxEntries(for: kind)
        let ofKind = slots.filter { $0.value.kind == kind }
        guard ofKind.count > limit else { return }
        let oldest = ofKind.sorted { $0.value.fetchedAt < $1.value.fetchedAt }.prefix(ofKind.count - limit)
        for (id, _) in oldest { slots[id] = nil }
    }

    private func persist() {
        guard let file else { return }
        let entries = slots.values.compactMap { slot -> CacheFileEntry? in
            guard let payload = slot.payload else { return nil }
            return CacheFileEntry(kind: slot.kind.rawValue, scope: slot.scope, fetchedAt: slot.fetchedAt, payload: payload)
        }
        .sorted { ($0.kind, $0.scope) < ($1.kind, $1.scope) }
        writeQueue.async { try? file.save(entries) }
    }

    private static func describe(_ error: Error) -> String {
        let text = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()
}

public enum CacheError: Error, Equatable {
    case typeMismatch(String)
}
