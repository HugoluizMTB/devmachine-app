import Foundation
import DevmachineCore

/// A read the person asked for on one machine: still running, its answer,
/// or why it failed.
enum MachineRead<Value: Equatable>: Equatable {
    case loading
    case loaded(Value)
    case failed(String)

    var value: Value? {
        if case let .loaded(value) = self { return value }
        return nil
    }
}

/// The CLI calls behind a machine's inline panels. Each one is read only
/// when its panel opens: `doctor` and `credentials list` log in to the
/// machine, and a list of machines must not cost an ssh each.
struct MachineDetailsService: Sendable {
    var doctor: @Sendable (_ machine: String, _ isSelf: Bool) async throws -> DevmachineCLI.DoctorOutcome
    var addresses: @Sendable (_ machine: String) async throws -> MachineAddresses
    var credentials: @Sendable (_ machine: String) async throws -> MachineCredentials
    var editLocation: @Sendable (_ machine: String, _ location: String) async throws -> Void
    var passwordLogin: @Sendable (_ machine: String) async throws -> MachinePasswordLogin
    var changePasswordLogin: @Sendable (_ machine: String, _ change: PasswordLoginChange) async throws -> Void

    static let live = MachineDetailsService(
        doctor: { machine, isSelf in
            try await Task.detached {
                let cli = try DevmachineCLI.resolve()
                return isSelf ? try cli.machineDoctor() : try cli.doctor(machine: machine)
            }.value
        },
        addresses: { machine in
            try await Task.detached { try DevmachineCLI.resolve().addresses(machine: machine) }.value
        },
        credentials: { machine in
            try await Task.detached { try DevmachineCLI.resolve().credentials(machine: machine) }.value
        },
        editLocation: { machine, location in
            try await Task.detached { try DevmachineCLI.resolve().editLocation(machine: machine, location: location) }
                .value
        },
        passwordLogin: { machine in
            try await Task.detached { try DevmachineCLI.resolve().passwordLogin(machine: machine) }.value
        },
        changePasswordLogin: { machine, change in
            try await Task.detached { try DevmachineCLI.resolve().changePasswordLogin(machine: machine, to: change) }
                .value
        })
}

/// Settings → Machines' per-machine panels (Check, Addresses, Credentials)
/// and the location edit. Long runs (sync, start, stop, delete) are machine
/// jobs in the corner instead.
@MainActor
final class MachineDetailsStore: ObservableObject {
    static let shared = MachineDetailsStore(service: DemoMode.isActive ? DemoData.machineDetailsService : .live)

    enum Panel: String, CaseIterable, Identifiable {
        case check, addresses, credentials, passwordLogin

        var id: String { rawValue }

        var title: String {
            switch self {
            case .check: return "Check"
            case .addresses: return "Addresses"
            case .credentials: return "Credentials"
            case .passwordLogin: return "SSH password login"
            }
        }
    }

    @Published private(set) var open: [String: Panel] = [:]
    @Published private(set) var checks: [String: MachineRead<DevmachineCLI.DoctorOutcome>] = [:]
    @Published private(set) var addresses: [String: MachineRead<MachineAddresses>] = [:]
    @Published private(set) var credentials: [String: MachineRead<MachineCredentials>] = [:]
    @Published private(set) var passwordLogins: [String: MachineRead<MachinePasswordLogin>] = [:]
    @Published private(set) var changingPasswordLogin: String?
    @Published var passwordLoginError: [String: String] = [:]
    @Published private(set) var savingLocation: String?
    @Published var locationError: [String: String] = [:]

    private let service: MachineDetailsService
    private let reload: @MainActor () -> Void

    init(service: MachineDetailsService, reload: @escaping @MainActor () -> Void = { MachinesStore.shared.requestLoad() }) {
        self.service = service
        self.reload = reload
    }

    /// Opens a panel, reading it again each time: a machine changes under
    /// the app. The same panel again closes it.
    func toggle(_ panel: Panel, machine: String, isSelf: Bool) async {
        if open[machine] == panel {
            open[machine] = nil
            return
        }
        open[machine] = panel
        await read(panel, machine: machine, isSelf: isSelf)
    }

    func read(_ panel: Panel, machine: String, isSelf: Bool) async {
        switch panel {
        case .check:
            checks[machine] = .loading
            checks[machine] = await result { try await self.service.doctor(machine, isSelf) }
        case .addresses:
            addresses[machine] = .loading
            addresses[machine] = await result { try await self.service.addresses(machine) }
        case .credentials:
            credentials[machine] = .loading
            credentials[machine] = await result { try await self.service.credentials(machine) }
        case .passwordLogin:
            passwordLogins[machine] = .loading
            passwordLogins[machine] = await result { try await self.service.passwordLogin(machine) }
        }
    }

    /// Changes who logs in over SSH with a password, then asks sshd again:
    /// the answer shown is the machine's, never the one that was asked for.
    func changePasswordLogin(_ change: PasswordLoginChange, machine: String) async {
        guard changingPasswordLogin == nil else { return }
        guard !DemoMode.isActive else {
            passwordLoginError[machine] = "Demo mode never changes a machine."
            return
        }
        changingPasswordLogin = machine
        defer { changingPasswordLogin = nil }
        do {
            try await service.changePasswordLogin(machine, change)
            passwordLoginError[machine] = nil
            reload()
        } catch {
            passwordLoginError[machine] = PackageGateMessage.friendly(for: error)
        }
        await read(.passwordLogin, machine: machine, isSelf: false)
    }

    /// `machines edit --location` writes this Mac's configuration only.
    @discardableResult
    func saveLocation(_ location: String, machine: String) async -> Bool {
        guard savingLocation == nil else { return false }
        if let problem = MachineLocation.problem(location) {
            locationError[machine] = problem
            return false
        }
        guard !DemoMode.isActive else {
            locationError[machine] = "Demo mode never changes a machine."
            return false
        }
        savingLocation = machine
        defer { savingLocation = nil }
        do {
            try await service.editLocation(machine, location)
            locationError[machine] = nil
            reload()
            return true
        } catch {
            locationError[machine] = error.localizedDescription
            return false
        }
    }

    /// Demo mode only: a panel already open with its answer.
    func seedDemo(open panel: Panel?, machine: String, isSelf: Bool) async {
        open = [:]
        guard let panel else { return }
        open[machine] = panel
        await read(panel, machine: machine, isSelf: isSelf)
    }

    private func result<Value>(_ read: () async throws -> Value) async -> MachineRead<Value> {
        do {
            return .loaded(try await read())
        } catch {
            return .failed(PackageGateMessage.friendly(for: error))
        }
    }
}
