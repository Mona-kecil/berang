import AppKit
import Sparkle

/// Keeps Berang up to date through Sparkle: it checks the release feed once a day, and Check for Updates checks
/// now. An update installs only once you choose to, and only if both its EdDSA signature and its code signature
/// match this build's (Model/Update.tla). A daily check that finds one doesn't open a window over your work: the
/// menu bar icon gets a badge, and the menu offers the update.
@MainActor final class Updater: NSObject, SPUStandardUserDriverDelegate {
    private var controller: SPUStandardUpdaterController!
    /// The version a daily check found, until you look at it.
    private(set) var waiting: String?
    /// Called when `waiting` changes.
    var changed: () -> Void = {}

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
    }

    func check() {
        NSApp.activate()
        controller.checkForUpdates(nil)
    }

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Sparkle shows an update a daily check found only if Berang is in front; otherwise the badge waits for you.
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool { immediateFocus }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        guard !state.userInitiated else { return }
        let version = update.displayVersionString
        MainActor.assumeIsolated { show(version) }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated { show(nil) }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { show(nil) }
    }

    private func show(_ version: String?) {
        waiting = version
        changed()
    }
}
