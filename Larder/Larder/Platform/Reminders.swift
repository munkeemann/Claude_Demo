import BackgroundTasks
import Foundation
import InventoryCore
import SwiftData

/// Recomputes forecasts and replaces pending reminders.
@MainActor
enum Reminders {
    static func refresh(context: ModelContext) async {
        let service = ForecastService(context: context)
        let settings = ReminderPreferences.settings
        let events = (try? service.upcomingEvents()) ?? []
        let plan = NotificationPlanner.plan(events: events, settings: settings, now: Date())
        await NotificationScheduler.reschedule(plan)
        let expired = settings.isEnabled && settings.tossRemindersEnabled ? ((try? service.expiredItemCount()) ?? 0) : 0
        await NotificationScheduler.setBadge(expired)
    }

    static func refresh(container: ModelContainer) async {
        await refresh(context: container.mainContext)
    }

    /// The "Tossed them" notification action: marks each item tossed (which
    /// logs a discard), then replans so the badge and reminders catch up.
    static func markTossed(_ ids: [UUID], container: ModelContainer) async {
        let context = container.mainContext
        let store = InventoryStore(context: context)
        for id in ids {
            guard let item = try? store.item(id: id), item.status.isActive else { continue }
            _ = try? store.apply(.tossed, to: item)
        }
        await refresh(context: context)
    }
}

/// Periodic background refresh so reminders stay current even if the app
/// isn't opened. The identifier is listed in Info.plist.
enum BackgroundRefresh {
    static let identifier = "com.munkeemann.larder.refresh"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date().addingTimeInterval(6 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }
}
