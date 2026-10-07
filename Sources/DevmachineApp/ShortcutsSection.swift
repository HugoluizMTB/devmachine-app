import SwiftUI

struct ShortcutsSection: View {
    let target: CommandTarget
    @EnvironmentObject var skillsStore: SkillsStore
    @State private var showEditor = false

    var body: some View {
        DMSection(
            contentSpacing: 9,
            padding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14),
            label: {
                Text("SHORTCUTS")
                    .font(.dm(10, weight: .bold))
                    .kerning(0.5)
                    .foregroundStyle(Color.dmMuted)
            },
            trailing: {
                DMIconButton(systemImage: "gearshape", size: 11, hitSize: DMHitSize.compact) {
                    showEditor = true
                }
                .help("Edit shortcuts")
                .popover(isPresented: $showEditor) {
                    SkillsEditorView()
                        .environmentObject(skillsStore)
                }
                StackHeaderControls()
            }
        ) {
            FlowLayout(spacing: 4, rowSpacing: 4) {
                ForEach(skillsStore.skills) { skill in
                    SkillButton(skill: skill) {
                        skillsStore.send(skill, to: target)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SkillButton: View {
    @Environment(\.dmMetrics) private var m
    let skill: SkillCommand
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: m.space.xs) {
                Image(systemName: skill.systemImage)
                    .font(.dm(11))
                Text(skill.label)
                    .font(.dm(11))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.dmChip)
    }
}

private struct SkillsEditorView: View {
    @Environment(\.dmMetrics) private var m
    @EnvironmentObject var skillsStore: SkillsStore
    @State private var newLabel = ""
    @State private var newCommand = ""
    @State private var newSystemImage = "star"

    private var canAdd: Bool {
        !newLabel.trimmingCharacters(in: .whitespaces).isEmpty
            && !newCommand.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: m.pt(10)) {
            Text("Shortcuts").font(.headline)

            VStack(spacing: m.space.xs) {
                ForEach(skillsStore.skills) { skill in
                    HStack(spacing: m.space.md) {
                        Image(systemName: skill.systemImage)
                            .foregroundStyle(Color.dmMuted)
                            .frame(width: m.pt(16))
                        Text(skill.label)
                            .font(.dm(12))
                        Text(skill.command)
                            .font(.dm(11))
                            .foregroundStyle(Color.dmMuted)
                        Spacer()
                        DMIconButton(systemImage: "minus.circle") {
                            skillsStore.remove(skill)
                        }
                    }
                }
            }

            DMHairline()

            VStack(alignment: .leading, spacing: m.space.sm) {
                TextField("Label", text: $newLabel)
                TextField("Command", text: $newCommand)
                TextField("SF Symbol", text: $newSystemImage)
                DMButton("Add", systemImage: "plus", size: .small) {
                    skillsStore.add(
                        label: newLabel.trimmingCharacters(in: .whitespaces),
                        command: newCommand.trimmingCharacters(in: .whitespaces),
                        systemImage: newSystemImage.trimmingCharacters(in: .whitespaces)
                    )
                    newLabel = ""
                    newCommand = ""
                    newSystemImage = "star"
                }
                .disabled(!canAdd)
            }
        }
        .padding(m.space.xl)
        .frame(width: m.pt(280))
    }
}
