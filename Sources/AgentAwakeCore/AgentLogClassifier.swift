import Foundation

public enum AgentLogClassifier {
    public static func codexIsActive(lines: [Data]) -> Bool {
        var isActive = false

        for line in lines {
            if let state = codexActivityState(line: line) {
                isActive = state
            }
        }

        return isActive
    }

    public static func claudeIsActive(lines: [Data]) -> Bool {
        var isActive = false

        for line in lines {
            if let state = claudeActivityState(line: line) {
                isActive = state
            }
        }

        return isActive
    }

    public static func codexActivityState(line: Data) -> Bool? {
        guard let object = jsonObject(from: line),
              object["type"] as? String == "event_msg",
              let payload = object["payload"] as? [String: Any],
              let payloadType = payload["type"] as? String else {
            return nil
        }

        if payloadType == "task_started" { return true }
        if payloadType == "task_complete" { return false }
        return nil
    }

    public static func claudeActivityState(line: Data) -> Bool? {
        guard let object = jsonObject(from: line),
              let type = object["type"] as? String else {
            return nil
        }

        if type == "user",
           let message = object["message"] as? [String: Any],
           message["content"] is String {
            return true
        }

        if type == "assistant",
           let message = object["message"] as? [String: Any],
           message["stop_reason"] as? String == "end_turn" {
            return false
        }

        if type == "system", object["subtype"] as? String == "stop_hook_summary" {
            return false
        }

        return nil
    }

    private static func jsonObject(from line: Data) -> [String: Any]? {
        guard !line.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: line),
              let dictionary = object as? [String: Any] else {
            return nil
        }

        return dictionary
    }
}
