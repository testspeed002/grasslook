import AppKit
import Foundation
import UniformTypeIdentifiers

/// Represents an installed macOS application metadata for easy friction target selection.
public struct InstalledAppInfo: Identifiable, Sendable, Hashable {
    public var id: String { bundleIdentifier }
    public let name: String
    public let bundleIdentifier: String
    public let url: URL

    public init(name: String, bundleIdentifier: String, url: URL) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.url = url
    }
}

/// Discovers installed applications across system and user application directories.
@MainActor
public final class InstalledAppsProvider: ObservableObject {
    @Published public private(set) var installedApps: [InstalledAppInfo] = []
    @Published public private(set) var isLoading: Bool = false

    public init() {
        Task {
            await loadInstalledApps()
        }
    }

    public func loadInstalledApps() async {
        isLoading = true
        let apps = await Task.detached(priority: .userInitiated) { () -> [InstalledAppInfo] in
            var results: [InstalledAppInfo] = []
            let fileManager = FileManager.default
            let searchPaths: [URL] = [
                URL(fileURLWithPath: "/Applications"),
                URL(fileURLWithPath: "/System/Applications"),
                fileManager.urls(for: .applicationDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: "/Users/\(NSUserName())/Applications")
            ]

            var seenBundleIds = Set<String>()

            for searchURL in searchPaths {
                guard let fileURLs = try? fileManager.contentsOfDirectory(
                    at: searchURL,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                ) else { continue }

                for appURL in fileURLs {
                    guard appURL.pathExtension == "app" else { continue }
                    guard let bundle = Bundle(url: appURL),
                          let bundleId = bundle.bundleIdentifier,
                          !bundleId.isEmpty else { continue }

                    if seenBundleIds.contains(bundleId) { continue }
                    seenBundleIds.insert(bundleId)

                    let name = bundle.infoDictionary?["CFBundleDisplayName"] as? String
                        ?? bundle.infoDictionary?["CFBundleName"] as? String
                        ?? appURL.deletingPathExtension().lastPathComponent

                    results.append(InstalledAppInfo(name: name, bundleIdentifier: bundleId, url: appURL))
                }
            }

            return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }.value

        self.installedApps = apps
        self.isLoading = false
    }

    /// Presents a native NSOpenPanel for the user to browse and click any application file.
    public static func pickAppViaPanel() -> InstalledAppInfo? {
        let openPanel = NSOpenPanel()
        openPanel.directoryURL = URL(fileURLWithPath: "/Applications")
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        openPanel.allowedContentTypes = [.applicationBundle]
        openPanel.prompt = "Select Application"
        openPanel.message = "Choose an application to add to Grasslook target rules"

        if openPanel.runModal() == .OK, let selectedURL = openPanel.url {
            if let bundle = Bundle(url: selectedURL), let bundleId = bundle.bundleIdentifier {
                let name = bundle.infoDictionary?["CFBundleDisplayName"] as? String
                    ?? bundle.infoDictionary?["CFBundleName"] as? String
                    ?? selectedURL.deletingPathExtension().lastPathComponent
                return InstalledAppInfo(name: name, bundleIdentifier: bundleId, url: selectedURL)
            }
        }
        return nil
    }
}
