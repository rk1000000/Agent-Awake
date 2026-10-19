import Darwin
import Foundation
import AgentAwakeCore
import OSLog

private let sleepOwnershipMarker = URL(fileURLWithPath: "/var/run/com.rodion.agentawake.sleep-disabled")
private let lowPowerOwnershipMarker = URL(fileURLWithPath: "/var/run/com.rodion.agentawake.low-power")
private let lowPowerAppliedMarker = PowerHeartbeat.lowPowerAppliedMarkerURL
private let maximumHeartbeatAge: TimeInterval = 10
private let logger = Logger(subsystem: "com.rodion.agentawake", category: "power-helper")
private var shouldStop = false
private var lowPowerAction = DelayedLidAction(
    delay: 10,
    initiallyApplied: FileManager.default.fileExists(atPath: lowPowerOwnershipMarker.path)
)

private struct ProcessIdentity {
    let path: String
    let uid: UInt32
}

private func processIdentity(pid: pid_t) -> ProcessIdentity? {
    var buffer = [CChar](repeating: 0, count: 4_096)
    let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
    guard length > 0 else { return nil }

    var info = proc_bsdinfo()
    let infoSize = MemoryLayout<proc_bsdinfo>.size
    let readSize = withUnsafeMutablePointer(to: &info) { pointer in
        proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, pointer, Int32(infoSize))
    }
    guard readSize == infoSize else { return nil }
    return ProcessIdentity(path: String(cString: buffer), uid: info.pbi_uid)
}

private func candidate(named name: String) -> PowerHeartbeatCandidate? {
    let url = URL(fileURLWithPath: "/tmp").appendingPathComponent(name)
    let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    guard descriptor >= 0 else { return nil }
    defer { close(descriptor) }

    var fileInfo = stat()
    guard fstat(descriptor, &fileInfo) == 0,
          fileInfo.st_size > 0,
          fileInfo.st_size <= PowerHeartbeatValidator.maximumByteCount else {
        return nil
    }

    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
    guard let data = try? handle.read(upToCount: PowerHeartbeatValidator.maximumByteCount + 1),
          data.count <= PowerHeartbeatValidator.maximumByteCount,
          let heartbeat = try? JSONDecoder().decode(PowerHeartbeat.self, from: data),
          let process = processIdentity(pid: heartbeat.pid) else {
        return nil
    }

    return PowerHeartbeatCandidate(
        fileName: name,
        ownerUID: fileInfo.st_uid,
        permissions: UInt16(fileInfo.st_mode & 0o777),
        byteCount: data.count,
        isRegularFile: fileInfo.st_mode & S_IFMT == S_IFREG,
        heartbeat: heartbeat,
        processPath: process.path,
        processUID: process.uid
    )
}

private func validHeartbeat(now: Date = Date()) -> PowerHeartbeat? {
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: "/tmp") else {
        return nil
    }

    for name in names where name.hasPrefix(PowerHeartbeat.filePrefix)
        && name.hasSuffix(PowerHeartbeat.fileSuffix) {
        guard let candidate = candidate(named: name),
              candidate.heartbeat.isFresh(at: now, maximumAge: maximumHeartbeatAge),
              PowerHeartbeatValidator.accepts(candidate, now: now) else {
            continue
        }
        return candidate.heartbeat
    }
    return nil
}

private func sleepIsDisabled() -> Bool {
    ClamshellController.systemSleepIsDisabled() ?? false
}

@discardableResult
private func setSleepDisabled(_ disabled: Bool) -> Bool {
    setPowerSetting("disablesleep", enabled: disabled)
}

@discardableResult
private func setLowPowerMode(_ enabled: Bool) -> Bool {
    setPowerSetting("lowpowermode", enabled: enabled)
}

private func setPowerSetting(_ setting: String, enabled: Bool) -> Bool {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    task.arguments = ["-a", setting, enabled ? "1" : "0"]
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    do {
        try task.run()
        task.waitUntilExit()
        return task.terminationStatus == 0
    } catch {
        return false
    }
}

private func owns(_ marker: URL) -> Bool {
    FileManager.default.fileExists(atPath: marker.path)
}

private func mark(_ marker: URL) -> Bool {
    FileManager.default.createFile(atPath: marker.path, contents: Data())
}

private func clear(_ marker: URL) {
    try? FileManager.default.removeItem(at: marker)
}

private func reconcileSleepOverride(heartbeatExists: Bool) {
    let currentlyDisabled = sleepIsDisabled()

    if heartbeatExists {
        guard !currentlyDisabled else { return }
        guard mark(sleepOwnershipMarker) else { return }
        if !setSleepDisabled(true) {
            clear(sleepOwnershipMarker)
        }
        return
    }

    guard owns(sleepOwnershipMarker) else { return }
    if !currentlyDisabled || setSleepDisabled(false) {
        clear(sleepOwnershipMarker)
    }
}

private func reconcileLowPower(heartbeat: PowerHeartbeat?, now: Date) {
    if !owns(lowPowerOwnershipMarker) {
        clear(lowPowerAppliedMarker)
    }

    let shouldApply = heartbeat?.lowPowerOnLidClose == true
        && ClamshellController.lidIsClosed() == true

    switch lowPowerAction.update(shouldApply: shouldApply, now: now) {
    case .none:
        return
    case .apply:
        guard mark(lowPowerOwnershipMarker) else {
            lowPowerAction = DelayedLidAction(delay: 10)
            return
        }
        if setLowPowerMode(true) {
            if mark(lowPowerAppliedMarker) {
                logger.notice("low power mode enabled and confirmed after lid delay")
            } else {
                logger.error("low power mode enabled but confirmation marker failed")
            }
        } else {
            clear(lowPowerOwnershipMarker)
            clear(lowPowerAppliedMarker)
            lowPowerAction = DelayedLidAction(delay: 10)
        }
    case .restore:
        guard owns(lowPowerOwnershipMarker) else {
            clear(lowPowerAppliedMarker)
            return
        }
        if setLowPowerMode(false) {
            clear(lowPowerAppliedMarker)
            clear(lowPowerOwnershipMarker)
            logger.notice("low power mode disabled after lid opened or heartbeat stopped")
        } else {
            lowPowerAction = DelayedLidAction(delay: 10, initiallyApplied: true)
        }
    }
}

private func reconcile(now: Date = Date()) {
    let heartbeat = validHeartbeat(now: now)
    reconcileSleepOverride(heartbeatExists: heartbeat != nil)
    reconcileLowPower(heartbeat: heartbeat, now: now)
}

signal(SIGTERM) { _ in shouldStop = true }
signal(SIGINT) { _ in shouldStop = true }

while !shouldStop {
    autoreleasepool {
        reconcile()
    }
    Thread.sleep(forTimeInterval: 1)
}

if owns(sleepOwnershipMarker) {
    _ = setSleepDisabled(false)
    clear(sleepOwnershipMarker)
}
if owns(lowPowerOwnershipMarker) {
    _ = setLowPowerMode(false)
    clear(lowPowerOwnershipMarker)
}
clear(lowPowerAppliedMarker)
