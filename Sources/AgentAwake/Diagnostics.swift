import Foundation
import AgentAwakeCore

enum Diagnostics {
    static func run() -> Int32 {
        let system = SystemSnapshot.current()
        print("Agent Awake diagnostics")
        print("Thermal: \(system.thermalLevel.displayName)")
        print("Lid closed: \(ClamshellController.lidIsClosed().map(String.init) ?? "unknown")")
        print("System SleepDisabled: \(ClamshellController.systemSleepIsDisabled().map(String.init) ?? "unknown")")
        let brightness = try? BuiltInDisplayBrightnessController().currentBrightness()
        print("Built-in display brightness: \(brightness.map { String(format: "%.0f%%", $0 * 100) } ?? "unavailable")")
        print("Low Power Mode: \(ProcessInfo.processInfo.isLowPowerModeEnabled ? "ON" : "OFF")")

        let charging = ChargingDiagnostics.presentation(for: system.chargingTelemetry)
        if charging.menuLines.isEmpty {
            print("Charging power: external power not detected")
        } else {
            charging.menuLines.forEach { print("Charging power: \($0)") }
        }

        let assertion = SleepAssertionController()
        let assertionResult = assertion.setHeld(true)
        print("Idle-sleep assertion: \(assertionResult == kIOReturnSuccess ? "OK" : "ERROR \(assertionResult)")")

        let assertionReleaseResult = assertion.setHeld(false)
        print("Idle-sleep assertion release: \(assertionReleaseResult == kIOReturnSuccess ? "OK" : "ERROR \(assertionReleaseResult)")")

        let helperInstalled = FileManager.default.isExecutableFile(
            atPath: "/Library/PrivilegedHelperTools/com.rodion.agentawake.power-helper"
        )
        print("Power helper installed: \(helperInstalled ? "OK" : "MISSING")")

        let agents = AgentActivityDetector().snapshot()
        print("Active agents: \(agents.displayText)")

        let allGreen = assertionResult == kIOReturnSuccess
            && assertionReleaseResult == kIOReturnSuccess
            && helperInstalled
            && brightness != nil
        print("Result: \(allGreen ? "PASS" : "FAIL")")
        return allGreen ? 0 : 1
    }
}
