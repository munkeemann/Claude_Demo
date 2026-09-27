import InventoryCore
import SwiftUI

/// Reminder toggles and lead times. Changes reschedule immediately.
struct RemindersSettingsSection: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(ReminderPreferences.enabledKey) private var isEnabled = false
    @AppStorage(ReminderPreferences.expiryLeadKey) private var expiryLeadDays = 2
    @AppStorage(ReminderPreferences.runOutLeadKey) private var runOutLeadDays = 3
    @AppStorage(ReminderPreferences.hourKey) private var hour = 9
    @AppStorage(ReminderPreferences.tossEnabledKey) private var tossEnabled = true
    @AppStorage(ReminderPreferences.tossHourKey) private var tossHour = 18
    @AppStorage(ReminderPreferences.horizonKey) private var horizonDays = 7
    @State private var permissionDenied = false

    var body: some View {
        Section {
            Toggle("Reminders", isOn: $isEnabled)
                .onChange(of: isEnabled) { _, enabled in
                    guard enabled else {
                        reschedule()
                        return
                    }
                    Task {
                        let granted = await NotificationScheduler.requestAuthorization()
                        permissionDenied = !granted
                        if !granted { isEnabled = false }
                        reschedule()
                    }
                }

            if isEnabled {
                Stepper(value: $expiryLeadDays, in: 0...7) {
                    LabeledContent("Before expiry", value: dayCount(expiryLeadDays))
                }
                Stepper(value: $runOutLeadDays, in: 0...14) {
                    LabeledContent("Before running out", value: dayCount(runOutLeadDays))
                }
                Picker("Time", selection: $hour) {
                    ForEach(6..<22, id: \.self) { hour in
                        Text(hourLabel(hour)).tag(hour)
                    }
                }
                Toggle(isOn: $tossEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Toss reminders")
                        Text("When something passes its date")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if tossEnabled {
                    Picker("Toss reminder time", selection: $tossHour) {
                        ForEach(6..<23, id: \.self) { hour in
                            Text(hourLabel(hour)).tag(hour)
                        }
                    }
                }
            }

            Picker("Look ahead", selection: $horizonDays) {
                Text("3 days").tag(3)
                Text("1 week").tag(7)
                Text("2 weeks").tag(14)
            }
        } header: {
            Text("Reminders & forecasts")
        } footer: {
            if permissionDenied {
                Text("Notifications are turned off for Larder. Enable them in the Settings app.")
                    .foregroundStyle(Theme.terracotta)
            } else {
                Text("Reminders for the same day are combined into one notification. Toss reminders arrive the evening after an item's date, when you're likely in the kitchen, and \"Tossed them\" clears the items right from the notification. \"Look ahead\" sets how far the Soon tab and shopping suggestions look.")
            }
        }
        .onChange(of: expiryLeadDays) { _, _ in reschedule() }
        .onChange(of: runOutLeadDays) { _, _ in reschedule() }
        .onChange(of: hour) { _, _ in reschedule() }
        .onChange(of: tossEnabled) { _, _ in reschedule() }
        .onChange(of: tossHour) { _, _ in reschedule() }
    }

    private func dayCount(_ days: Int) -> String {
        switch days {
        case 0: "Same day"
        case 1: "1 day"
        default: "\(days) days"
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func reschedule() {
        let context = modelContext
        Task { await Reminders.refresh(context: context) }
    }
}
