import Foundation
import IOKit.pwr_mgt

/// Keeps the display on during a session when the user asks for it. A comfort
/// setting held by the app; the helper owns the session's system-sleep assertion.
@MainActor
final class DisplayAwakeAssertion {
    private var identifier: IOPMAssertionID?

    var isHeld: Bool { identifier != nil }

    func set(_ active: Bool) {
        if active, identifier == nil {
            var id: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                   IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                   "Vigil display awake" as CFString, &id)
            if result == kIOReturnSuccess { identifier = id }
        } else if !active, let id = identifier {
            IOPMAssertionRelease(id)
            identifier = nil
        }
    }
}
