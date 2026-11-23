// Multi-display full-screen overlay window controller for breaks and friction.

import AppKit
import SwiftUI

/// Manages full-screen overlay panels across all connected displays.
@MainActor
public final class OverlayWindowController: ObservableObject {
    private var overlayPanels: [NSPanel] = []
    private var currentRootView: AnyView?
    private nonisolated(unsafe) var screenParametersObserver: (any NSObjectProtocol)?

    /// Indicates whether an overlay is currently displayed on at least one screen.
    public private(set) var isShowingOverlay: Bool = false

    /// Creates an overlay window controller that tracks display configuration changes.
    public init() {
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.repositionPanels()
            }
        }
    }

    deinit {
        if let observer = screenParametersObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Shows a break overlay on all connected screens.
    public func presentBreakOverlay(
        type: BreakType,
        duration: TimeInterval,
        secondsRemaining: TimeInterval,
        strictMode: Bool = false,
        isDuskCueActive: Bool = false,
        onSkip: @escaping () -> Void,
        onPostpone: @escaping () -> Void,
        onComplete: @escaping () -> Void
    ) {
        let view = BreakOverlayView(
            type: type,
            duration: duration,
            secondsRemaining: secondsRemaining,
            strictMode: strictMode,
            isDuskCueActive: isDuskCueActive,
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

    /// Shows a breathing delay overlay on all connected screens.
    public func presentFrictionOverlay(
        appName: String,
        domainName: String?,
        duration: TimeInterval,
        cooldownDuration: TimeInterval = 900.0,
        focusPhase: FocusPhase = .daytime,
        isStrictCurfew: Bool = false,
        isDuskCueActive: Bool = false,
        canUseBreakGlass: Bool = false,
        breakGlassWaitSeconds: TimeInterval = 30.0,
        breakGlassMinNoteLength: Int = 4,
        onProceed: @escaping () -> Void,
        onBreakGlass: ((String) -> Void)? = nil,
        onCloseApp: @escaping () -> Void
    ) {
        let wrappedBreakGlass: ((String) -> Void)? = onBreakGlass.map { handler in
            { [weak self] note in
                self?.dismissOverlays()
                handler(note)
            }
        }

        let view = BreathingBubbleView(
            appName: appName,
            domainName: domainName,
            duration: duration,
            cooldownDuration: cooldownDuration,
            focusPhase: focusPhase,
            isStrictCurfew: isStrictCurfew,
            isDuskCueActive: isDuskCueActive,
            canUseBreakGlass: canUseBreakGlass,
            breakGlassWaitSeconds: breakGlassWaitSeconds,
            breakGlassMinNoteLength: breakGlassMinNoteLength,
            onProceed: { [weak self] in
                self?.dismissOverlays()
                onProceed()
            },
            onBreakGlass: wrappedBreakGlass,
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
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            return
        }

        currentRootView = rootView
        for screen in screens {
            let panel = createOverlayPanel(for: screen, rootView: rootView)
            panel.makeKeyAndOrderFront(nil)
            overlayPanels.append(panel)
        }
        isShowingOverlay = true
    }

    func createOverlayPanel(for screen: NSScreen, rootView: AnyView) -> NSPanel {
        let panel = KeyableOverlayPanel(
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
        // Use local zero-origin bounds so secondary display coordinates do not shift content off-screen.
        hostingView.frame = NSRect(origin: .zero, size: screen.frame.size)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        return panel
    }

    private func repositionPanels() {
        guard isShowingOverlay, let rootView = currentRootView else { return }
        displayViewOnAllScreens(rootView: rootView)
    }
}

private final class KeyableOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
