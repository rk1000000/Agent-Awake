import Foundation

public struct SleepProtectionNotification {
    private var action: DelayedLidAction

    public init(delay: TimeInterval = 1) {
        action = DelayedLidAction(delay: delay)
    }

    public mutating func update(
        lidClosed: Bool,
        protectionActive: Bool,
        now: Date = Date()
    ) -> Bool {
        switch action.update(shouldApply: lidClosed && protectionActive, now: now) {
        case .apply:
            return true
        case .none, .restore:
            return false
        }
    }
}
