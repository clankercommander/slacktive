import SwiftUI

@main
struct SlacktiveApp: App {
    @StateObject private var activityManager = ActivityManager()
    @StateObject private var scheduleManager = ScheduleManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(activityManager: activityManager, scheduleManager: scheduleManager)
        } label: {
            Image(systemName: activityManager.isActive ? "circle.fill" : "circle")
                .foregroundColor(activityManager.isActive ? .green : .gray)
        }
        .menuBarExtraStyle(.window)

        Window("Slacktive Settings", id: "settings") {
            SettingsView(scheduleManager: scheduleManager)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 320, height: 360)
    }
}
