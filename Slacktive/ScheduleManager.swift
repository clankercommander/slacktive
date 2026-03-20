import Foundation
import Combine
import os.log

private let logger = Logger(subsystem: "com.slacktive.app", category: "ScheduleManager")

final class ScheduleManager: ObservableObject {
    @Published var isScheduleEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isScheduleEnabled, forKey: "scheduleEnabled")
            // When schedule is toggled, immediately apply it
            if isScheduleEnabled {
                applyScheduleNow()
            }
        }
    }
    @Published var startHour: Int {
        didSet {
            let clamped = clamp(startHour, min: 0, max: 23)
            if startHour != clamped { startHour = clamped; return }
            UserDefaults.standard.set(startHour, forKey: "startHour")
        }
    }
    @Published var startMinute: Int {
        didSet {
            let clamped = clamp(startMinute, min: 0, max: 59)
            if startMinute != clamped { startMinute = clamped; return }
            UserDefaults.standard.set(startMinute, forKey: "startMinute")
        }
    }
    @Published var endHour: Int {
        didSet {
            let clamped = clamp(endHour, min: 0, max: 23)
            if endHour != clamped { endHour = clamped; return }
            UserDefaults.standard.set(endHour, forKey: "endHour")
        }
    }
    @Published var endMinute: Int {
        didSet {
            let clamped = clamp(endMinute, min: 0, max: 59)
            if endMinute != clamped { endMinute = clamped; return }
            UserDefaults.standard.set(endMinute, forKey: "endMinute")
        }
    }
    @Published var activeDays: Set<Int> {
        didSet {
            // Filter to only valid weekday values (1–7)
            let valid = activeDays.filter { (1...7).contains($0) }
            if valid != activeDays { activeDays = valid; return }
            UserDefaults.standard.set(Array(activeDays), forKey: "activeDays")
        }
    }

    private var checkTimer: DispatchSourceTimer?
    private let scheduleQueue = DispatchQueue(label: "com.slacktive.schedule", qos: .utility)
    var onScheduleChange: ((Bool) -> Void)?

    init() {
        let defaults = UserDefaults.standard
        self.isScheduleEnabled = defaults.bool(forKey: "scheduleEnabled")
        self.startHour = Swift.min(Swift.max(defaults.object(forKey: "startHour") as? Int ?? 9, 0), 23)
        self.startMinute = Swift.min(Swift.max(defaults.object(forKey: "startMinute") as? Int ?? 0, 0), 59)
        self.endHour = Swift.min(Swift.max(defaults.object(forKey: "endHour") as? Int ?? 17, 0), 23)
        self.endMinute = Swift.min(Swift.max(defaults.object(forKey: "endMinute") as? Int ?? 0, 0), 59)

        if let savedDays = defaults.array(forKey: "activeDays") as? [Int] {
            self.activeDays = Set(savedDays.filter { (1...7).contains($0) })
        } else {
            // Monday(2) through Friday(6) in Calendar weekday format
            self.activeDays = Set(2...6)
        }

        startMonitoring()
    }

    /// Whether the current time falls within the configured schedule.
    /// Safe to call from any thread — reads only value-type published properties.
    var isWithinSchedule: Bool {
        guard isScheduleEnabled else { return false }

        let now = Date()
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: now)
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)

        guard activeDays.contains(weekday) else { return false }

        let currentMinutes = hour * 60 + minute
        let startMinutes = startHour * 60 + self.startMinute
        let endMinutes = endHour * 60 + self.endMinute

        // If start == end, the schedule window is zero-length → never active
        guard startMinutes < endMinutes else {
            logger.warning("Schedule start (\(startMinutes)m) >= end (\(endMinutes)m) — schedule is effectively disabled")
            return false
        }

        return currentMinutes >= startMinutes && currentMinutes < endMinutes
    }

    func applyScheduleNow() {
        guard isScheduleEnabled else { return }
        let shouldBeActive = isWithinSchedule
        DispatchQueue.main.async { [weak self] in
            self?.onScheduleChange?(shouldBeActive)
        }
    }

    private func startMonitoring() {
        let timer = DispatchSource.makeTimerSource(queue: scheduleQueue)
        timer.schedule(deadline: .now() + .seconds(60), repeating: .seconds(60), leeway: .seconds(5))
        timer.setEventHandler { [weak self] in
            guard let self, self.isScheduleEnabled else { return }
            let shouldBeActive = self.isWithinSchedule
            DispatchQueue.main.async { [weak self] in
                self?.onScheduleChange?(shouldBeActive)
            }
        }
        timer.resume()
        checkTimer = timer
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
        checkTimer?.cancel()
    }

    // MARK: - Helpers

    private func clamp(_ value: Int, min lo: Int, max hi: Int) -> Int {
        Swift.min(Swift.max(value, lo), hi)
    }
}

