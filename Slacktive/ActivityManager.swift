import Foundation
import AppKit
import IOKit.pwr_mgt
import CoreGraphics
import os.log

private let logger = Logger(subsystem: "com.slacktive.app", category: "ActivityManager")

final class ActivityManager: ObservableObject {
    @Published var isActive = false

    /// When true, the schedule cannot change the active state.
    /// Set when the user manually toggles and auto-resets after 5 minutes.
    @Published private(set) var manualOverride = false

    private var assertionID: IOPMAssertionID = 0
    private var hasAssertion = false
    private var mouseTimer: DispatchSourceTimer?
    /// Serial queue that protects all mutable timer and assertion state.
    private let timerQueue = DispatchQueue(label: "com.slacktive.jiggle", qos: .utility)

    private var systemActivityTimer: DispatchSourceTimer?
    private var userActivityAssertionID: IOPMAssertionID = 0
    private var overrideResetWork: DispatchWorkItem?

    // MARK: - Public API (call from main thread)

    /// Called by the schedule system — respects manual override.
    func start() {
        guard !isActive else { return }
        isActive = true
        timerQueue.async { [self] in
            startSleepPrevention()
            startMouseSimulation()
            startSystemActivityPoke()
        }
        logger.info("Slacktive activated — sleep prevention, mouse jiggle, and system activity poke all running")
    }

    /// Called by the schedule system — respects manual override.
    func stop() {
        guard isActive else { return }
        isActive = false
        timerQueue.async { [self] in
            stopSleepPrevention()
            stopMouseSimulation()
            stopSystemActivityPoke()
        }
        logger.info("Slacktive deactivated")
    }

    /// Called when the user explicitly toggles ON. Sets a 5-minute manual override
    /// so the schedule doesn't immediately undo their action.
    func manualStart() {
        setManualOverride()
        start()
    }

    /// Called when the user explicitly toggles OFF. Sets a 5-minute manual override
    /// so the schedule doesn't immediately re-enable.
    func manualStop() {
        setManualOverride()
        stop()
    }

    func toggle() {
        if isActive { manualStop() } else { manualStart() }
    }

    /// Clear the manual override so the schedule can resume control.
    func clearManualOverride() {
        overrideResetWork?.cancel()
        overrideResetWork = nil
        manualOverride = false
        logger.info("Manual override cleared — schedule can resume control")
    }

    private func setManualOverride() {
        overrideResetWork?.cancel()
        manualOverride = true
        let work = DispatchWorkItem { [weak self] in
            self?.manualOverride = false
            logger.info("Manual override auto-expired after 5 minutes")
        }
        overrideResetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 300, execute: work)
        logger.info("Manual override set — schedule suppressed for 5 minutes")
    }

    // MARK: - Sleep Prevention (IOKit Power Assertion)
    // Called on timerQueue

    private func startSleepPrevention() {
        // Release any existing assertion first to avoid leaks on double-start
        stopSleepPrevention()

        let reason = "Slacktive keeping system active" as CFString

        var displayAssertionID: IOPMAssertionID = 0
        let displayResult = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &displayAssertionID
        )

        if displayResult == kIOReturnSuccess {
            assertionID = displayAssertionID
            hasAssertion = true
            logger.info("Power assertion created successfully (ID: \(displayAssertionID))")
        } else {
            logger.error("Failed to create power assertion: \(displayResult)")

            // Fallback: try the system sleep assertion
            var systemAssertionID: IOPMAssertionID = 0
            let systemResult = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &systemAssertionID
            )
            if systemResult == kIOReturnSuccess {
                assertionID = systemAssertionID
                hasAssertion = true
                logger.info("Fallback system sleep assertion created (ID: \(systemAssertionID))")
            } else {
                logger.error("Fallback system sleep assertion also failed: \(systemResult)")
            }
        }
    }

    private func stopSleepPrevention() {
        if hasAssertion {
            IOPMAssertionRelease(assertionID)
            hasAssertion = false
            assertionID = 0
            logger.info("Power assertion released")
        }
    }

    // MARK: - System Activity Declaration
    //
    // IOPMAssertionDeclareUserActivity() informs the Power Manager that user activity
    // has occurred, which resets the system idle timer. CGEvent mouse moves do NOT
    // reliably reset HIDIdleTime on modern macOS.
    //
    // Called every 30 seconds on timerQueue.

    private func startSystemActivityPoke() {
        // Cancel any existing timer to avoid duplicates
        systemActivityTimer?.cancel()

        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now(), repeating: .seconds(30), leeway: .seconds(2))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            var aid: IOPMAssertionID = self.userActivityAssertionID
            let result = IOPMAssertionDeclareUserActivity(
                "Slacktive user activity" as CFString,
                kIOPMUserActiveLocal,
                &aid
            )
            if result == kIOReturnSuccess {
                self.userActivityAssertionID = aid
                logger.debug("User activity declared (assertion ID: \(aid))")
            } else {
                logger.warning("Failed to declare user activity: \(result)")
            }
        }
        timer.resume()
        systemActivityTimer = timer
    }

    private func stopSystemActivityPoke() {
        systemActivityTimer?.cancel()
        systemActivityTimer = nil
    }

    // MARK: - Mouse Simulation
    //
    // Secondary mechanism for application-level idle detection (Slack's own checks).
    //
    // Design:
    //   - Fires every ~4-5 minutes (randomized 240-300s)
    //   - Before moving, checks system idle time. If < 30s, the user is actively
    //     using the computer and we skip the jiggle entirely.
    //   - Movement is a tiny circle (~4px radius) — looks like a brief "pinhead" wobble
    //   - Cursor always returns to its exact original position
    //
    // All mouse timer state is managed on timerQueue.

    /// Minimum system idle time (seconds) before we'll jiggle.
    /// If the user has been active within this window, we skip.
    private static let idleThresholdBeforeJiggle: TimeInterval = 30

    /// Radius of the circle pattern in pixels.
    private static let jiggleRadius: CGFloat = 4

    /// Steps in the circle (4 = diamond pattern, 8 = smoother circle)
    private static let circleSteps = 4

    /// Delay between each step of the circle (seconds)
    private static let circleStepDelay: TimeInterval = 0.03

    private func startMouseSimulation() {
        scheduleNextMovement()
    }

    private func stopMouseSimulation() {
        mouseTimer?.cancel()
        mouseTimer = nil
    }

    private func scheduleNextMovement() {
        // Cancel any existing timer before creating a new one to prevent leaks
        mouseTimer?.cancel()

        // Randomize between 4 and 5 minutes
        let interval = Int.random(in: 240...300)
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now() + .seconds(interval))
        timer.setEventHandler { [weak self] in
            self?.performMouseJiggle()
            self?.scheduleNextMovement()
        }
        timer.resume()
        mouseTimer = timer
    }

    private func performMouseJiggle() {
        // Check if the user is actively using the computer.
        // If they've had activity in the last 30 seconds, skip the jiggle
        // so we never move the mouse during active use.
        if let idleTime = ActivityManager.systemIdleTime, idleTime < Self.idleThresholdBeforeJiggle {
            logger.debug("Skipping mouse jiggle — user is active (idle: \(String(format: "%.1f", idleTime))s)")
            return
        }

        guard let eventSource = CGEventSource(stateID: .hidSystemState) else {
            logger.warning("Failed to create CGEventSource")
            return
        }

        guard let locationEvent = CGEvent(source: nil) else {
            logger.warning("Failed to get current mouse location event")
            return
        }
        let origin = locationEvent.location

        // Move in a small circle: N evenly-spaced points around the origin
        let steps = Self.circleSteps
        let radius = Self.jiggleRadius

        for i in 0..<steps {
            let angle = (2.0 * .pi / Double(steps)) * Double(i)
            let x = origin.x + radius * CGFloat(cos(angle))
            let y = origin.y + radius * CGFloat(sin(angle))

            timerQueue.asyncAfter(deadline: .now() + Self.circleStepDelay * Double(i)) {
                self.postMouseMove(to: CGPoint(x: x, y: y), source: eventSource)
            }
        }

        // Return to the original position after the circle completes
        let returnDelay = Self.circleStepDelay * Double(steps)
        timerQueue.asyncAfter(deadline: .now() + returnDelay) {
            self.postMouseMove(to: origin, source: eventSource)
        }

        // F16 key tap after the circle finishes, as additional idle reset signal
        timerQueue.asyncAfter(deadline: .now() + returnDelay + 0.02) {
            self.simulateInertKeyTap(eventSource: eventSource)
        }

        logger.debug("Mouse circle jiggle at (\(origin.x), \(origin.y)), radius=\(radius)px, \(steps) steps")
    }

    /// Post a single mouse move CGEvent to the given position.
    private func postMouseMove(to position: CGPoint, source: CGEventSource) {
        if let event = CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: position,
            mouseButton: .left
        ) {
            let uptimeNs = UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
            event.timestamp = uptimeNs
            event.post(tap: .cghidEventTap)
        }
    }

    /// Simulate pressing and releasing F16.
    /// F16 is a no-op key that resets idle timers without any visible side-effects.
    private func simulateInertKeyTap(eventSource: CGEventSource) {
        let f16KeyCode: CGKeyCode = 106

        if let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: f16KeyCode, keyDown: true) {
            keyDown.flags = []  // No modifier flags — this is a bare keypress
            let uptimeNs = UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
            keyDown.timestamp = uptimeNs
            keyDown.post(tap: .cghidEventTap)
        }

        timerQueue.asyncAfter(deadline: .now() + 0.02) {
            if let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: f16KeyCode, keyDown: false) {
                keyUp.flags = []
                let uptimeNs = UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
                keyUp.timestamp = uptimeNs
                keyUp.post(tap: .cghidEventTap)
            }
        }
    }

    // MARK: - Diagnostics

    /// Returns the current system idle time in seconds (useful for debugging)
    static var systemIdleTime: TimeInterval? {
        var iterator: io_iterator_t = 0
        defer { IOObjectRelease(iterator) }

        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOHIDSystem"),
            &iterator
        ) == KERN_SUCCESS else { return nil }

        let entry = IOIteratorNext(iterator)
        defer { IOObjectRelease(entry) }
        guard entry != 0 else { return nil }

        guard let dict = IORegistryEntryCreateCFProperty(
            entry,
            "HIDIdleTime" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? NSNumber else { return nil }

        return dict.doubleValue / 1_000_000_000.0
    }

    deinit {
        // Direct cleanup — no need to dispatch since we're being deallocated.
        // Cancel timers synchronously to prevent dangling references.
        mouseTimer?.cancel()
        systemActivityTimer?.cancel()
        if hasAssertion {
            IOPMAssertionRelease(assertionID)
        }
    }
}
