import Foundation

public struct ChargingWarningNotification {
    private var action: DelayedLidAction

    public init(delay: TimeInterval = 10) {
        action = DelayedLidAction(delay: delay)
    }

    public mutating func update(
        problemDetected: Bool,
        now: Date = Date()
    ) -> Bool {
        switch action.update(shouldApply: problemDetected, now: now) {
        case .apply:
            return true
        case .none, .restore:
            return false
        }
    }
}
