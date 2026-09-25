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
    /// Remind to throw things out once they're past their date.
    public var tossRemindersEnabled: Bool
    /// Hour of day (0–23) toss reminders are delivered: a time people are
    /// usually home and in the kitchen.
    public var tossHour: Int

    public init(
        isEnabled: Bool = true,
        expiryLeadDays: Int = 2,
        runOutLeadDays: Int = 3,
        hour: Int = 9,
        minimumRunOutConfidence: ForecastConfidence = .medium,
        tossRemindersEnabled: Bool = true,
        tossHour: Int = 18
    ) {
        self.isEnabled = isEnabled
        self.expiryLeadDays = expiryLeadDays
        self.runOutLeadDays = runOutLeadDays
        self.hour = hour
        self.minimumRunOutConfidence = minimumRunOutConfidence
        self.tossRemindersEnabled = tossRemindersEnabled
        self.tossHour = tossHour
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
    /// The inventory item an expiry belongs to, so a toss reminder can mark
    /// it tossed from the notification.
    public var itemID: UUID?

    public init(name: String, date: Date, kind: Kind, confidence: ForecastConfidence = .high, itemID: UUID? = nil) {
        self.name = name
        self.date = date
        self.kind = kind
        self.confidence = confidence
        self.itemID = itemID
    }
}

public struct PlannedNotification: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// "Use it soon" / "Running low", ahead of time.
        case headsUp
        /// Something is past its date: throw it out.
        case toss
    }

    public var id: String
    public var fireDate: Date
    public var title: String
    public var body: String
    public var kind: Kind = .headsUp
    /// Items a toss reminder covers.
    public var itemIDs: [UUID] = []
    /// App badge to show: items expired by the time this fires.
    public var badge: Int?
}

/// Turns upcoming expiries and run-outs into local notifications.
///
/// iOS keeps only the 64 soonest pending local notifications per app, so
/// reminders that fall on the same day are grouped into one notification
/// ("Spinach, Milk and 2 more expire soon"), and at most `limit` are
/// scheduled. Heads-up reminders whose time has already passed are skipped;
/// the in-app "Soon" list covers those.
///
/// Toss reminders fire at `tossHour` the day after an item's date. Items
/// that expired within the last `tossNagDays` days and are still in stock
/// get a reminder at the next toss time, so turning reminders on (or not
/// opening the app for a while) doesn't lose them.
public enum NotificationPlanner {
    public static let identifierPrefix = "larder.reminder."
    public static let limit = 60
    public static let tossNagDays = 7

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

        let headsUp = byDay.keys.map { fireDate in
            let group = byDay[fireDate]!.sorted { ($0.date, $0.name) < ($1.date, $1.name) }
            return PlannedNotification(
                id: identifierPrefix + dayStamp(fireDate, calendar: calendar),
                fireDate: fireDate,
                title: title(for: group),
                body: body(for: group, on: fireDate, calendar: calendar)
            )
        }
        let toss = settings.tossRemindersEnabled ? tossReminders(events: events, settings: settings, now: now, calendar: calendar) : []
        return (headsUp + toss).sorted { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }.prefix(limit).map { $0 }
    }

    static func tossReminders(
        events: [UpcomingEvent],
        settings: NotificationSettings,
        now: Date,
        calendar: Calendar
    ) -> [PlannedNotification] {
        let expiring = events.filter { $0.kind == .expires }
        var byTime: [Date: [UpcomingEvent]] = [:]
        for event in expiring {
            let expiryDay = calendar.startOfDay(for: event.date)
            guard let tossDay = calendar.date(byAdding: .day, value: 1, to: expiryDay),
                  var fireDate = calendar.date(bySettingHour: settings.tossHour, minute: 0, second: 0, of: tossDay)
            else { continue }
            if fireDate <= now {
                let daysPast = calendar.dateComponents([.day], from: tossDay, to: calendar.startOfDay(for: now)).day ?? 0
                guard daysPast < tossNagDays, let next = nextOccurrence(hour: settings.tossHour, after: now, calendar: calendar) else { continue }
                fireDate = next
            }
            byTime[fireDate, default: []].append(event)
        }

        return byTime.keys.map { fireDate in
            let group = byTime[fireDate]!.sorted { ($0.date, $0.name) < ($1.date, $1.name) }
            let fireDay = calendar.startOfDay(for: fireDate)
            let expiredByThen = expiring.filter { calendar.startOfDay(for: $0.date) < fireDay }.count
            return PlannedNotification(
                id: identifierPrefix + dayStamp(fireDate, calendar: calendar) + ".toss",
                fireDate: fireDate,
                title: group.count == 1 ? "Past its date: \(group[0].name)" : "\(group.count) items are past their date",
                body: tossBody(for: group, on: fireDate, calendar: calendar),
                kind: .toss,
                itemIDs: group.compactMap(\.itemID),
                badge: expiredByThen
            )
        }
    }

    static func tossBody(for group: [UpcomingEvent], on fireDate: Date, calendar: Calendar) -> String {
        guard group.count > 1 else {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: group[0].date), to: calendar.startOfDay(for: fireDate)).day ?? 1
            let when = days <= 1 ? "yesterday" : "\(days) days ago"
            return "It expired \(when). Toss it next time you're in the kitchen."
        }
        return "\(list(group.map(\.name))) expired. Toss them next time you're in the kitchen."
    }

    /// Today at `hour` if that's still ahead, otherwise tomorrow.
    static func nextOccurrence(hour: Int, after now: Date, calendar: Calendar) -> Date? {
        guard let today = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now) else { return nil }
        return today > now ? today : calendar.date(byAdding: .day, value: 1, to: today)
    }

    static func dayStamp(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
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
