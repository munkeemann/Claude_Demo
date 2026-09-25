import Foundation
import InventoryCore
import UserNotifications

/// User-facing reminder settings, stored in UserDefaults.
enum ReminderPreferences {
    static let enabledKey = "reminders.enabled"
    static let expiryLeadKey = "reminders.expiryLeadDays"
    static let runOutLeadKey = "reminders.runOutLeadDays"
    static let hourKey = "reminders.hour"
    static let tossEnabledKey = "reminders.toss.enabled"
    static let tossHourKey = "reminders.toss.hour"
    static let horizonKey = "forecast.horizonDays"

    static var settings: NotificationSettings {
        let defaults = UserDefaults.standard
        return NotificationSettings(
            isEnabled: defaults.object(forKey: enabledKey) as? Bool ?? false,
            expiryLeadDays: defaults.object(forKey: expiryLeadKey) as? Int ?? 2,
            runOutLeadDays: defaults.object(forKey: runOutLeadKey) as? Int ?? 3,
            hour: defaults.object(forKey: hourKey) as? Int ?? 9,
            tossRemindersEnabled: defaults.object(forKey: tossEnabledKey) as? Bool ?? true,
            tossHour: defaults.object(forKey: tossHourKey) as? Int ?? 18
        )
    }

    /// How far ahead "Running low soon" and the shopping list look.
    static var horizonDays: Int {
        UserDefaults.standard.object(forKey: horizonKey) as? Int ?? 7
    }
}

/// Replaces Larder's pending reminders with a freshly computed plan.
enum NotificationScheduler {
    /// Toss reminders carry a "Tossed them" button.
    static let tossCategory = "larder.toss"
    static let tossedAction = "larder.toss.done"
    /// `userInfo` key holding the covered item IDs as strings.
    static let itemIDsKey = "itemIDs"
    /// `userInfo` key naming the tab a tap should open.
    static let tabKey = "tab"

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Declares the notification actions. Call once at launch.
    static func registerCategories() {
        let tossed = UNNotificationAction(identifier: tossedAction, title: "Tossed them", options: [])
        let toss = UNNotificationCategory(identifier: tossCategory, actions: [tossed], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([toss])
    }

    static func reschedule(_ plan: [PlannedNotification]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(NotificationPlanner.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let calendar = Calendar.current
        for notification in plan {
            let content = UNMutableNotificationContent()
            content.title = notification.title
            content.body = notification.body
            content.sound = .default
            content.userInfo[tabKey] = "soon"
            if notification.kind == .toss {
                content.categoryIdentifier = tossCategory
                content.userInfo[itemIDsKey] = notification.itemIDs.map(\.uuidString)
                content.threadIdentifier = "toss"
            }
            if let badge = notification.badge {
                content.badge = NSNumber(value: badge)
            }
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: notification.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: notification.id, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    /// Shows how many items are past their date on the app icon.
    static func setBadge(_ count: Int) async {
        try? await UNUserNotificationCenter.current().setBadgeCount(count)
    }
}
