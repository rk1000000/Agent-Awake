import Foundation

public struct TimerExpiryNotification {
    private let warningThreshold: TimeInterval
    private var warnedDeadline: Date?

    public init(warningThreshold: TimeInterval = 60) {
        self.warningThreshold = warningThreshold
    }

    public mutating func update(deadline: Date?, now: Date = Date()) -> Bool {
        guard let deadline else {
            warnedDeadline = nil
            return false
        }

        let remaining = deadline.timeIntervalSince(now)
        guard remaining > 0, remaining <= warningThreshold else {
            return false
        }
        guard warnedDeadline != deadline else {
            return false
        }

        warnedDeadline = deadline
        return true
    }
}
