import Darwin
import Foundation

// Single-queue use, like AgentActivityDetector. Read metadata afresh on every poll.
struct SessionFileStamp: Equatable {
    let device: Int32
    let inode: UInt64
    let size: Int64
    let modifiedSeconds: Int
    let modifiedNanoseconds: Int
    let changedSeconds: Int
    let changedNanoseconds: Int
    let isDirectory: Bool
    let isRegularFile: Bool

    init?(path: String) {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        device = info.st_dev
        inode = info.st_ino
        size = info.st_size
        modifiedSeconds = info.st_mtimespec.tv_sec
        modifiedNanoseconds = info.st_mtimespec.tv_nsec
        changedSeconds = info.st_ctimespec.tv_sec
        changedNanoseconds = info.st_ctimespec.tv_nsec
        isDirectory = (info.st_mode & S_IFMT) == S_IFDIR
        isRegularFile = (info.st_mode & S_IFMT) == S_IFREG
    }

    var modifiedAt: Date {
        Date(timeIntervalSince1970: Double(modifiedSeconds) + Double(modifiedNanoseconds) / 1e9)
    }
}

final class SessionFileIndex {
    private struct Directory {
        let stamp: SessionFileStamp
        let children: [Child]
    }
    // Path strings and the journal test are computed once per directory listing: building
    // them for ~5 000 files on every two-second poll was the detector's main remaining cost.
    private struct Child {
        let url: URL
        let path: String
        let isDirectory: Bool
        let isJournal: Bool
    }
    private var directories: [String: Directory] = [:]
    private let fileManager: FileManager

    init(fileManager: FileManager) { self.fileManager = fileManager }

    func files(under roots: [URL]) -> [(url: URL, path: String, rootIndex: Int)] {
        var visited = Set<String>()
        var files: [(url: URL, path: String, rootIndex: Int)] = []
        var pending = roots.enumerated().map { (url: $0.element, path: $0.element.path, rootIndex: $0.offset) }
        while let directory = pending.popLast() {
            let path = directory.path
            guard let stamp = SessionFileStamp(path: path), stamp.isDirectory else { continue }
            visited.insert(path)
            let children: [Child]
            if let cached = directories[path], cached.stamp == stamp {
                children = cached.children
            } else {
                guard let urls = try? fileManager.contentsOfDirectory(
                    at: directory.url,
                    includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles]
                ) else {
                    directories.removeValue(forKey: path)
                    continue
                }
                children = urls.compactMap { url in
                    guard let values = try? url.resourceValues(forKeys: [
                        .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey
                    ]), values.isSymbolicLink != true, values.isPackage != true else { return nil }
                    let isDirectory = values.isDirectory == true
                    let childPath = url.path
                    return Child(
                        url: url,
                        path: childPath,
                        isDirectory: isDirectory,
                        isJournal: !isDirectory && url.pathExtension == "jsonl"
                            && !childPath.contains("claude-mem-observer-sessions")
                    )
                }
                directories[path] = Directory(stamp: stamp, children: children)
            }
            for child in children {
                if child.isDirectory { pending.append((child.url, child.path, directory.rootIndex)) }
                else if child.isJournal { files.append((child.url, child.path, directory.rootIndex)) }
            }
        }
        directories = directories.filter { visited.contains($0.key) }
        return files
    }
}
