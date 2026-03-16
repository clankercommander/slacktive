import Foundation
import Combine

final class ScheduleManager: ObservableObject {
    @Published var isScheduleEnabled: Bool {
        didSet { UserDefaults.standard.set(isScheduleEnabled, forKey: "scheduleEnabled") }
    }
    @Published var startHour: Int {
        didSet { UserDefaults.standard.set(startHour, forKey: "startHour") }
    }
    @Published var startMinute: Int {
        didSet { UserDefaults.standard.set(startMinute, forKey: "startMinute") }
    }
    @Published var endHour: Int {
        didSet { UserDefaults.standard.set(endHour, forKey: "endHour") }
    }
    @Published var endMinute: Int {
        didSet { UserDefaults.standard.set(endMinute, forKey: "endMinute") }
    }
    @Published var activeDays: Set<Int> {
        didSet { UserDefaults.standard.set(Array(activeDays), forKey: "activeDays") }
    }

    private var checkTimer: Timer?
    var onScheduleChange: ((Bool) -> Void)?

    init() {
        let defaults = UserDefaults.standard
        self.isScheduleEnabled = defaults.bool(forKey: "scheduleEnabled")
        self.startHour = defaults.object(forKey: "startHour") as? Int ?? 9
        self.startMinute = defaults.object(forKey: "startMinute") as? Int ?? 0
        self.endHour = defaults.object(forKey: "endHour") as? Int ?? 17
        self.endMinute = defaults.object(forKey: "endMinute") as? Int ?? 0

        if let savedDays = defaults.array(forKey: "activeDays") as? [Int] {
            self.activeDays = Set(savedDays)
        } else {
            // Monday(2) through Friday(6) in Calendar weekday format
            self.activeDays = Set(2...6)
        }

        startMonitoring()
    }

    var isWithinSchedule: Bool {
        guard isScheduleEnabled else { return false }

        let now = Date()
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: now)
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)

        guard activeDays.contains(weekday) else { return false }

        let currentMinutes = hour * 60 + minute
        let startMinutes = startHour * 60 + startMinute
        let endMinutes = endHour * 60 + endMinute

        return currentMinutes >= startMinutes && currentMinutes < endMinutes
    }

    private func startMonitoring() {
        checkTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self, self.isScheduleEnabled else { return }
            self.onScheduleChange?(self.isWithinSchedule)
        }
    }

    var startTime: Date {
        get {
            Calendar.current.date(from: DateComponents(hour: startHour, minute: startMinute)) ?? Date()
        }
        set {
            let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            startHour = comps.hour ?? 9
            startMinute = comps.minute ?? 0
        }
    }

    var endTime: Date {
        get {
            Calendar.current.date(from: DateComponents(hour: endHour, minute: endMinute)) ?? Date()
        }
        set {
            let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            endHour = comps.hour ?? 17
            endMinute = comps.minute ?? 0
        }
    }

    static let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    // Calendar weekday: 1=Sunday, 2=Monday, ..., 7=Saturday
    static let weekdayIndices = [1, 2, 3, 4, 5, 6, 7]

    deinit {
        checkTimer?.invalidate()
    }
}
