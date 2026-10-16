import Foundation

public struct ChatGroup: Equatable, Identifiable, Sendable {
    public let title: String
    public let chats: [ChatRecord]
    public var id: String { title }
}

public enum ChatGrouping {
    public static let today = "Today"
    public static let yesterday = "Yesterday"
    public static let previousWeek = "Previous 7 days"
    public static let older = "Older"

    /// Newest first, under Today / Yesterday / Previous 7 days / Older by
    /// the last message; empty groups are left out.
    public static func groups(_ chats: [ChatRecord], now: Date, calendar: Calendar = .current) -> [ChatGroup] {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        let startOfWeek = calendar.date(byAdding: .day, value: -7, to: startOfToday) ?? startOfToday
        var buckets: [String: [ChatRecord]] = [:]
        for chat in sorted(chats) {
            let title: String
            if chat.updatedAt >= startOfToday {
                title = today
            } else if chat.updatedAt >= startOfYesterday {
                title = yesterday
            } else if chat.updatedAt >= startOfWeek {
                title = previousWeek
            } else {
                title = older
            }
            buckets[title, default: []].append(chat)
        }
        return [today, yesterday, previousWeek, older].compactMap { title in
            buckets[title].map { ChatGroup(title: title, chats: $0) }
        }
    }

    public static func sorted(_ chats: [ChatRecord]) -> [ChatRecord] {
        chats.sorted { $0.updatedAt != $1.updatedAt ? $0.updatedAt > $1.updatedAt : $0.id < $1.id }
    }

    public static func filter(_ chats: [ChatRecord], query: String) -> [ChatRecord] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return chats }
        return chats.filter { $0.title.localizedCaseInsensitiveContains(needle) }
    }

    /// "now", "5m", "2h", "3d", "2w": as short as the rows have room for.
    public static func age(of date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(seconds / 60)m"
        case ..<86_400: return "\(seconds / 3600)h"
        case ..<(86_400 * 14): return "\(seconds / 86_400)d"
        default: return "\(seconds / (86_400 * 7))w"
        }
    }
}

/// ↑ and ↓ in the chat list: the chat next to the selected one, in the
/// order the list shows. Nothing selected: ↓ picks the first, ↑ the last.
public enum ChatListNavigation {
    public static func neighbor(of selected: String?, in ids: [String], step: Int) -> String? {
        guard !ids.isEmpty else { return nil }
        guard let selected, let index = ids.firstIndex(of: selected) else {
            return step > 0 ? ids.first : ids.last
        }
        return ids[min(max(index + step, 0), ids.count - 1)]
    }
}
