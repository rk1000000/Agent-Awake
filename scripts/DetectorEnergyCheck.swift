import Foundation
import Darwin

@main
struct DetectorEnergyCheck {
    static func require(_ condition: Bool, _ message: String) {
        if !condition { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }

    static func main() throws {
        let fm = FileManager.default
        let temporary = fm.temporaryDirectory.appendingPathComponent("detector-energy-\(UUID())")
        try fm.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temporary) }
        let realHome = fm.homeDirectoryForCurrentUser
        var codex = 0
        var claude = 0
        for (source, target, limit) in [(".codex/sessions", ".codex/sessions", 25), (".claude/projects", ".claude/projects/project", 25)] {
            let root = realHome.appendingPathComponent(source)
            let files = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])!
            var selected: [(URL, Date)] = []
            for case let file as URL in files where file.pathExtension == "jsonl" && !file.path.contains("claude-mem-observer-sessions") {
                if let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
                    selected.append((file, date))
                }
            }
            let destination = temporary.appendingPathComponent(target)
            try fm.createDirectory(at: destination, withIntermediateDirectories: true)
            for (index, entry) in selected.sorted(by: { $0.1 > $1.1 }).prefix(limit).enumerated() {
                let copy = destination.appendingPathComponent("\(index).jsonl")
                try fm.copyItem(at: entry.0, to: copy)
                try fm.setAttributes([.modificationDate: Date()], ofItemAtPath: copy.path)
                let before = BeforeDetector(homeURL: temporary).snapshot()
                let after = AgentActivityDetector(homeURL: temporary).snapshot()
                require(before == after, "real corpus mismatch at \(source) #\(index)")
                if source.contains("codex") { codex += 1 } else { claude += 1 }
            }
        }
        require(codex == 25 && claude == 25, "need 50 real sessions")
        let detector = AgentActivityDetector(homeURL: temporary)
        let baseline = BeforeDetector(homeURL: temporary)
        require(detector.snapshot() == baseline.snapshot(), "initial parity")
        require(detector.snapshot() == baseline.snapshot(), "cached parity")
        let active = Data("{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\"}}\n".utf8)
        let complete = Data("{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\"}}\n".utf8)
        let nested = temporary.appendingPathComponent(".codex/sessions/new/day")
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        let file = nested.appendingPathComponent("new.jsonl")
        try active.write(to: file)
        require(detector.snapshot() == baseline.snapshot(), "new directory/session")
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: complete)
        try handle.close()
        require(detector.snapshot() == baseline.snapshot(), "completion append invalidates cache")
        try active.write(to: file)
        require(detector.snapshot() == baseline.snapshot(), "truncation")
        try fm.setAttributes([.modificationDate: Date().addingTimeInterval(-1900)], ofItemAtPath: file.path)
        require(detector.snapshot() == baseline.snapshot(), "expiry")
        try fm.removeItem(at: nested)
        require(detector.snapshot() == baseline.snapshot(), "directory deletion")
        print("PASS: 50 real sessions, cached parity, new session, append, truncate, expiry, deletion")
        let live = AgentActivityDetector()
        let old = BeforeDetector()
        var beforeTime = 0.0
        var afterTime = 0.0
        for _ in 0..<5 {
            let start = Date()
            _ = old.snapshot()
            beforeTime += Date().timeIntervalSince(start)
        }
        _ = live.snapshot()
        for _ in 0..<10 {
            let start = Date()
            _ = live.snapshot()
            afterTime += Date().timeIntervalSince(start)
        }
        beforeTime /= 5
        afterTime /= 10
        print(String(format: "Live archive: before %.4fs/poll; after %.4fs/poll; speedup %.1fx", beforeTime, afterTime, beforeTime / afterTime))
        require(afterTime < beforeTime * 0.5, "poll must be at least twice as fast")
    }
}
