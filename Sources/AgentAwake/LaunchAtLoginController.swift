import Foundation
import ServiceManagement

final class LaunchAtLoginController {
    enum LaunchError: LocalizedError {
        case appNotInstalled
        case bootstrapFailed(String)

        var errorDescription: String? {
            switch self {
            case .appNotInstalled:
                return "Автозапуск доступен после установки Agent Awake в Программы"
            case let .bootstrapFailed(message):
                return "Не удалось включить автозапуск: \(message)"
            }
        }
    }

    private let label = "com.rodion.agentawake.login"

    func ensureEnabled() throws {
        let mainApp = SMAppService.mainApp
        if mainApp.status == .enabled {
            return
        }
        if mainApp.status == .notRegistered {
            try? mainApp.register()
            if mainApp.status == .enabled {
                return
            }
        }
        try installLaunchAgent()
    }

    private func installLaunchAgent() throws {
        let appPath = Bundle.main.bundleURL.path
        guard appPath == "/Applications/Agent Awake.app" else {
            throw LaunchError.appNotInstalled
        }

        let uid = getuid()
        let launchAgentsDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        let plistURL = launchAgentsDirectory.appendingPathComponent("\(label).plist")
        try FileManager.default.createDirectory(
            at: launchAgentsDirectory,
            withIntermediateDirectories: true
        )

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["/usr/bin/open", "-a", appPath],
            "RunAtLoad": true,
            "ProcessType": "Background"
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: plistURL, options: .atomic)

        _ = runLaunchctl(["bootout", "gui/\(uid)/\(label)"])
        let bootstrap = runLaunchctl(["bootstrap", "gui/\(uid)", plistURL.path])
        guard bootstrap.status == 0 else {
            throw LaunchError.bootstrapFailed(bootstrap.output)
        }
    }

    private func runLaunchctl(_ arguments: [String]) -> (status: Int32, output: String) {
        let task = Process()
        let output = Pipe()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = arguments
        task.standardOutput = output
        task.standardError = output
        do {
            try task.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            return (task.terminationStatus, String(decoding: data, as: UTF8.self))
        } catch {
            return (1, error.localizedDescription)
        }
    }
}
