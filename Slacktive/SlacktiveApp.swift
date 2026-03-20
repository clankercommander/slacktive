import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.slacktive.app", category: "App")

@main
struct SlacktiveApp: App {
    @StateObject private var activityManager = ActivityManager()
    @StateObject private var scheduleManager = ScheduleManager()

    init() {
        // Note: Accessing _wrappedValue during init is necessary to wire up the
        // schedule → activity binding before the first SwiftUI render. This is a
        // known pattern for inter-StateObject communication during App.init().
        let schedule = _scheduleManager.wrappedValue
        let activity = _activityManager.wrappedValue
        schedule.onScheduleChange = { [weak activity] shouldBeActive in
            guard let activity else { return }
            // Don't override the user's manual toggle
            guard !activity.manualOverride else {
                logger.info("Schedule change ignored — manual override is active")
                return
            }
            if shouldBeActive && !activity.isActive {
                activity.start()
            } else if !shouldBeActive && activity.isActive {
                activity.stop()
            }
        }
        // Apply schedule immediately on launch
        schedule.applyScheduleNow()
        logger.info("Slacktive app launched")
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
