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
    private let fileManager: FileManager
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
        self.fileManager = fileManager
    }

    public func snapshot(now: Date = Date()) -> AgentActivitySnapshot {
        let codexRoot = homeURL.appendingPathComponent(".codex/sessions", isDirectory: true)
        let claudeRoot = homeURL.appendingPathComponent(".claude/projects", isDirectory: true)

        let codexCount = recentJSONLFiles(under: codexRoot, now: now)
            .filter {
                lastActivityState(from: $0, classifier: AgentLogClassifier.codexActivityState) == true
            }
            .count

        let claudeCount = recentJSONLFiles(under: claudeRoot, now: now)
            .filter { !$0.path.contains("claude-mem-observer-sessions") }
            .filter {
                lastActivityState(from: $0, classifier: AgentLogClassifier.claudeActivityState) == true
            }
            .count

        return AgentActivitySnapshot(
            codexActiveCount: codexCount,
            claudeActiveCount: claudeCount
        )
    }

    private func recentJSONLFiles(under root: URL, now: Date) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var results: [URL] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let modifiedAt = values.contentModificationDate,
                  now.timeIntervalSince(modifiedAt) <= maximumSessionAge else {
                continue
            }
            results.append(fileURL)
        }
        return results
    }

    private func lastActivityState(
        from fileURL: URL,
        classifier: (Data) -> Bool?
    ) -> Bool? {
        guard let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return nil
        }

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
