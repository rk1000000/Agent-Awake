import Foundation
import Darwin
import IOKit
import IOKit.ps
import AgentAwakeCore

enum ChargingPowerReader {
    static func current() -> ChargingTelemetry {
        let description = batteryDescription()
        let adapter = externalAdapterDetails()
        let telemetry = smartBatteryDictionary(named: "PowerTelemetryData")
        let charger = smartBatteryDictionary(named: "ChargerData")

        let powerState = description?[kIOPSPowerSourceStateKey as String] as? String
        let externalPowerConnected = powerState == kIOPSACPowerValue || adapter != nil

        return ChargingTelemetry(
            externalPowerConnected: externalPowerConnected,
            adapterWatts: validAdapterWatts(adapter?[kIOPSPowerAdapterWattsKey as String]),
            recommendedAdapterWatts: MacPowerProfile.recommendedAdapterWatts(
                forModelIdentifier: hardwareModelIdentifier()
            ),
            inputWatts: positiveMilliwatts(telemetry?["SystemPowerIn"]),
            batteryWatts: signedMilliwatts(telemetry?["BatteryPower"]),
            slowChargingDetected: (integer(charger?["SlowChargingReason"]) ?? 0) > 0
        )
    }

    private static func batteryDescription() -> [String: Any]? {
        guard let powerInfo = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(powerInfo)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return nil
        }

        for source in sources {
            guard let raw = IOPSGetPowerSourceDescription(powerInfo, source)?.takeUnretainedValue(),
                  let description = raw as? [String: Any],
                  description[kIOPSTypeKey as String] as? String == kIOPSInternalBatteryType else {
                continue
            }
            return description
        }
        return nil
    }

    private static func externalAdapterDetails() -> [String: Any]? {
        guard let raw = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() else {
            return nil
        }
        return raw as? [String: Any]
    }

    private static func smartBatteryDictionary(named name: String) -> [String: Any]? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        guard let property = IORegistryEntryCreateCFProperty(
            service,
            name as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else {
            return nil
        }
        return property as? [String: Any]
    }

    private static func integer(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    private static func hardwareModelIdentifier() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 1 else {
            return ""
        }

        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else {
            return ""
        }
        return String(cString: bytes)
    }

    private static func validAdapterWatts(_ value: Any?) -> Int? {
        guard let watts = integer(value), (1...500).contains(watts) else { return nil }
        return watts
    }

    private static func positiveMilliwatts(_ value: Any?) -> Double? {
        guard let milliwatts = value as? NSNumber else { return nil }
        let watts = milliwatts.doubleValue / 1_000
        return watts > 0 && watts <= 500 ? watts : nil
    }

    private static func signedMilliwatts(_ value: Any?) -> Double? {
        guard let milliwatts = value as? NSNumber else { return nil }
        let watts = Double(milliwatts.int64Value) / 1_000
        return abs(watts) <= 500 ? watts : nil
    }
}
