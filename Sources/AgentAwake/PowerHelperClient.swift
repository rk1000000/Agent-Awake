import Foundation
import AgentAwakeCore

final class PowerHelperClient {
    enum HelperError: LocalizedError {
        case bundleIncomplete
        case appNotInstalled
        case authorizationFailed(String)
        case heartbeatWriteFailed(String)

        var errorDescription: String? {
            switch self {
            case .bundleIncomplete:
                return "В приложении отсутствуют файлы системного помощника"
            case .appNotInstalled:
                return "Системный помощник можно установить только из папки Программы"
            case let .authorizationFailed(message):
                return "Системный помощник не установлен: \(message)"
            case let .heartbeatWriteFailed(message):
                return "Не удалось передать состояние системному помощнику: \(message)"
            }
        }
    }

    private let uid = UInt32(getuid())
    private var wantsClosedLidAwake = false
    private var lowPowerOnLidClose = false

    private var bundledHelperURL: URL? {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LaunchServices/com.rodion.agentawake.power-helper")
    }

    private var bundledPlistURL: URL? {
        Bundle.main.url(forResource: "com.rodion.agentawake.power-helper", withExtension: "plist")
    }

    private var installerURL: URL? {
        Bundle.main.url(forResource: "install-power-helper", withExtension: "sh")
    }

    private var bundledVersionURL: URL? {
        Bundle.main.url(forResource: "power-helper", withExtension: "version")
    }

    private let installedHelperURL = URL(
        fileURLWithPath: "/Library/PrivilegedHelperTools/com.rodion.agentawake.power-helper"
    )
    private let installedPlistURL = URL(
        fileURLWithPath: "/Library/LaunchDaemons/com.rodion.agentawake.power-helper.plist"
    )
    private let installedVersionURL = URL(
        fileURLWithPath: "/Library/PrivilegedHelperTools/com.rodion.agentawake.power-helper.version"
    )

    var needsInstallation: Bool {
        guard FileManager.default.isExecutableFile(atPath: installedHelperURL.path),
              FileManager.default.fileExists(atPath: installedPlistURL.path),
              serviceIsLoaded(),
              let bundledVersionURL,
              let bundledVersion = try? String(contentsOf: bundledVersionURL, encoding: .utf8),
              let installedVersion = try? String(contentsOf: installedVersionURL, encoding: .utf8) else {
            return true
        }
        return bundledVersion.trimmingCharacters(in: .whitespacesAndNewlines)
            != installedVersion.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func serviceIsLoaded() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["print", "system/com.rodion.agentawake.power-helper"]
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

    func install() throws {
        guard Bundle.main.bundleURL.path == "/Applications/Agent Awake.app" else {
            throw HelperError.appNotInstalled
        }
        guard let bundledHelperURL,
              let bundledPlistURL,
              let installerURL,
              let bundledVersionURL,
              FileManager.default.isExecutableFile(atPath: bundledHelperURL.path),
              FileManager.default.isExecutableFile(atPath: installerURL.path) else {
            throw HelperError.bundleIncomplete
        }

        let command = [
            installerURL.path,
            bundledHelperURL.path,
            bundledPlistURL.path,
            bundledVersionURL.path
        ]
            .map(shellQuoted)
            .joined(separator: " ")
        let source = "do shell script \"\(appleScriptEscaped(command))\" with administrator privileges"
        var errorInfo: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
        guard result != nil, errorInfo == nil else {
            let message = (errorInfo?[NSAppleScript.errorMessage] as? String) ?? "разрешение не получено"
            throw HelperError.authorizationFailed(message)
        }
    }

    func setDesired(_ desired: Bool) throws {
        wantsClosedLidAwake = desired
        if desired {
            try writeHeartbeat()
        } else {
            try? FileManager.default.removeItem(at: PowerHeartbeat.url(for: uid))
        }
    }

    func setLowPowerOnLidClose(_ enabled: Bool) throws {
        guard lowPowerOnLidClose != enabled else { return }
        lowPowerOnLidClose = enabled
        if wantsClosedLidAwake {
            try writeHeartbeat()
        }
    }

    func refresh() throws {
        guard wantsClosedLidAwake else { return }
        try writeHeartbeat()
    }

    private func writeHeartbeat() throws {
        let heartbeat = PowerHeartbeat(
            pid: ProcessInfo.processInfo.processIdentifier,
            uid: uid,
            wantsClosedLidAwake: true,
            lowPowerOnLidClose: lowPowerOnLidClose,
            updatedAt: Date()
        )
        do {
            let data = try JSONEncoder().encode(heartbeat)
            let url = PowerHeartbeat.url(for: uid)
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        } catch {
            throw HelperError.heartbeatWriteFailed(error.localizedDescription)
        }
    }

    private func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    deinit {
        try? FileManager.default.removeItem(at: PowerHeartbeat.url(for: uid))
    }
}
