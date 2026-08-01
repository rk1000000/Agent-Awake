import Foundation
import IOKit.ps
import AgentAwakeCore

struct SystemSnapshot {
    let thermalLevel: ThermalLevel
    let lidClosed: Bool
    let lidCausesSleep: Bool?
    let powerDescription: String
    let chargingTelemetry: ChargingTelemetry

    static func current() -> SystemSnapshot {
        SystemSnapshot(
            thermalLevel: thermalLevel(from: ProcessInfo.processInfo.thermalState),
            lidClosed: ClamshellController.lidIsClosed() ?? false,
            lidCausesSleep: ClamshellController.lidCurrentlyCausesSleep(),
            powerDescription: currentPowerDescription(),
            chargingTelemetry: ChargingPowerReader.current()
        )
    }

    private static func thermalLevel(from state: ProcessInfo.ThermalState) -> ThermalLevel {
        switch state {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .nominal
        }
    }

    private static func currentPowerDescription() -> String {
        guard let powerInfo = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(powerInfo)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let rawDescription = IOPSGetPowerSourceDescription(powerInfo, source)?.takeUnretainedValue(),
              let description = rawDescription as? [String: Any] else {
            return "неизвестно"
        }

        let powerState = description[kIOPSPowerSourceStateKey as String] as? String
        let currentCapacity = description[kIOPSCurrentCapacityKey as String] as? Int
        let maximumCapacity = description[kIOPSMaxCapacityKey as String] as? Int
        let isCharging = description[kIOPSIsChargingKey as String] as? Bool ?? false

        var parts: [String] = []
        if powerState == kIOPSACPowerValue {
            parts.append(isCharging ? "сеть, зарядка" : "сеть")
        } else if powerState == kIOPSBatteryPowerValue {
            parts.append("батарея")
        }

        if let currentCapacity, let maximumCapacity, maximumCapacity > 0 {
            let percentage = Int((Double(currentCapacity) / Double(maximumCapacity) * 100).rounded())
            parts.append("\(percentage)%")
        }

        return parts.isEmpty ? "неизвестно" : parts.joined(separator: " · ")
    }
}
