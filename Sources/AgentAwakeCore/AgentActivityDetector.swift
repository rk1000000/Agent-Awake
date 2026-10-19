import Foundation

public struct AgentActivitySnapshot: Equatable {
    public let codexActiveCount: Int
    public let claudeActiveCount: Int

    public init(codexActiveCount: Int, claudeActiveCount: Int) {
        self.codexActiveCount = codexActiveCount
        self.claudeActiveCount = claudeActiveCount
    }

    public var totalActiveCount: Int {
        codexActiveCount + claudeActiveCount
    }

    public var displayText: String {
        var parts: [String] = []
        if codexActiveCount > 0 { parts.append("Codex ×\(codexActiveCount)") }
        if claudeActiveCount > 0 { parts.append("Claude Code ×\(claudeActiveCount)") }
        return parts.isEmpty ? "нет активной работы" : parts.joined(separator: ", ")
    }
}

public final class AgentActivityDetector {
    private let fileIndex: SessionFileIndex
    private struct CachedState {
        let stamp: SessionFileStamp
        let state: Bool?
    }
    private var states: [String: CachedState] = [:]
    private let homeURL: URL
    private let maximumSessionAge: TimeInterval
    private let initialTailSize = 256 * 1024

    public init(
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        maximumSessionAge: TimeInterval = 30 * 60,
        fileManager: FileManager = .default
    ) {
        self.homeURL = homeURL
        self.maximumSessionAge = maximumSessionAge
        self.fileIndex = SessionFileIndex(fileManager: fileManager)
    }

    public func snapshot(now: Date = Date()) -> AgentActivitySnapshot {
        let codexRoot = homeURL.appendingPathComponent(".codex/sessions", isDirectory: true)
        let claudeRoot = homeURL.appendingPathComponent(".claude/projects", isDirectory: true)

        var retainedStates: [String: CachedState] = [:]
        var codexCount = 0
        var claudeCount = 0
        for entry in fileIndex.files(under: [codexRoot, claudeRoot]) {
            let file = entry.url
            let path = file.path
            guard !path.contains("claude-mem-observer-sessions"),
                  let stamp = SessionFileStamp(path: path), stamp.isRegularFile,
                  now.timeIntervalSince(stamp.modifiedAt) <= maximumSessionAge else { continue }
            let isCodex = entry.rootIndex == 0
            let cached: CachedState
            if let previous = states[path], previous.stamp == stamp {
                cached = previous
            } else {
                let state = lastActivityState(
                    from: file,
                    fileSize: Int(stamp.size),
                    classifier: isCodex ? AgentLogClassifier.codexActivityState
                        : AgentLogClassifier.claudeActivityState
                )
                // Never cache a result if a writer changed the file during the read.
                if SessionFileStamp(path: path) != stamp {
                    if state == true {
                        if isCodex { codexCount += 1 } else { claudeCount += 1 }
                    }
                    continue
                }
                cached = CachedState(stamp: stamp, state: state)
            }
            retainedStates[path] = cached
            if cached.state == true {
                if isCodex { codexCount += 1 } else { claudeCount += 1 }
            }
        }
        states = retainedStates
        return AgentActivitySnapshot(codexActiveCount: codexCount, claudeActiveCount: claudeCount)
    }

    private func lastActivityState(
        from fileURL: URL,
        fileSize: Int,
        classifier: (Data) -> Bool?
    ) -> Bool? {
        var tailSize = min(initialTailSize, fileSize)
        while tailSize > 0 {
            let lines = readTailLines(from: fileURL, maximumSize: tailSize)
            for line in lines.reversed() {
                if let state = classifier(line) {
                    return state
                }
            }

            if tailSize >= fileSize { return nil }
            tailSize = min(fileSize, tailSize * 2)
        }
        return nil
    }

    private func readTailLines(from fileURL: URL, maximumSize: Int) -> [Data] {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return []
        }
        defer { try? handle.close() }

        do {
            let size = try handle.seekToEnd()
            let start = size > UInt64(maximumSize) ? size - UInt64(maximumSize) : 0
            try handle.seek(toOffset: start)
            guard var data = try handle.readToEnd(), !data.isEmpty else {
                return []
            }

            if start > 0, let firstNewline = data.firstIndex(of: 0x0A) {
                data.removeSubrange(data.startIndex...firstNewline)
            }

            let bytes = [UInt8](data)
            return bytes.split(separator: 0x0A).map { Data($0) }
        } catch {
            return []
        }
    }
}
