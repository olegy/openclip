// StatusBarController.swift
// OpenClip
//
// Manages the menu bar status item, its menu (Settings, Quit), and preferences window presentation for OpenClip.
// Formatted according to native macOS status menu conventions with consistent text alignment,
// clean sectional dividers, and standard keyboard shortcuts.
import AppKit
import SwiftUI
import Combine
import Core

/// Manages the menu bar status icon for OpenClip.
@MainActor
class StatusBarController: NSObject {
    private let settingsStore: any SettingsStore
    private let notificationCenter: NotificationCenter
    private var statusItem: NSStatusItem?
    private var preferencesWindow: NSWindow?
    private var preferencesToolbarController: PreferencesToolbarController?
    internal var rootMenu: NSMenu?
    internal var settingsMenuItem: NSMenuItem?
    private var cancellables = Set<AnyCancellable>()

    var isMenuBarIconVisible: Bool { statusItem != nil }

    /// Initializes a new status bar controller.
    init(
        settingsStore: any SettingsStore = DefaultSettingsStore.shared,
        notificationCenter: NotificationCenter = .default
    ) {
        self.settingsStore = settingsStore
        self.notificationCenter = notificationCenter
        super.init()

        notificationCenter.addObserver(
            self,
            selector: #selector(handleMenuBarVisibilityChanged(_:)),
            name: .openClipMenuBarVisibilityChanged,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(handleOpenConfiguration(_:)),
            name: .openClipOpenActionConfiguration,
            object: nil
        )

        setMenuBarIconVisible(settingsStore.get(.showMenuBarIcon))

        AppUpdateManager.shared.$hasUpdateReminder
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusIcon()
            }
            .store(in: &cancellables)
    }

    deinit {
        notificationCenter.removeObserver(self)
    }
    
    /// Sets up the menu for the status bar item following standard macOS menu hierarchy.
    private func setupMenu() {
        let menu = NSMenu()
        self.rootMenu = menu

        // Section 1: Navigation
        let prefsItem = menuItem(title: String(localized: "Settings…"), action: #selector(showPreferences as () -> Void), keyEquivalent: ",")
        self.settingsMenuItem = prefsItem
        menu.addItem(prefsItem)
        menu.addItem(NSMenuItem.separator())

        // Section 2: Lifecycle
        let quitItem = NSMenuItem(title: String(localized: "Quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
        updateStatusIcon()
    }

    private func menuSymbolImage(_ name: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        img?.size = NSSize(width: 14, height: 14)
        img?.isTemplate = true
        return img
    }

    /// Builds a menu item targeted at self (status-item menus don't resolve actions through the responder chain).
    private func menuItem(title: String, action: Selector, keyEquivalent: String = "", iconName: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        if let iconName {
            item.image = menuSymbolImage(iconName)
        }
        return item
    }

    @objc private func handleMenuBarVisibilityChanged(_ notification: Notification) {
        let isVisible = (notification.object as? Bool) ?? settingsStore.get(.showMenuBarIcon)
        setMenuBarIconVisible(isVisible)
    }

    /// Decision 8 config-open path: an action requested its configuration. The popup has already
    /// hidden; open Preferences and hand the request to the coordinator so PreferencesView can
    /// present the matching ActionEditorPage (the window may not have existed yet).
    @objc private func handleOpenConfiguration(_ notification: Notification) {
        showPreferences()
    }
    
    private func updateStatusIcon() {
        if let button = statusItem?.button {
            button.image = NSImage(named: "MenuBarIcon") ?? NSImage(systemSymbolName: "paperclip", accessibilityDescription: "OpenClip")
            button.image?.isTemplate = true
            let hasReminder = AppUpdateManager.shared.hasUpdateReminder
            button.title = hasReminder ? "•" : ""
            button.font = .systemFont(ofSize: 9, weight: .bold)
            button.imagePosition = .imageLeft
            button.toolTip = hasReminder ? String(localized: "OpenClip Update Available") : "OpenClip"
            button.setAccessibilityLabel(hasReminder ? String(localized: "OpenClip Update Available") : "OpenClip")
        }
    }

    private func setMenuBarIconVisible(_ isVisible: Bool) {
        if isVisible {
            guard statusItem == nil else { return }
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            setupMenu()
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
            rootMenu = nil
        }
    }
    
    /// Opens Settings on whatever pane (and drill-down) was last shown. The menu item and the
    /// Dock reopen use this: a reused window already holds the router's last path, and resetting
    /// to General here is what used to throw the user back to the top on every reopen.
    @objc public func showPreferences() {
        presentPreferences(tab: nil)
    }

    private func presentPreferences(tab: PreferenceTab?) {
        SettingsWindowController.show(tab: tab)
    }
}
