import BackgroundTasks
import Foundation
import InventoryCore
import SwiftData

/// Recomputes forecasts and replaces pending reminders.
@MainActor
enum Reminders {
    static func refresh(context: ModelContext) async {
        let events = (try? ForecastService(context: context).upcomingEvents()) ?? []
        let plan = NotificationPlanner.plan(events: events, settings: ReminderPreferences.settings, now: Date())
        await NotificationScheduler.reschedule(plan)
    }

    static func refresh(container: ModelContainer) async {
        await refresh(context: container.mainContext)
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
