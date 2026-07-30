import Foundation
import AgentAwakeCore

enum Diagnostics {
    static func run() -> Int32 {
        print("Agent Awake diagnostics")
        print("Thermal: \(SystemSnapshot.current().thermalLevel.displayName)")
        print("Lid closed: \(ClamshellController.lidIsClosed().map(String.init) ?? "unknown")")
        print("System SleepDisabled: \(ClamshellController.systemSleepIsDisabled().map(String.init) ?? "unknown")")
        let brightness = try? BuiltInDisplayBrightnessController().currentBrightness()
        print("Built-in display brightness: \(brightness.map { String(format: "%.0f%%", $0 * 100) } ?? "unavailable")")
        print("Low Power Mode: \(ProcessInfo.processInfo.isLowPowerModeEnabled ? "ON" : "OFF")")

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
