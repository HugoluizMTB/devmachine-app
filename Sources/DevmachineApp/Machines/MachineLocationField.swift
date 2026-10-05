import SwiftUI
import DevmachineCore

/// Where a machine is: free text, with the common answers one click away.
/// The wizard and a machine's "Edit location" both use it.
struct MachineLocationField: View {
    @Environment(\.dmMetrics) private var m
    @Binding var location: String
    /// Locations other machines already use, offered before the fixed ones.
    var known: [String] = []
    var defaultLocation = MachineLocation.external

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.sm) {
            TextField(defaultLocation, text: $location).dmField()
            FlowLayout(spacing: DMSpace.xs, rowSpacing: DMSpace.xs) {
                ForEach(choices, id: \.value) { choice in
                    Button { location = choice.value } label: { Text(verbatim: choice.title) }
                        .buttonStyle(.dmChip(selected: MachineLocation.normalized(location) == choice.value))
                        .font(.dm(11))
                }
            }
        }
    }

    private var choices: [MachineLocation.Suggestion] {
        var seen = Set<String>()
        let all = [MachineLocation.Suggestion(title: defaultLocation.capitalized, value: defaultLocation)]
            + known.map { MachineLocation.Suggestion(title: $0.capitalized, value: $0) }
            + MachineLocation.suggestions
        return all.filter { seen.insert($0.value).inserted }
    }
}
