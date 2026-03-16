import SwiftUI

@main
struct SlacktiveApp: App {
    @StateObject private var activityManager = ActivityManager()
    @StateObject private var scheduleManager = ScheduleManager()

    init() {
        // Wire up schedule → activity binding at launch so it works
        // even before the user opens the menu bar popover
        let schedule = _scheduleManager.wrappedValue
        let activity = _activityManager.wrappedValue
        schedule.onScheduleChange = { shouldBeActive in
            if shouldBeActive && !activity.isActive {
                activity.start()
            } else if !shouldBeActive && activity.isActive {
                activity.stop()
            }
        }
        // Apply schedule immediately on launch
        schedule.applyScheduleNow()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(activityManager: activityManager, scheduleManager: scheduleManager)
        } label: {
            Image(systemName: activityManager.isActive ? "circle.fill" : "circle")
                .foregroundColor(activityManager.isActive ? .green : .gray)
        }
        .menuBarExtraStyle(.window)

        Window("Slacktive Settings", id: "settings") {
            SettingsView()
                .environmentObject(scheduleManager)
                .environmentObject(activityManager)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 320, height: 360)
    }
}
