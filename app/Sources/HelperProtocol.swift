import Foundation

/// What Recall asks of its helper (app/Helper/main.swift), a LaunchDaemon bundled in the app
/// for the two settings that need root: Steady Wi-Fi and fan speed (GameHelper). Also compiled
/// into the helper, so both sides share these names.
@objc(RecallHelperProtocol) protocol RecallHelperProtocol {
    /// Holds awdl0 and llw0 down (true) or lets them come back up (false). Replies whether the
    /// helper is holding.
    func setWiFiHeld(_ held:Bool, withReply reply:@escaping (Bool)->Void)
    /// Runs every fan at this share of the way from its minimum to its maximum speed (0...100),
    /// or hands the fans back to macOS (below 0). Replies whether the fans run at that speed.
    func setFanPercent(_ percent:Double, withReply reply:@escaping (Bool)->Void)
}

enum RecallHelperNames {
    /// The helper's launchd label and Mach service; its plist is Contents/Library/LaunchDaemons/<label>.plist.
    static let label="org.overwatch2mac.launcher.helper"
    /// The helper's code signing identifier, which Recall checks before talking to it.
    static let helperIdentifier=label
    /// Recall's bundle identifier, which the helper checks before taking a connection.
    static let appIdentifier="org.overwatch2mac.launcher"
}
