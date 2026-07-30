import Foundation

public struct PowerHeartbeatCandidate {
    public let fileName: String
    public let ownerUID: UInt32
    public let permissions: UInt16
    public let byteCount: Int
    public let isRegularFile: Bool
    public let heartbeat: PowerHeartbeat
    public let processPath: String
    public let processUID: UInt32

    public init(
        fileName: String,
        ownerUID: UInt32,
        permissions: UInt16,
        byteCount: Int,
        isRegularFile: Bool,
        heartbeat: PowerHeartbeat,
        processPath: String,
        processUID: UInt32
    ) {
        self.fileName = fileName
        self.ownerUID = ownerUID
        self.permissions = permissions
        self.byteCount = byteCount
        self.isRegularFile = isRegularFile
        self.heartbeat = heartbeat
        self.processPath = processPath
        self.processUID = processUID
    }
}

public enum PowerHeartbeatValidator {
    public static let maximumByteCount = 4_096
    public static let expectedProcessPath = "/Applications/Agent Awake.app/Contents/MacOS/AgentAwake"

    public static func accepts(
        _ candidate: PowerHeartbeatCandidate,
        now: Date = Date()
    ) -> Bool {
        candidate.isRegularFile
            && candidate.byteCount > 0
            && candidate.byteCount <= maximumByteCount
            && candidate.permissions & 0o777 == 0o600
            && candidate.fileName == PowerHeartbeat.url(for: candidate.heartbeat.uid).lastPathComponent
            && candidate.ownerUID == candidate.heartbeat.uid
            && candidate.processUID == candidate.heartbeat.uid
            && candidate.processPath == expectedProcessPath
            && candidate.heartbeat.isFresh(at: now)
    }
}
