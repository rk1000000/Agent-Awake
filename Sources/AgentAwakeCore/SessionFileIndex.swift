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
        let children: [(url: URL, isDirectory: Bool)]
    }
    private var directories: [String: Directory] = [:]
    private let fileManager: FileManager

    init(fileManager: FileManager) { self.fileManager = fileManager }

    func files(under roots: [URL]) -> [(url: URL, rootIndex: Int)] {
        var visited = Set<String>()
        var files: [(url: URL, rootIndex: Int)] = []
        var pending = roots.enumerated().map { (url: $0.element, rootIndex: $0.offset) }
        while let directory = pending.popLast() {
            let path = directory.url.path
            guard let stamp = SessionFileStamp(path: path), stamp.isDirectory else { continue }
            visited.insert(path)
            let children: [(url: URL, isDirectory: Bool)]
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
                    return (url, values.isDirectory == true)
                }
                directories[path] = Directory(stamp: stamp, children: children)
            }
            for child in children {
                if child.isDirectory { pending.append((child.url, directory.rootIndex)) }
                else if child.url.pathExtension == "jsonl" { files.append((child.url, directory.rootIndex)) }
            }
        }
        directories = directories.filter { visited.contains($0.key) }
        return files
    }
}
