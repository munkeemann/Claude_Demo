import Foundation

/// How close an item is to its expiry date, measured in calendar days.
public struct ExpiryStatus: Sendable, Equatable {
    public enum Urgency: Int, Sendable, Comparable {
        case expired
        case today
        case soon
        case later

        public static func < (lhs: Urgency, rhs: Urgency) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Calendar days from today to the expiry date. Negative once expired.
    public let daysRemaining: Int
    public let urgency: Urgency

    public init(expiry: Date, now: Date, calendar: Calendar = .current, soonThresholdDays: Int = 3) {
        let today = calendar.startOfDay(for: now)
        let expiryDay = calendar.startOfDay(for: expiry)
        let days = calendar.dateComponents([.day], from: today, to: expiryDay).day ?? 0
        daysRemaining = days
        switch days {
        case ..<0: urgency = .expired
        case 0: urgency = .today
        case 1...soonThresholdDays: urgency = .soon
        default: urgency = .later
        }
    }

    /// Compact label for list rows: "Expired", "Today", "Tomorrow", "3 days", "2 wks".
    public var shortLabel: String {
        switch daysRemaining {
        case ..<(-1): "Expired \(-daysRemaining)d ago"
        case -1: "Expired yesterday"
        case 0: "Expires today"
        case 1: "Tomorrow"
        case 2...13: "\(daysRemaining) days"
        case 14...59: "\(daysRemaining / 7) wks"
        default: "\(daysRemaining / 30) mo"
        }
    }
}
