import Foundation

public struct NotificationSettings: Sendable, Equatable {
    public var isEnabled: Bool
    /// Days before expiry to remind.
    public var expiryLeadDays: Int
    /// Days before a predicted run-out to remind.
    public var runOutLeadDays: Int
    /// Hour of day (0–23) reminders are delivered.
    public var hour: Int
    /// Only forecasts at or above this confidence trigger reminders.
    public var minimumRunOutConfidence: ForecastConfidence

    public init(
        isEnabled: Bool = true,
        expiryLeadDays: Int = 2,
        runOutLeadDays: Int = 3,
        hour: Int = 9,
        minimumRunOutConfidence: ForecastConfidence = .medium
    ) {
        self.isEnabled = isEnabled
        self.expiryLeadDays = expiryLeadDays
        self.runOutLeadDays = runOutLeadDays
        self.hour = hour
        self.minimumRunOutConfidence = minimumRunOutConfidence
    }
}

public struct UpcomingEvent: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case expires
        case runsOut
    }

    public var name: String
    public var date: Date
    public var kind: Kind
    public var confidence: ForecastConfidence

    public init(name: String, date: Date, kind: Kind, confidence: ForecastConfidence = .high) {
        self.name = name
        self.date = date
        self.kind = kind
        self.confidence = confidence
    }
}

public struct PlannedNotification: Sendable, Equatable {
    public var id: String
    public var fireDate: Date
    public var title: String
    public var body: String
}

/// Turns upcoming expiries and run-outs into local notifications.
///
/// iOS keeps only the 64 soonest pending local notifications per app, so
/// reminders that fall on the same day are grouped into one notification
/// ("Spinach, Milk and 2 more expire soon"), and at most `limit` days are
/// scheduled. Reminders whose time has already passed are skipped; the
/// in-app "Soon" list covers those.
public enum NotificationPlanner {
    public static let identifierPrefix = "larder.reminder."
    public static let limit = 60

    public static func plan(
        events: [UpcomingEvent],
        settings: NotificationSettings,
        now: Date,
        calendar: Calendar = .current
    ) -> [PlannedNotification] {
        guard settings.isEnabled else { return [] }

        var byDay: [Date: [UpcomingEvent]] = [:]
        for event in events {
            if event.kind == .runsOut && event.confidence < settings.minimumRunOutConfidence { continue }
            let lead = event.kind == .expires ? settings.expiryLeadDays : settings.runOutLeadDays
            let eventDay = calendar.startOfDay(for: event.date)
            guard let reminderDay = calendar.date(byAdding: .day, value: -lead, to: eventDay),
                  let fireDate = calendar.date(bySettingHour: settings.hour, minute: 0, second: 0, of: reminderDay),
                  fireDate > now
            else { continue }
            byDay[fireDate, default: []].append(event)
        }

        return byDay.keys.sorted().prefix(limit).map { fireDate in
            let group = byDay[fireDate]!.sorted { ($0.date, $0.name) < ($1.date, $1.name) }
            let components = calendar.dateComponents([.year, .month, .day], from: fireDate)
            let id = identifierPrefix + String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
            return PlannedNotification(
                id: id,
                fireDate: fireDate,
                title: title(for: group),
                body: body(for: group, on: fireDate, calendar: calendar)
            )
        }
    }

    static func title(for group: [UpcomingEvent]) -> String {
        let expiring = group.filter { $0.kind == .expires }.count
        let runningOut = group.count - expiring
        switch (expiring, runningOut) {
        case (0, _): return runningOut == 1 ? "Running low" : "Running low on \(runningOut) items"
        case (_, 0): return expiring == 1 ? "Use it soon" : "\(expiring) items expiring soon"
        default: return "Kitchen check-in"
        }
    }

    static func body(for group: [UpcomingEvent], on fireDate: Date, calendar: Calendar) -> String {
        let expiring = group.filter { $0.kind == .expires }
        let runningOut = group.filter { $0.kind == .runsOut }
        var sentences: [String] = []
        if !expiring.isEmpty {
            sentences.append("\(list(expiring.map(\.name))) \(expiring.count == 1 ? "expires" : "expire") \(when(expiring[0].date, from: fireDate, calendar: calendar)).")
        }
        if !runningOut.isEmpty {
            sentences.append("\(list(runningOut.map(\.name))) may run out \(when(runningOut[0].date, from: fireDate, calendar: calendar)).")
        }
        return sentences.joined(separator: " ")
    }

    /// "Milk", "Milk and Eggs", "Milk, Eggs and 3 more".
    static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        case 3: return "\(names[0]), \(names[1]) and \(names[2])"
        default: return "\(names[0]), \(names[1]) and \(names.count - 2) more"
        }
    }

    static func when(_ date: Date, from fireDate: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: fireDate), to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case ..<1: return "today"
        case 1: return "tomorrow"
        default: return "in \(days) days"
        }
    }
}
