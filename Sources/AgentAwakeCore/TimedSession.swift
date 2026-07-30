import Foundation

public enum TimedSession {
    public static let allowedMinutes = 1...60

    public static func parseMinutes(_ text: String) -> Int? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let minutes = Int(normalized), allowedMinutes.contains(minutes) else {
            return nil
        }
        return minutes
    }

    public static func remainingLabel(until: Date, now: Date = Date()) -> String {
        let remainingSeconds = max(0, until.timeIntervalSince(now))
        let remainingMinutes = Int(ceil(remainingSeconds / 60))
        return "\(remainingMinutes)m"
    }
}
