import Foundation
import IOKit
import IOKit.pwr_mgt

public enum ClamshellController {
    public static func setSleepDisabled(_ disabled: Bool) -> IOReturn {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPMrootDomain")
        )
        guard service != IO_OBJECT_NULL else {
            return kIOReturnNotFound
        }
        defer { IOObjectRelease(service) }

        var connection = io_connect_t()
        let openResult = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard openResult == kIOReturnSuccess else {
            return openResult
        }
        defer { IOServiceClose(connection) }

        var input: UInt64 = disabled ? 1 : 0
        var outputCount: UInt32 = 0
        return withUnsafePointer(to: &input) { inputPointer in
            IOConnectCallScalarMethod(
                connection,
                UInt32(kPMSetClamshellSleepState),
                inputPointer,
                1,
                nil,
                &outputCount
            )
        }
    }

    public static func lidIsClosed() -> Bool? {
        boolProperty(named: "AppleClamshellState")
    }

    public static func lidCurrentlyCausesSleep() -> Bool? {
        boolProperty(named: "AppleClamshellCausesSleep")
    }

    public static func systemSleepIsDisabled() -> Bool? {
        boolProperty(named: "SleepDisabled")
    }

    private static func boolProperty(named name: String) -> Bool? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPMrootDomain")
        )
        guard service != IO_OBJECT_NULL else {
            return nil
        }
        defer { IOObjectRelease(service) }

        guard let property = IORegistryEntryCreateCFProperty(
            service,
            name as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else {
            return nil
        }

        return property as? Bool
    }
}
