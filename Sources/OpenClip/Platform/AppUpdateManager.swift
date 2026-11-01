// AppUpdateManager.swift
// OpenClip
//
// Wraps Sparkle's SPUStandardUpdaterController for the About page's "Check for Updates" link and
// the menu bar icon's update dot. Ed25519-verified updates come from the appcast at SUFeedURL
// (scripts/release.sh publishes it). Sparkle checks once a day (SUScheduledCheckInterval) and never
// downloads on its own: installing an update is always the user's click in Sparkle's window.
import Foundation
import AppKit
import Sparkle
import Combine
import Core

@MainActor
public final class AppUpdateManager: NSObject, ObservableObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    public static let shared = AppUpdateManager()

    public static let defaultFeedURL = "https://github.com/olegy/openclip/releases/latest/download/appcast.xml"

    /// Whether this build ships an update feed (`SUFeedURL`, Lite's own appcast). A build without one
    /// never creates Sparkle: no network check, no background schedule, and the update UI is hidden.
    public static var isEnabled: Bool {
        guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String else { return false }
        return !feed.isEmpty
    }

    private var controller: SPUStandardUpdaterController?
    public let updatesEnabled: Bool
    public var canPresentUpdate: Bool {
        updatesEnabled && (canCheckForUpdates || controller?.updater.sessionInProgress == true)
    }

    /// A scheduled check found an update the user has not looked at yet; the menu bar icon shows a
    /// dot until they do (Sparkle's gentle reminders for a menu bar app).
    @Published public private(set) var hasUpdateReminder = false

    /// KVO-backed published state so SwiftUI views can bind directly.
    @Published public private(set) var canCheckForUpdates = false

    private var isInteractiveUpdatePresented = false
    private var cancellables = Set<AnyCancellable>()

    init(bundleIdentifier: String? = Bundle.main.bundleIdentifier,
         hasUpdateFeed: Bool = AppUpdateManager.isEnabled) {
        // A build without a feed never updates, whatever its bundle identifier.
        self.updatesEnabled = hasUpdateFeed && Self.supportsUpdates(bundleIdentifier: bundleIdentifier)
        super.init()

        guard updatesEnabled else {
            Log.updates.info("Updates disabled: no SUFeedURL in this build or a development build")
            return
        }
        let controller = SPUStandardUpdaterController(
            startingUpdater: NSClassFromString("XCTestCase") == nil,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        self.controller = controller
        controller.updater.automaticallyChecksForUpdates = true
        controller.updater.automaticallyDownloadsUpdates = false

        // Mirror Sparkle's KVO-observable `canCheckForUpdates` into our @Published property.
        controller.updater
            .publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
            }
            .store(in: &cancellables)
    }

    /// Only the Release bundle updates itself; the Debug build (`com.olegy.openclip.dev`) never does.
    static func supportsUpdates(bundleIdentifier: String?) -> Bool {
        bundleIdentifier == "com.olegy.openclip"
    }

    // MARK: - SPUStandardUserDriverDelegate

    public var supportsGentleScheduledUpdateReminders: Bool { true }

    public func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        handleUpdatePresentation(showsWindow: handleShowingUpdate, userInitiated: state.userInitiated)
    }

    func handleUpdatePresentation(showsWindow: Bool, userInitiated: Bool) {
        if showsWindow { beginInteractiveUpdatePresentation() }
        hasUpdateReminder = !userInitiated
    }

    public func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        hasUpdateReminder = false
    }

    public func standardUserDriverWillFinishUpdateSession() {
        hasUpdateReminder = false
        finishInteractiveUpdatePresentation()
    }

    // MARK: - SPUUpdaterDelegate

    public func feedURLString(for updater: SPUUpdater) -> String? {
        currentFeedURL
    }

    /// The feed URL for OpenClip Lite releases.
    public var currentFeedURL: String {
        Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? Self.defaultFeedURL
    }

    /// Triggers an interactive update check (shows Sparkle's native update window or dialog).
    public func checkForUpdates() {
        guard canPresentUpdate, let controller else { return }
        beginInteractiveUpdatePresentation()
        controller.checkForUpdates(nil)
    }

    /// Share the Settings window's activation lease so overlapping windows keep the app regular.
    func beginInteractiveUpdatePresentation() {
        guard !isInteractiveUpdatePresented else { return }
        isInteractiveUpdatePresented = true
        AppActivationPolicy.enter()
    }

    func finishInteractiveUpdatePresentation() {
        guard isInteractiveUpdatePresented else { return }
        isInteractiveUpdatePresented = false
        AppActivationPolicy.leave()
    }

    public func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        // Sparkle calls this after the driver finishes, including cancellation, no update, and errors.
        finishInteractiveUpdatePresentation()
    }

    public func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString ?? item.versionString
        Log.updates.info("Sparkle found valid update: v\(version, privacy: .public)")
    }

    public func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Log.updates.info("Sparkle: no update found or up to date")
        hasUpdateReminder = false
    }

    public func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        hasUpdateReminder = false
    }

    public func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        let nsError = error as NSError
        // Sparkle uses error code 1001 (SUNoUpdateError) when no update is found and 4001 (SUInstallationCanceledError)
        // when an update check is canceled. These are expected control flow, not system failures.
        if nsError.code == 1001 || nsError.code == 4001 {
            if nsError.code == 1001 {
                Log.updates.info("Sparkle update check completed: app is up to date")
            } else {
                Log.updates.info("Sparkle update check canceled by user")
            }
            return
        }
        Log.updates.error("Sparkle update error (\(nsError.code)): \(error.localizedDescription, privacy: .public)")
    }

    // MARK: - Testing Hooks

    func setUpdateReminderForTesting(_ reminder: Bool) {
        hasUpdateReminder = reminder
    }
}
