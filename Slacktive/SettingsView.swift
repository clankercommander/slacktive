import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var scheduleManager: ScheduleManager
    @State private var launchAtLogin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.title2)
                .fontWeight(.semibold)

            Divider()

            // Schedule Section
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Enable Schedule", isOn: $scheduleManager.isScheduleEnabled)
                    .tint(.green)
                    .toggleStyle(.switch)

                if scheduleManager.isScheduleEnabled {
                    // Time pickers
                    HStack(spacing: 16) {
                        VStack(alignment: .leading) {
                            Text("Start").font(.caption).foregroundColor(.secondary)
                            DatePicker("", selection: $scheduleManager.startTime, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }
                        VStack(alignment: .leading) {
                            Text("End").font(.caption).foregroundColor(.secondary)
                            DatePicker("", selection: $scheduleManager.endTime, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }
                    }

                    // Day selector
                    Text("Active Days").font(.caption).foregroundColor(.secondary)
                    HStack(spacing: 4) {
                        ForEach(ScheduleManager.weekdayIndices, id: \.self) { day in
                            DayButton(
                                label: ScheduleManager.dayNames[day - 1],
                                isSelected: scheduleManager.activeDays.contains(day),
                                action: {
                                    if scheduleManager.activeDays.contains(day) {
                                        scheduleManager.activeDays.remove(day)
                                    } else {
                                        scheduleManager.activeDays.insert(day)
                                    }
                                }
                            )
                        }
                    }
                }
            }

            Divider()

            // Launch at Login
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .tint(.green)
                .toggleStyle(.switch)
                .onChange(of: launchAtLogin) { newValue in
                    setLaunchAtLogin(newValue)
                }

            Spacer()

            HStack {
                Spacer()
                Button("Done") {
                        NSApplication.shared.keyWindow?.close()
                    }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320, height: 360)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        .onReceive(scheduleManager.objectWillChange) { _ in
            DispatchQueue.main.async {
                NSApp.windows
                    .first { $0.title == "Slacktive Settings" }?
                    .makeKeyAndOrderFront(nil)
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Silently fail - user can toggle again
        }
    }
}

struct DayButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption2)
                .fontWeight(.medium)
                .frame(width: 32, height: 26)
                .background(isSelected ? Color.accentColor : Color.clear)
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}
