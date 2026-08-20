import AppKit
import SwiftUI

/// Coordinates full-screen non-activating Liquid Glass overlay panels across all connected displays.
@MainActor
public final class OverlayWindowController: ObservableObject {
    private var overlayPanels: [NSPanel] = []
    private var currentRootView: AnyView?
    public private(set) var isShowingOverlay: Bool = false

    public init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.repositionPanels()
            }
        }
    }

    /// Presents a proactive eye rest or movement break overlay across all screens.
    public func presentBreakOverlay(
        type: BreakType,
        duration: TimeInterval,
        secondsRemaining: TimeInterval,
        onSkip: @escaping () -> Void,
        onPostpone: @escaping () -> Void,
        onComplete: @escaping () -> Void
    ) {
        let view = BreakOverlayView(
            type: type,
            duration: duration,
            secondsRemaining: secondsRemaining,
            onSkip: { [weak self] in
                self?.dismissOverlays()
                onSkip()
            },
            onPostpone: { [weak self] in
                self?.dismissOverlays()
                onPostpone()
            },
            onComplete: { [weak self] in
                self?.dismissOverlays()
                onComplete()
            }
        )

        displayViewOnAllScreens(rootView: AnyView(view))
    }

    /// Presents a reactive mindful friction delay overlay across all screens.
    public func presentFrictionOverlay(
        appName: String,
        domainName: String?,
        duration: TimeInterval,
        onProceed: @escaping () -> Void,
        onCloseApp: @escaping () -> Void
    ) {
        let view = BreathingBubbleView(
            appName: appName,
            domainName: domainName,
            duration: duration,
            onProceed: { [weak self] in
                self?.dismissOverlays()
                onProceed()
            },
            onCloseApp: { [weak self] in
                self?.dismissOverlays()
                onCloseApp()
            }
        )

        displayViewOnAllScreens(rootView: AnyView(view))
    }

    /// Dismisses all active overlay panels.
    public func dismissOverlays() {
        for panel in overlayPanels {
            panel.orderOut(nil)
        }
        overlayPanels.removeAll()
        currentRootView = nil
        isShowingOverlay = false
    }

    // MARK: - Private Panel Creation

    private func displayViewOnAllScreens(rootView: AnyView) {
        dismissOverlays()
        currentRootView = rootView

        for screen in NSScreen.screens {
            let panel = createOverlayPanel(for: screen, rootView: rootView)
            panel.makeKeyAndOrderFront(nil)
            overlayPanels.append(panel)
        }
        isShowingOverlay = true
    }

    private func createOverlayPanel(for screen: NSScreen, rootView: AnyView) -> NSPanel {
        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )

        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = screen.frame
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        return panel
    }

    private func repositionPanels() {
        guard isShowingOverlay, let rootView = currentRootView else { return }
        // Recreate clean overlay panels across all currently connected screens
        displayViewOnAllScreens(rootView: rootView)
    }
}
