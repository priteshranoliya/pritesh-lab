import AppKit

/// Manual launches open the popover; login and service launches stay quiet.
public enum LaunchPresentation {
    public static func shouldShowPopover(for event: NSAppleEventDescriptor?) -> Bool {
        guard event?.eventID == kAEOpenApplication else { return true }
        // macOS describes login/service launches in the open-application event.
        let launchReason = event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue
        return launchReason != keyAELaunchedAsLogInItem && launchReason != keyAELaunchedAsServiceItem
    }
}
