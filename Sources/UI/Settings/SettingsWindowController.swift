// Native AppKit preferences window controller using NSToolbar (.preference) and dynamic pane sizing.

import AppKit
import SwiftUI

/// Reference-counted AppKit activation policy helper for menu-bar-only apps.
@MainActor
public enum AppActivationPolicy {
    private static var count = 0

    /// Switches the app to regular activation policy while a settings window is open.
    public static func enter() {
        count += 1
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Restores accessory activation policy when all settings windows have closed.
    public static func leave() {
        count = max(0, count - 1)
        guard count == 0 else { return }
        Task { @MainActor in
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

/// Standalone macOS Preferences window controller modeled on native Safari Settings.
@MainActor
public final class SettingsWindowController: NSObject, NSWindowDelegate, NSToolbarDelegate {
    /// Fixed content width across all settings panes.
    public static let paneWidth: CGFloat = 640

    /// Shared singleton settings window controller.
    public static let shared = SettingsWindowController()

    private static let toolbarIdentifier = NSToolbar.Identifier("GrasslookSettingsToolbar")

    private var window: NSWindow?
    private var hostingController: NSHostingController<SettingsPaneView>?
    private weak var coordinator: GrasslookCoordinator?
    private var selectedTab: SettingsTab = .breaks

    public override init() {
        super.init()
    }

    /// Presents the native preferences window for the given coordinator and optional initial tab.
    public func show(coordinator: GrasslookCoordinator, initialTab: SettingsTab = .breaks) {
        if let existing = window, self.coordinator === coordinator {
            if selectedTab != initialTab {
                selectTab(initialTab, animated: false)
            }
            AppActivationPolicy.enter()
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let settingsWindow = makeSettingsWindow(coordinator: coordinator, initialTab: initialTab)
        AppActivationPolicy.enter()
        settingsWindow.makeKeyAndOrderFront(nil)
    }

    /// Builds and configures the preference-style NSWindow for live display or unit tests.
    internal func makeSettingsWindow(
        coordinator: GrasslookCoordinator,
        initialTab: SettingsTab = .breaks
    ) -> NSWindow {
        self.coordinator = coordinator
        self.selectedTab = initialTab

        let pane = makePaneView(tab: initialTab, coordinator: coordinator)
        let controller = NSHostingController(rootView: pane)
        self.hostingController = controller

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.paneWidth, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        newWindow.toolbarStyle = .preference
        newWindow.titleVisibility = .visible
        newWindow.titlebarAppearsTransparent = false
        newWindow.backgroundColor = .windowBackgroundColor
        newWindow.isReleasedWhenClosed = false
        newWindow.title = initialTab.title
        newWindow.delegate = self

        let toolbar = NSToolbar(identifier: Self.toolbarIdentifier)
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.selectedItemIdentifier = initialTab.toolbarItemIdentifier
        newWindow.toolbar = toolbar

        newWindow.contentViewController = controller
        self.window = newWindow

        resizeWindowToFitContent(in: newWindow, animated: false)
        newWindow.center()
        return newWindow
    }

    /// Switches the active preferences pane and resizes the window while keeping its top edge pinned.
    internal func selectTab(_ tab: SettingsTab, animated: Bool) {
        guard let window, let coordinator else { return }
        selectedTab = tab
        window.toolbar?.selectedItemIdentifier = tab.toolbarItemIdentifier
        window.title = tab.title
        hostingController?.rootView = makePaneView(tab: tab, coordinator: coordinator)
        resizeWindowToFitContent(in: window, animated: animated)
    }

    public func windowWillClose(_ notification: Notification) {
        AppActivationPolicy.leave()
    }

    // MARK: - NSToolbarDelegate

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map(\.toolbarItemIdentifier)
    }

    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map(\.toolbarItemIdentifier)
    }

    public func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map(\.toolbarItemIdentifier)
    }

    public func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let tab = SettingsTab(toolbarItemIdentifier: itemIdentifier) else {
            return nil
        }

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = tab.rawValue
        item.paletteLabel = tab.rawValue
        item.toolTip = tab.title
        item.image = NSImage(systemSymbolName: tab.systemImage, accessibilityDescription: tab.title)
        item.target = self
        item.action = #selector(selectToolbarTab(_:))
        item.isEnabled = true
        return item
    }

    @objc private func selectToolbarTab(_ sender: NSToolbarItem) {
        guard let tab = SettingsTab(toolbarItemIdentifier: sender.itemIdentifier) else {
            return
        }
        let shouldAnimate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        selectTab(tab, animated: shouldAnimate)
    }

    // MARK: - Layout Sizing

    private func makePaneView(tab: SettingsTab, coordinator: GrasslookCoordinator) -> SettingsPaneView {
        SettingsPaneView(tab: tab, coordinator: coordinator) { [weak self] in
            guard let self, let window = self.window else { return }
            let shouldAnimate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            self.resizeWindowToFitContent(in: window, animated: shouldAnimate)
        }
    }

    private func resizeWindowToFitContent(in window: NSWindow, animated: Bool) {
        guard let contentView = hostingController?.view else { return }
        contentView.layoutSubtreeIfNeeded()
        let fittingSize = contentView.fittingSize
        let maxVisibleHeight = (window.screen?.visibleFrame.height ?? 800) - 120
        let contentHeight = max(160, min(ceil(fittingSize.height), maxVisibleHeight))

        let currentFrame = window.frame
        var nextFrame = window.frameRect(
            forContentRect: NSRect(x: 0, y: 0, width: Self.paneWidth, height: contentHeight)
        )
        nextFrame.origin = NSPoint(
            x: currentFrame.origin.x,
            y: currentFrame.maxY - nextFrame.height
        )

        guard abs(currentFrame.width - nextFrame.width) > 0.5 || abs(currentFrame.height - nextFrame.height) > 0.5 else {
            return
        }
        window.setFrame(nextFrame, display: true, animate: animated)
    }
}
