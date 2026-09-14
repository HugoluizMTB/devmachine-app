import SwiftUI

struct CommandPaletteView: View {
    @EnvironmentObject var model: AppModel
    @State private var query = ""
    @State private var index = 0
    @FocusState private var focused: Bool

    private var results: [PaletteItem] {
        let all = model.paletteItems()
        guard !query.isEmpty else { return all }
        return all
            .compactMap { item -> (PaletteItem, Int)? in
                guard let s = Self.fuzzyScore(query, "\(item.subtitle) \(item.title)") else { return nil }
                return (item, s)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Buscar sessão…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($focused)
                    .onSubmit(openSelected)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { i, item in
                            row(i: i, item: item)
                                .id(item.id)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 360)
                .onChange(of: index) { _, new in
                    if new < results.count { withAnimation { proxy.scrollTo(results[new].id) } }
                }
            }
        }
        .frame(width: 560)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.12), lineWidth: 0.5))
        .shadow(radius: 30, y: 12)
        .onAppear { focused = true; index = 0 }
        .onChange(of: query) { _, _ in index = 0 }
        .onKeyPress(.downArrow) { index = min(index + 1, max(results.count - 1, 0)); return .handled }
        .onKeyPress(.upArrow) { index = max(index - 1, 0); return .handled }
        .onKeyPress(.return) { openSelected(); return .handled }
        .onKeyPress(.escape) { model.showCommandPalette = false; return .handled }
    }

    private func row(i: Int, item: PaletteItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.claude ? "circle.fill" : "circle")
                .font(.system(size: 7))
                .foregroundStyle(item.claude ? Color.orange : Color.dmMuted)
            Text(item.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
            Text(item.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(i == index ? Color.white.opacity(0.10) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { model.openPalette(item) }
    }

    private func openSelected() {
        guard index < results.count else { return }
        model.openPalette(results[index])
    }

    static func fuzzyScore(_ q: String, _ text: String) -> Int? {
        let t = text.lowercased()
        let query = q.lowercased()
        if query.isEmpty { return 0 }
        if let r = t.range(of: query) {
            return 1000 - t.distance(from: t.startIndex, to: r.lowerBound)
        }
        var ti = t.startIndex
        var score = 0
        for ch in query {
            guard let f = t[ti...].firstIndex(of: ch) else { return nil }
            ti = t.index(after: f)
            score += 1
        }
        return score
    }
}
