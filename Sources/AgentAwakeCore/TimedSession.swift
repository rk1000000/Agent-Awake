import Foundation

public enum TimedSession {
    /// Custom timer: from 1 minute up to 24 hours, entered as hours and minutes.
    public static let allowedMinutes = 1...(24 * 60)

    /// Total minutes for the hours and minutes fields; an empty field counts as zero.
    public static func parseDuration(hours: String, minutes: String) -> Int? {
        guard let hourValue = wholeNumber(hours), (0...24).contains(hourValue),
              let minuteValue = wholeNumber(minutes), (0...59).contains(minuteValue) else {
            return nil
        }
        let total = hourValue * 60 + minuteValue
        return allowedMinutes.contains(total) ? total : nil
    }

    public static func remainingLabel(until: Date, now: Date = Date()) -> String {
        let remainingSeconds = max(0, until.timeIntervalSince(now))
        let remainingMinutes = Int(ceil(remainingSeconds / 60))
        guard remainingMinutes >= 60 else { return "\(remainingMinutes)m" }
        return String(format: "%dh %02dm", remainingMinutes / 60, remainingMinutes % 60)
    }

    private static func wholeNumber(_ text: String) -> Int? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty { return 0 }
        guard normalized.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(normalized) else { return nil }
        return value
    }
}
