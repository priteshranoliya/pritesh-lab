import Foundation

/// Names and paths shared by the app, the helper, the CLI and the install script.
/// `script/helper.sh` repeats the paths; keep both in sync.
public enum VigilIdentity {
    public static let version = "0.1.1"
    /// Bump when `HelperRequest`/`HelperResponse` change incompatibly.
    public static let protocolVersion = 1

    public static let appBundleID = "app.vigil.Vigil"
    public static let helperLabel = "app.vigil.Vigil.helper"
    public static let socketPath = "/var/run/app.vigil.helper.sock"
    public static let helperInstallPath = "/Library/PrivilegedHelperTools/app.vigil.Vigil.helper"
    public static let launchDaemonPath = "/Library/LaunchDaemons/app.vigil.Vigil.helper.plist"
    public static let stateDirectory = "/private/var/db/app.vigil.helper"
}
