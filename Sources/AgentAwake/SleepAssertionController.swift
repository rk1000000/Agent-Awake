import Foundation
import IOKit.pwr_mgt

final class SleepAssertionController {
    private(set) var isHeld = false
    private(set) var assertionID = IOPMAssertionID(0)

    @discardableResult
    func setHeld(_ shouldHold: Bool) -> IOReturn {
        if shouldHold == isHeld {
            return kIOReturnSuccess
        }

        if shouldHold {
            var newAssertionID = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Agent Awake: active session" as CFString,
                &newAssertionID
            )
            if result == kIOReturnSuccess {
                assertionID = newAssertionID
                isHeld = true
            }
            return result
        }

        let result = IOPMAssertionRelease(assertionID)
        if result == kIOReturnSuccess {
            assertionID = IOPMAssertionID(0)
            isHeld = false
        }
        return result
    }

    deinit {
        if isHeld {
            IOPMAssertionRelease(assertionID)
        }
    }
}
