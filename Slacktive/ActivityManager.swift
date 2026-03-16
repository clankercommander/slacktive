import Foundation
import IOKit.pwr_mgt
import CoreGraphics

final class ActivityManager: ObservableObject {
    @Published var isActive = false

    private var assertionID: IOPMAssertionID = 0
    private var hasAssertion = false
    private var mouseTimer: Timer?

    func start() {
        guard !isActive else { return }
        isActive = true
        startSleepPrevention()
        startMouseSimulation()
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        stopSleepPrevention()
        stopMouseSimulation()
    }

    func toggle() {
        if isActive { stop() } else { start() }
    }

    // MARK: - Sleep Prevention

    private func startSleepPrevention() {
        let reason = "Slacktive keeping system active" as CFString
        let success = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID
        )
        hasAssertion = (success == kIOReturnSuccess)
    }

    private func stopSleepPrevention() {
        if hasAssertion {
            IOPMAssertionRelease(assertionID)
            hasAssertion = false
        }
    }

    // MARK: - Mouse Simulation

    private func startMouseSimulation() {
        scheduleNextMovement()
    }

    private func stopMouseSimulation() {
        mouseTimer?.invalidate()
        mouseTimer = nil
    }

    private func scheduleNextMovement() {
        let interval = TimeInterval.random(in: 30...120)
        mouseTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.performMouseJiggle()
            self?.scheduleNextMovement()
        }
    }

    private func performMouseJiggle() {
        guard let eventSource = CGEventSource(stateID: .hidSystemState) else { return }

        let currentPos = CGEvent(source: nil)?.location ?? .zero
        let dx = CGFloat.random(in: 1...2) * (Bool.random() ? 1 : -1)
        let dy = CGFloat.random(in: 1...2) * (Bool.random() ? 1 : -1)

        let movedPos = CGPoint(x: currentPos.x + dx, y: currentPos.y + dy)

        // Move slightly
        let moveEvent = CGEvent(
            mouseEventSource: eventSource,
            mouseType: .mouseMoved,
            mouseCursorPosition: movedPos,
            mouseButton: .left
        )
        moveEvent?.post(tap: .cghidEventTap)

        // Move back after a tiny delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let returnEvent = CGEvent(
                mouseEventSource: eventSource,
                mouseType: .mouseMoved,
                mouseCursorPosition: currentPos,
                mouseButton: .left
            )
            returnEvent?.post(tap: .cghidEventTap)
        }
    }

    deinit {
        stop()
    }
}
