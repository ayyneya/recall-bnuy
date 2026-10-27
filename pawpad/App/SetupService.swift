import Foundation

/// What this build of Pawpad installs: the engine archive bundled in the app, and Aniimo's
/// official launcher installer, both pinned by SHA-256 (Resources/release.json).
struct Release: Decodable {
    let appVersion: String
    let runtimeVersion: String
    let runtimeArchive: String
    let runtimeSHA256: String
    let installerURL: String
    let installerSHA256: String
}
struct SetupFailure: Error {
    let code: String
    var message: String {
        switch code {
        case "cancelled": return L("Setup is paused. Continue when you’re ready; finished steps are kept.")
        case "apple_silicon_required": return L("Pawpad needs a Mac with Apple Silicon (M1 or later).")
        case "macos_26_5_required": return L("Pawpad needs macOS 26.5 or later. Update macOS, then try again.")
        case "rosetta_required": return L("Rosetta is needed to run the game. Choose Install Rosetta and follow Apple’s steps.")
        case "install_location_unavailable": return L("The drive with your installation isn’t connected. Connect it, then try again.")
        case "unsupported_volume_format", "case_sensitive_volume", "read_only_volume": return L("This drive can’t hold Windows games. Use an APFS drive that isn’t case-sensitive.")
        case "insufficient_disk_space": return L("There isn’t enough free storage for this step. Free a few GB, then try again.")
        case "close_game_before_maintenance", "close_game_before_setup", "environment_initialization_busy": return L("Close Aniimo and its launcher, then try again.")
        case "setup_already_running", "app_worker_busy": return L("Another step is finishing. Wait a moment, then try again.")
        case "download_interrupted_retry_to_resume": return L("The download was interrupted. Check your connection and try again to resume.")
        case "download_hash_mismatch", "client_installer_hash_mismatch", "cached_download_hash_mismatch":
            return L("Aniimo’s launcher download differs from the one this version of Pawpad expects. The publisher may have updated it: check for a newer Pawpad.")
        case "archive_hash_mismatch", "runtime_file_hash_mismatch", "runtime_missing", "release_unavailable": return L("A part of Pawpad is missing or damaged. Download Pawpad again.")
        case "launcher_not_installed": return L("Aniimo’s launcher isn’t installed yet. Finish its installer first.")
        case "directory_not_owned_by_app", "invalid_ownership_marker", "existing_environment_not_owned": return L("The data folder holds files Pawpad didn’t create. Nothing was changed.")
        case "session_check_failed", "session_membership_unknown": return L("Pawpad couldn’t check what’s running. Quit Aniimo normally, then try again.")
        case "close_game_before_uninstall": return L("Aniimo is running. Quit the game, then try again. Nothing was removed.")
        case "client_close_failed": return L("The Aniimo launcher couldn’t be closed. Quit it, then try again.")
        case "no_recorded_session": return L("There’s no recording to add a marker to. Turn on Record performance, then press Play.")
        case "uninstall_move_failed": return L("The Pawpad folder couldn’t be moved to the Trash. Nothing was deleted.")
        default: return L("This step couldn’t finish ({0}). Try again; your game data is kept.",code)
        }
    }
}

/// One worker command at a time; its output is bounded JSON events, read off the main thread.
/// Recall's SetupService, unchanged in what it does.
@MainActor
final class SetupService {
    var root: URL
    let helper: URL
    private var process: Process?
    private var cancelRequested=false
    init(root: URL, helper: URL) { self.root=root; self.helper=helper }
    var running: Bool { process != nil }
    func cancel() { cancelRequested=true; if process?.isRunning == true { process?.terminate() } }
    func run(_ command: String, _ args: [String] = [], event: @escaping @MainActor ([String:Any])->Void = { _ in }) async throws -> [[String:Any]] {
        guard process == nil else { throw SetupFailure(code:"app_worker_busy") }
        let p=Process(), pipe=Pipe()
        p.executableURL=helper; p.arguments=[command,"--root",root.path]+args
        p.standardOutput=pipe; p.standardError=FileHandle.nullDevice
        p.environment=["PATH":"/usr/bin:/bin:/usr/sbin:/sbin","HOME":NSHomeDirectory()]
        process=p;cancelRequested=false
        defer { process=nil }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos:.userInitiated).async {
                do { try p.run() }
                catch { continuation.resume(throwing:SetupFailure(code:"process_launch_failed"));return }
                Task { @MainActor in if self.cancelRequested && self.process === p { self.cancel() } }
                var pending=Data(), events=[[String:Any]](), oversized=false
                while true {
                    let data=pipe.fileHandleForReading.availableData
                    if data.isEmpty { break }
                    pending.append(data)
                    if pending.count > 65536 { oversized=true; p.terminate(); break }
                    while let end=pending.firstIndex(of:10) {
                        let line=pending[..<end]; pending.removeSubrange(...end)
                        if let value=(try? JSONSerialization.jsonObject(with:Data(line))) as? [String:Any] {
                            events.append(value)
                            if events.count>256 { events.removeFirst() }
                            Task { @MainActor in event(value) }
                        }
                    }
                }
                p.waitUntilExit()
                try? pipe.fileHandleForReading.close()
                if let error=events.last(where:{$0["stage"] as? String == "error"})?["code"] as? String {
                    continuation.resume(throwing:SetupFailure(code:error))
                } else if p.terminationStatus != 0 || oversized {
                    continuation.resume(throwing:SetupFailure(code:p.terminationReason == .uncaughtSignal ? "cancelled":"process_failed"))
                } else { continuation.resume(returning:events) }
            }
        }
    }
}
