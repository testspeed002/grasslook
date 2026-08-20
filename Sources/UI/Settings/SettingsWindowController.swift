import AppKit
import SwiftUI

/// Reference-counted AppKit activation policy helper for menu-bar-only apps.
@MainActor
public enum AppActivationPolicy {
    private static var count = 0

    public static func enter() {
        count += 1
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    public static func leave() {
        count = max(0, count - 1)
        guard count == 0 else { return }
        Task { @MainActor in
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

/// Standalone Settings Window Controller adhering to native macOS 26 Liquid Glass guidelines.
@MainActor
public final class SettingsWindowController: NSObject, NSWindowDelegate {
    public static let shared = SettingsWindowController()
    private var window: NSWindow?

    private override init() {
        super.init()
    }

    public func show(coordinator: GrasslookCoordinator) {
        if let existing = window {
            AppActivationPolicy.enter()
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let settingsView = SettingsView(
            scheduler: coordinator.scheduler,
            interception: coordinator.interception,
            analytics: coordinator.analytics,
            audio: coordinator.audio
        )

        let hostingView = NSHostingView(rootView: settingsView)
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 530),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        newWindow.title = "Break Timers"
        newWindow.titlebarAppearsTransparent = false
        newWindow.titleVisibility = .visible
        newWindow.minSize = NSSize(width: 580, height: 530)
        newWindow.contentView = hostingView
        newWindow.delegate = self
        newWindow.center()
        newWindow.isReleasedWhenClosed = false

        self.window = newWindow
        AppActivationPolicy.enter()
        newWindow.makeKeyAndOrderFront(nil)
    }

    public func windowWillClose(_ notification: Notification) {
        AppActivationPolicy.leave()
    }
}
