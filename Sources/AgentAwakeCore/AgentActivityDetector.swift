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
        /// State decided by newline-terminated lines only, and the offset just past them.
        /// An append-only journal resumes from here instead of re-reading its tail.
        let completeState: Bool?
        let parsedOffset: Int
        /// First bytes of the file and the bytes just before `parsedOffset`. A file truncated
        /// and rewritten in place keeps its inode, so these must still match before resuming.
        let head: Data
        let anchor: Data
        /// Time of the last full tail read. Resuming is allowed only for a minute after it, so a
        /// rewrite that keeps both fingerprints can mislead the count for at most that long.
        let verifiedAt: Date
        /// False when the state came from resuming; such a state is re-read after a minute
        /// even if the file does not change again.
        let isVerified: Bool
    }
    private static let fingerprintSize = 256
    private static let fullReadInterval: TimeInterval = 60
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
            let path = entry.path
            guard let stamp = SessionFileStamp(path: path), stamp.isRegularFile,
                  now.timeIntervalSince(stamp.modifiedAt) <= maximumSessionAge else { continue }
            let isCodex = entry.rootIndex == 0
            let classifier = isCodex ? AgentLogClassifier.codexActivityState
                : AgentLogClassifier.claudeActivityState
            let cached: CachedState
            if let previous = states[path], previous.stamp == stamp,
               previous.isVerified || now.timeIntervalSince(previous.verifiedAt) < Self.fullReadInterval {
                cached = previous
            } else if let previous = states[path],
                      previous.stamp.device == stamp.device,
                      previous.stamp.inode == stamp.inode,
                      stamp.size > previous.stamp.size,
                      now.timeIntervalSince(previous.verifiedAt) < Self.fullReadInterval,
                      let appended = appendedState(
                        from: file,
                        previous: previous,
                        stamp: stamp,
                        classifier: classifier
                      ) {
                cached = appended
            } else {
                let state = lastActivityState(
                    from: file,
                    fileSize: Int(stamp.size),
                    classifier: classifier
                )
                // Never cache a result if a writer changed the file during the read.
                if SessionFileStamp(path: path) != stamp {
                    if state == true {
                        if isCodex { codexCount += 1 } else { claudeCount += 1 }
                    }
                    continue
                }
                let boundary = lineBoundary(in: file, fileSize: Int(stamp.size))
                cached = CachedState(
                    stamp: stamp,
                    state: state,
                    completeState: state,
                    parsedOffset: boundary,
                    head: bytes(of: file, in: 0..<min(boundary, Self.fingerprintSize)) ?? Data(),
                    anchor: bytes(of: file, in: max(0, boundary - Self.fingerprintSize)..<boundary) ?? Data(),
                    verifiedAt: now,
                    isVerified: true
                )
            }
            retainedStates[path] = cached
            if cached.state == true {
                if isCodex { codexCount += 1 } else { claudeCount += 1 }
            }
        }
        states = retainedStates
        return AgentActivitySnapshot(codexActiveCount: codexCount, claudeActiveCount: claudeCount)
    }

    /// Reads only bytes appended since the previous poll. The journal prefix is assumed
    /// unchanged; a replaced or truncated file fails the inode/size checks and is re-read.
    private func appendedState(
        from fileURL: URL,
        previous: CachedState,
        stamp: SessionFileStamp,
        classifier: (Data) -> Bool?
    ) -> CachedState? {
        let end = Int(stamp.size)
        let anchorStart = previous.parsedOffset - previous.anchor.count
        guard previous.parsedOffset <= end,
              bytes(of: fileURL, in: 0..<previous.head.count) == previous.head,
              let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: UInt64(anchorStart))) != nil,
              let read = try? handle.read(upToCount: end - anchorStart),
              read.count == end - anchorStart,
              read.prefix(previous.anchor.count) == previous.anchor else { return nil }
        let data = Data(read.dropFirst(previous.anchor.count))

        var completeState = previous.completeState
        var parsedOffset = previous.parsedOffset
        var trailing = Data()
        if let lastNewline = data.lastIndex(of: 0x0A) {
            let complete = data[data.startIndex..<lastNewline]
            for line in complete.split(separator: 0x0A).reversed() {
                if let state = classifier(Data(line)) {
                    completeState = state
                    break
                }
            }
            parsedOffset += data.distance(from: data.startIndex, to: lastNewline) + 1
            trailing = Data(data[data.index(after: lastNewline)...])
        } else {
            trailing = data
        }
        // A last line without its newline yet still counts, exactly as in a full tail read.
        let state = trailing.isEmpty ? completeState : (classifier(trailing) ?? completeState)
        let anchorData = Data((previous.anchor + data.prefix(parsedOffset - previous.parsedOffset))
            .suffix(Self.fingerprintSize))
        var head = previous.head
        if head.count < Self.fingerprintSize, parsedOffset > head.count {
            head = bytes(of: fileURL, in: 0..<min(parsedOffset, Self.fingerprintSize)) ?? head
        }
        return CachedState(
            stamp: stamp,
            state: state,
            completeState: completeState,
            parsedOffset: parsedOffset,
            head: head,
            anchor: anchorData,
            verifiedAt: previous.verifiedAt,
            isVerified: false
        )
    }

    private func bytes(of fileURL: URL, in range: Range<Int>) -> Data? {
        guard !range.isEmpty else { return Data() }
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: UInt64(range.lowerBound))) != nil,
              let data = try? handle.read(upToCount: range.count),
              data.count == range.count else { return nil }
        return data
    }

    /// Offset just past the last newline, scanning back from the end in 64 KB steps.
    private func lineBoundary(in fileURL: URL, fileSize: Int) -> Int {
        guard fileSize > 0, let handle = try? FileHandle(forReadingFrom: fileURL) else { return 0 }
        defer { try? handle.close() }
        var end = fileSize
        while end > 0 {
            let start = max(0, end - 64 * 1024)
            guard (try? handle.seek(toOffset: UInt64(start))) != nil,
                  let chunk = try? handle.read(upToCount: end - start),
                  !chunk.isEmpty else { return 0 }
            if let newline = chunk.lastIndex(of: 0x0A) {
                return start + chunk.distance(from: chunk.startIndex, to: newline) + 1
            }
            end = start
        }
        return 0
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
