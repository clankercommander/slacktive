import SwiftUI
import ServiceManagement

struct MenuBarView: View {
    @ObservedObject var activityManager: ActivityManager
    @ObservedObject var scheduleManager: ScheduleManager
    @Environment(\.openWindow) private var openWindow
    @State private var manualOverride = false

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Text("Slacktive")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(activityManager.isActive ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)
            }

            Divider()

            // Status
            HStack {
                Image(systemName: activityManager.isActive ? "bolt.fill" : "bolt.slash")
                    .foregroundColor(activityManager.isActive ? .green : .secondary)
                Text(activityManager.isActive ? "Keeping you active" : "Inactive")
                    .foregroundColor(activityManager.isActive ? .primary : .secondary)
                Spacer()
            }

            // Toggle
            Toggle(isOn: Binding(
                get: { activityManager.isActive },
                set: { newValue in
                    manualOverride = true
                    if newValue { activityManager.start() } else { activityManager.stop() }
                }
            )) {
                Text("Stay Active")
            }
            .tint(.green)
            .toggleStyle(.switch)

            // Schedule indicator
            if scheduleManager.isScheduleEnabled {
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text(scheduleDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }

            Divider()

            // Buttons
            Button(action: {
                // Delay to let the MenuBarExtra popover dismiss first
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }) {
                HStack {
                    Image(systemName: "gear")
                    Text("Settings")
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            Button(action: { NSApplication.shared.terminate(nil) }) {
                HStack {
                    Image(systemName: "power")
                    Text("Quit Slacktive")
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        }
        .padding()
        .frame(width: 240)
        .onAppear {
            setupScheduleBinding()
        }
        .onDisappear {
            // Reset manual override when popover closes so schedule can resume control
            manualOverride = false
        }
    }

    private var scheduleDescription: String {
        let days = ScheduleManager.weekdayIndices
            .filter { scheduleManager.activeDays.contains($0) }
            .map { ScheduleManager.dayNames[$0 - 1] }
            .joined(separator: ", ")

        let startStr = String(format: "%d:%02d", scheduleManager.startHour, scheduleManager.startMinute)
        let endStr = String(format: "%d:%02d", scheduleManager.endHour, scheduleManager.endMinute)

        return "\(days) \(startStr)–\(endStr)"
    }

    private func setupScheduleBinding() {
        // Override the app-level binding with one that respects manual override
        scheduleManager.onScheduleChange = { shouldBeActive in
            guard !manualOverride else { return }
            if shouldBeActive && !activityManager.isActive {
                activityManager.start()
            } else if !shouldBeActive && activityManager.isActive {
                activityManager.stop()
            }
        }
    }
}
