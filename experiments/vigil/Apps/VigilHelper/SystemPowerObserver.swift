import Foundation
import IOKit
import IOKit.pwr_mgt

/// Delivers system-sleep notifications on the main queue. macOS waits for
/// `IOAllowPowerChange` before sleeping, so every message is acknowledged.
enum SystemPowerObserver {
    // iokit_common_msg values; the C macros are not imported into Swift.
    private static let canSystemSleep: UInt32 = 0xE000_0270
    private static let systemWillSleep: UInt32 = 0xE000_0280

    nonisolated(unsafe) private static var rootPort: io_connect_t = 0
    nonisolated(unsafe) private static var notifier: io_object_t = 0
    nonisolated(unsafe) private static var onWillSleep: (@MainActor () -> Void)?

    @MainActor static func start(onWillSleep: @escaping @MainActor () -> Void) {
        self.onWillSleep = onWillSleep
        var port: IONotificationPortRef?
        rootPort = IORegisterForSystemPower(nil, &port, { _, _, messageType, argument in
            let token = Int(bitPattern: argument)
            switch messageType {
            case SystemPowerObserver.canSystemSleep:
                IOAllowPowerChange(SystemPowerObserver.rootPort, token)
            case SystemPowerObserver.systemWillSleep:
                MainActor.assumeIsolated { SystemPowerObserver.onWillSleep?() }
                IOAllowPowerChange(SystemPowerObserver.rootPort, token)
            default:
                break
            }
        }, &notifier)
        if let port { IONotificationPortSetDispatchQueue(port, .main) }
    }
}
