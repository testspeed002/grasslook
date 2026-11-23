// Universal AppleScript dictionary (.sdef) inspector for browser URL dialects.

import Foundation
import os

/// Result of inspecting an application bundle for an AppleScript scripting definition.
public struct SdefInspectionResult: Sendable, Equatable {
    /// The detected AppleScript URL-inspection dialect.
    public let dialect: AppleScriptDialect
    /// The filename of the inspected `.sdef` resource, if one was found.
    public let sdefFilename: String?

    /// Creates an inspection result for a bundle's scripting definition.
    public init(dialect: AppleScriptDialect, sdefFilename: String? = nil) {
        self.dialect = dialect
        self.sdefFilename = sdefFilename
    }
}

/// Inspects macOS application bundles and `.sdef` XML data to classify AppleScript URL dialects.
public enum SdefScriptingInspector {
    private static let logger = Logger(subsystem: "com.grasslook.app", category: "SdefScriptingInspector")

    /// Inspects `Contents/Info.plist` and `Contents/Resources/*.sdef` in the given `.app` bundle.
    public static func inspect(bundleURL: URL) -> SdefInspectionResult {
        let contentsURL = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        let infoPlistURL = contentsURL.appendingPathComponent("Info.plist", isDirectory: false)

        if let declaredName = scriptingDefinitionFilename(fromInfoPlistAt: infoPlistURL) {
            let candidates = candidateSdefURLs(forDeclaredName: declaredName, in: resourcesURL)
            for candidateURL in candidates {
                if let data = try? Data(contentsOf: candidateURL) {
                    let dialect = parseDialect(from: data)
                    return SdefInspectionResult(
                        dialect: dialect,
                        sdefFilename: candidateURL.lastPathComponent
                    )
                }
            }
        }

        guard let resourceItems = try? FileManager.default.contentsOfDirectory(
            at: resourcesURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return SdefInspectionResult(dialect: .none, sdefFilename: nil)
        }

        let sdefURLs = resourceItems
            .filter { $0.pathExtension.lowercased() == "sdef" }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }

        var firstFilename: String?
        for sdefURL in sdefURLs {
            if firstFilename == nil {
                firstFilename = sdefURL.lastPathComponent
            }
            guard let data = try? Data(contentsOf: sdefURL) else {
                continue
            }
            let dialect = parseDialect(from: data)
            if dialect != .none {
                return SdefInspectionResult(
                    dialect: dialect,
                    sdefFilename: sdefURL.lastPathComponent
                )
            }
        }

        return SdefInspectionResult(dialect: .none, sdefFilename: firstFilename)
    }

    /// Parses raw `.sdef` XML data and classifies the supported AppleScript URL dialect.
    public static func parseDialect(from sdefData: Data) -> AppleScriptDialect {
        guard !sdefData.isEmpty else {
            return .none
        }

        let delegate = SdefXMLParserDelegate()
        let parser = XMLParser(data: sdefData)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false

        guard parser.parse() else {
            if let error = parser.parserError {
                logger.debug("Failed to parse sdef XML: \(error.localizedDescription, privacy: .public)")
            }
            return .none
        }

        return delegate.resolvedDialect
    }

    private static func scriptingDefinitionFilename(fromInfoPlistAt infoPlistURL: URL) -> String? {
        guard let data = try? Data(contentsOf: infoPlistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let rawName = plist["OSAScriptingDefinition"] as? String else {
            return nil
        }

        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func candidateSdefURLs(forDeclaredName name: String, in resourcesURL: URL) -> [URL] {
        let directURL = resourcesURL.appendingPathComponent(name, isDirectory: false)
        if name.lowercased().hasSuffix(".sdef") {
            return [directURL]
        }
        let withExtensionURL = resourcesURL.appendingPathComponent("\(name).sdef", isDirectory: false)
        return [directURL, withExtensionURL]
    }
}

private final class SdefXMLParserDelegate: NSObject, XMLParserDelegate {
    private var currentClassStack: [String] = []
    private var hasActiveTab = false
    private var hasCurrentTab = false
    private var hasDocumentURL = false

    var resolvedDialect: AppleScriptDialect {
        if hasActiveTab {
            return .chromiumActiveTab
        }
        if hasCurrentTab {
            return .safariCurrentTab
        }
        if hasDocumentURL {
            return .documentURL
        }
        return .none
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let element = elementName.lowercased()

        if element == "class" || element == "class-extension" {
            let className = (attributeDict["name"] ?? attributeDict["extends"] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            currentClassStack.append(className)
            return
        }

        guard element == "property" else {
            return
        }

        let propertyName = (attributeDict["name"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch propertyName {
        case "active tab":
            hasActiveTab = true
        case "current tab":
            hasCurrentTab = true
        case "url":
            if currentClassStack.last == "document" {
                hasDocumentURL = true
            }
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let element = elementName.lowercased()
        if (element == "class" || element == "class-extension") && !currentClassStack.isEmpty {
            currentClassStack.removeLast()
        }
    }
}
