import DevmachineCore

/// What the Published apps tab shows: a status view wins over everything,
/// then the DNS provider chooser or its bar, else the plain table.
enum PublishLayout: Equatable {
    case status, chooser, barAndTable, table

    static func pick(state: DNSSetupState, hasSites: Bool, showsStatus: Bool, wantsChooser: Bool) -> PublishLayout {
        if showsStatus { return .status }
        if state == .unknown || state == .ready { return .table }
        if !hasSites || wantsChooser { return .chooser }
        return .barAndTable
    }
}
