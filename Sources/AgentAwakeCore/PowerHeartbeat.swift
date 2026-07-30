import Foundation

public struct PowerHeartbeat: Codable, Equatable {
    public static let filePrefix = "com.rodion.agentawake."
    public static let fileSuffix = ".power-heartbeat"
    public static let lowPowerAppliedMarkerURL = URL(
        fileURLWithPath: "/var/run/com.rodion.agentawake.low-power-applied"
    )

    public let pid: Int32
    public let uid: UInt32
    public let wantsClosedLidAwake: Bool
    public let lowPowerOnLidClose: Bool
    public let updatedAt: Date

    public init(
        pid: Int32,
        uid: UInt32,
        wantsClosedLidAwake: Bool,
        lowPowerOnLidClose: Bool = false,
        updatedAt: Date
    ) {
        self.pid = pid
        self.uid = uid
        self.wantsClosedLidAwake = wantsClosedLidAwake
        self.lowPowerOnLidClose = lowPowerOnLidClose
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case pid
        case uid
        case wantsClosedLidAwake
        case lowPowerOnLidClose
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pid = try container.decode(Int32.self, forKey: .pid)
        uid = try container.decode(UInt32.self, forKey: .uid)
        wantsClosedLidAwake = try container.decode(Bool.self, forKey: .wantsClosedLidAwake)
        lowPowerOnLidClose = try container.decodeIfPresent(Bool.self, forKey: .lowPowerOnLidClose) ?? false
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    public func isFresh(at now: Date, maximumAge: TimeInterval = 10) -> Bool {
        wantsClosedLidAwake
            && now.timeIntervalSince(updatedAt) >= 0
            && now.timeIntervalSince(updatedAt) <= maximumAge
    }

    public static func url(for uid: UInt32) -> URL {
        URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("\(filePrefix)\(uid)\(fileSuffix)")
    }
}
