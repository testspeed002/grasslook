import AppKit
import SwiftUI
import XCTest
@testable import Grasslook

final class GrasslookTests: XCTestCase {
    func testAppInitialization() {
        XCTAssertTrue(true, "Grasslook test suite initialized successfully.")
    }

    @MainActor
    func testOverlayPanelCanBecomeKeyAndMain() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let controller = OverlayWindowController()
        let panel = controller.createOverlayPanel(for: screen, rootView: AnyView(EmptyView()))
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertTrue(panel.canBecomeMain)
    }

    @MainActor
    func testSettingsWindowUsesNativePreferenceToolbarAndNoVisualEffectBlur() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GrasslookSettingsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tempURL = tempDir.appendingPathComponent("config.json")
        let coordinator = GrasslookCoordinator(configStore: GrasslookConfigStore(fileURL: tempURL))
        let controller = SettingsWindowController()
        let window = controller.makeSettingsWindow(coordinator: coordinator, initialTab: .breaks)

        XCTAssertEqual(window.toolbarStyle, .preference)
        XCTAssertEqual(window.toolbar?.displayMode, .iconAndLabel)
        XCTAssertEqual(window.toolbar?.items.count, SettingsTab.allCases.count)
        XCTAssertEqual(window.title, "Break Timers")
        XCTAssertEqual(window.toolbar?.selectedItemIdentifier, SettingsTab.breaks.toolbarItemIdentifier)

        let contentView = try XCTUnwrap(window.contentView)
        XCTAssertFalse(containsVisualEffectView(in: contentView))
    }

    @MainActor
    func testSettingsWindowTabSwitchUpdatesTitleSelectionAndPinsTopEdge() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GrasslookSettingsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tempURL = tempDir.appendingPathComponent("config.json")
        let coordinator = GrasslookCoordinator(configStore: GrasslookConfigStore(fileURL: tempURL))
        let controller = SettingsWindowController()
        let window = controller.makeSettingsWindow(coordinator: coordinator, initialTab: .breaks)
        let oldFrame = window.frame

        controller.selectTab(.sensory, animated: false)
        let newFrame = window.frame

        XCTAssertEqual(window.title, "Sound")
        XCTAssertEqual(window.toolbar?.selectedItemIdentifier, SettingsTab.sensory.toolbarItemIdentifier)
        XCTAssertLessThanOrEqual(abs(newFrame.maxY - oldFrame.maxY), 1.0)
        XCTAssertLessThan(newFrame.height, oldFrame.height)
    }

    @MainActor
    private func containsVisualEffectView(in view: NSView) -> Bool {
        if view is NSVisualEffectView {
            return true
        }
        return view.subviews.contains { containsVisualEffectView(in: $0) }
    }
}
