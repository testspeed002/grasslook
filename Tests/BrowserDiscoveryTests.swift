// Unit tests for SdefScriptingInspector and BrowserDiscovery across all seven browser engines.

import XCTest
@testable import Grasslook

final class BrowserDiscoveryTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GrasslookBrowserDiscoveryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try super.tearDownWithError()
    }

    // MARK: - SdefScriptingInspector

    func testParseDialectRecognizesChromiumActiveTab() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE dictionary SYSTEM "file://localhost/System/Library/DTDs/sdef.dtd">
        <dictionary title="Yab Terminology">
            <suite name="Yab Suite" code="YabS">
                <class name="window" code="cwin">
                    <property name="active tab" code="acTa" type="tab" access="r"/>
                </class>
                <class name="tab" code="CrTb">
                    <property name="URL" code="URL " type="text" access="rw"/>
                </class>
            </suite>
        </dictionary>
        """
        let data = try XCTUnwrap(sdef.data(using: .utf8))
        XCTAssertEqual(SdefScriptingInspector.parseDialect(from: data), .chromiumActiveTab)
    }

    func testParseDialectRecognizesSafariCurrentTab() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary title="Safari Terminology">
            <suite name="Safari Suite" code="sfri">
                <class name="window" code="cwin">
                    <property name="current tab" code="cTab" type="tab" access="rw"/>
                </class>
                <class name="tab" code="bTab">
                    <property name="URL" code="pURL" type="text" access="rw"/>
                </class>
                <class name="document" code="docu">
                    <property name="URL" code="pURL" type="text" access="r"/>
                </class>
            </suite>
        </dictionary>
        """
        let data = try XCTUnwrap(sdef.data(using: .utf8))
        XCTAssertEqual(SdefScriptingInspector.parseDialect(from: data), .safariCurrentTab)
    }

    func testParseDialectRecognizesDocumentURL() throws {
        let sdef = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary title="Document Browser Terminology">
            <suite name="Standard Suite" code="core">
                <class name="document" code="docu">
                    <property name="URL" code="pURL" type="text" access="r"/>
                </class>
            </suite>
        </dictionary>
        """
        let data = try XCTUnwrap(sdef.data(using: .utf8))
        XCTAssertEqual(SdefScriptingInspector.parseDialect(from: data), .documentURL)
    }

    func testParseDialectReturnsNoneForStandardEmptyAndMalformedSdef() throws {
        let standardOnly = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary title="Minimal">
            <suite name="Standard Suite" code="core">
                <class name="window" code="cwin">
                    <property name="name" code="pnam" type="text" access="r"/>
                </class>
            </suite>
        </dictionary>
        """
        let standardData = try XCTUnwrap(standardOnly.data(using: .utf8))
        XCTAssertEqual(SdefScriptingInspector.parseDialect(from: standardData), .none)
        XCTAssertEqual(SdefScriptingInspector.parseDialect(from: Data()), .none)

        let malformedData = try XCTUnwrap("<dictionary><unclosed>".data(using: .utf8))
        XCTAssertEqual(SdefScriptingInspector.parseDialect(from: malformedData), .none)
    }

    func testInspectReadsOSAScriptingDefinitionAndFallsBackToResourcesScan() throws {
        let sdefXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary title="Yab Terminology">
            <suite name="Yab Suite" code="YabS">
                <class name="window" code="cwin">
                    <property name="active tab" code="acTa" type="tab" access="r"/>
                </class>
            </suite>
        </dictionary>
        """

        let declaredBundle = try makeSyntheticApp(
            folderName: "DeclaredYab.app",
            bundleIdentifier: "com.example.declaredyab",
            displayName: "DeclaredYab",
            osaScriptingDefinition: "Yab.sdef",
            sdefFiles: ["Yab.sdef": sdefXML]
        )
        let declaredResult = SdefScriptingInspector.inspect(bundleURL: declaredBundle)
        XCTAssertEqual(declaredResult.dialect, .chromiumActiveTab)
        XCTAssertEqual(declaredResult.sdefFilename, "Yab.sdef")

        let scannedBundle = try makeSyntheticApp(
            folderName: "ScannedBrowser.app",
            bundleIdentifier: "com.example.scanned",
            displayName: "ScannedBrowser",
            osaScriptingDefinition: nil,
            sdefFiles: ["Fallback.sdef": sdefXML]
        )
        let scannedResult = SdefScriptingInspector.inspect(bundleURL: scannedBundle)
        XCTAssertEqual(scannedResult.dialect, .chromiumActiveTab)
        XCTAssertEqual(scannedResult.sdefFilename, "Fallback.sdef")
    }

    // MARK: - Seven-Engine Classification

    func testInspectBundleClassifiesAllSevenEnginesAndUnknown() throws {
        let webkitApp = try makeSyntheticApp(
            folderName: "SynthWebKit.app",
            bundleIdentifier: "com.example.webkit",
            displayName: "SynthWebKit",
            frameworks: ["WebKit.framework"]
        )
        XCTAssertEqual(BrowserDiscovery().inspectBundle(at: webkitApp)?.engine, .webkit)

        let chromiumApp = try makeSyntheticApp(
            folderName: "SynthChromium.app",
            bundleIdentifier: "com.example.chromium",
            displayName: "SynthChromium",
            frameworks: ["Helium Framework.framework"]
        )
        XCTAssertEqual(BrowserDiscovery().inspectBundle(at: chromiumApp)?.engine, .chromium)

        let electronApp = try makeSyntheticApp(
            folderName: "SynthElectron.app",
            bundleIdentifier: "com.example.electron",
            displayName: "SynthElectron",
            frameworks: ["Electron Framework.framework"]
        )
        XCTAssertEqual(BrowserDiscovery().inspectBundle(at: electronApp)?.engine, .electron)

        let dualCEFWebKitApp = try makeSyntheticApp(
            folderName: "SynthDualCEF.app",
            bundleIdentifier: "com.example.dualcef",
            displayName: "SynthDualCEF",
            frameworks: ["Chromium Embedded Framework.framework"],
            macOSFiles: ["SynthDualCEF": Data("linked /System/Library/Frameworks/WebKit.framework".utf8)]
        )
        XCTAssertEqual(BrowserDiscovery().inspectBundle(at: dualCEFWebKitApp)?.engine, .dualCEFWebKit)

        let cefNativeApp = try makeSyntheticApp(
            folderName: "SynthCEFNative.app",
            bundleIdentifier: "com.example.cefnative",
            displayName: "SynthCEFNative",
            frameworks: ["Chromium Embedded Framework.framework"]
        )
        XCTAssertEqual(BrowserDiscovery().inspectBundle(at: cefNativeApp)?.engine, .cefNative)

        let geckoApp = try makeSyntheticApp(
            folderName: "SynthGecko.app",
            bundleIdentifier: "com.example.gecko",
            displayName: "SynthGecko",
            macOSFiles: ["XUL": Data()],
            resourceFiles: ["omni.ja": Data()]
        )
        XCTAssertEqual(BrowserDiscovery().inspectBundle(at: geckoApp)?.engine, .gecko)

        let ladybirdApp = try makeSyntheticApp(
            folderName: "SynthLadybird.app",
            bundleIdentifier: "com.example.ladybird",
            displayName: "SynthLadybird",
            frameworks: ["LibWeb.framework"],
            macOSFiles: ["Ladybird": Data()]
        )
        XCTAssertEqual(BrowserDiscovery().inspectBundle(at: ladybirdApp)?.engine, .ladybird)

        let unknownApp = try makeSyntheticApp(
            folderName: "SynthUnknown.app",
            bundleIdentifier: "com.example.unknown",
            displayName: "SynthUnknown"
        )
        XCTAssertEqual(BrowserDiscovery().inspectBundle(at: unknownApp)?.engine, .unknown)
    }

    // MARK: - Exclusion & Web Handler Gate

    func testExcludesVLCLikeMediaAppsAndDenylist() throws {
        let vlcApp = try makeSyntheticApp(
            folderName: "VLC.app",
            bundleIdentifier: "org.videolan.vlc",
            displayName: "VLC",
            urlSchemes: ["http", "https"],
            documentUTIs: ["public.html"]
        )
        let iinaApp = try makeSyntheticApp(
            folderName: "IINA.app",
            bundleIdentifier: "com.colliderli.iina",
            displayName: "IINA",
            urlSchemes: ["http", "https"],
            documentUTIs: []
        )
        let genericStreamPlayer = try makeSyntheticApp(
            folderName: "StreamPlayer.app",
            bundleIdentifier: "com.example.streamplayer",
            displayName: "StreamPlayer",
            urlSchemes: ["http", "https"],
            documentUTIs: []
        )
        let validBrowser = try makeSyntheticApp(
            folderName: "ValidBrowser.app",
            bundleIdentifier: "com.example.validbrowser",
            displayName: "ValidBrowser",
            urlSchemes: ["http", "https"],
            documentUTIs: ["public.html"]
        )

        let discovery = BrowserDiscovery(appURLsProvider: {
            [vlcApp, iinaApp, genericStreamPlayer, validBrowser]
        })

        let discovered = discovery.discoverInstalledBrowsers()
        XCTAssertEqual(discovered.map(\.bundleIdentifier), ["com.example.validbrowser"])
        XCTAssertFalse(discovery.isBrowser(bundleIdentifier: "org.videolan.vlc"))
        XCTAssertFalse(discovery.isBrowser(bundleIdentifier: "com.colliderli.iina"))
        XCTAssertFalse(discovery.isBrowser(bundleIdentifier: "com.example.streamplayer"))
        XCTAssertTrue(discovery.isBrowser(bundleIdentifier: "com.example.validbrowser"))
    }

    // MARK: - Custom Browsers & Caching

    func testCustomBrowserRegistrationAndDiscoveryCache() throws {
        let customApp = try makeSyntheticApp(
            folderName: "InternalBrowser.app",
            bundleIdentifier: "com.acme.InternalBrowser",
            displayName: "InternalBrowser",
            urlSchemes: [],
            documentUTIs: [],
            frameworks: ["WebKit.framework"]
        )

        final class CallCounter: @unchecked Sendable {
            private let lock = NSLock()
            private var value = 0

            func increment() {
                lock.lock()
                value += 1
                lock.unlock()
            }

            func current() -> Int {
                lock.lock()
                let result = value
                lock.unlock()
                return result
            }
        }

        let counter = CallCounter()
        let discovery = BrowserDiscovery(appURLsProvider: {
            counter.increment()
            return [customApp]
        })

        XCTAssertFalse(discovery.isBrowser(bundleIdentifier: "com.acme.InternalBrowser"))
        XCTAssertTrue(discovery.discoverInstalledBrowsers().isEmpty)

        discovery.registerCustomBrowser(bundleIdentifier: "com.acme.InternalBrowser")
        XCTAssertTrue(discovery.isBrowser(bundleIdentifier: "com.acme.InternalBrowser"))

        // Cached result remains empty until forceRefresh is requested.
        XCTAssertTrue(discovery.discoverInstalledBrowsers(forceRefresh: false).isEmpty)
        let refreshed = discovery.discoverInstalledBrowsers(forceRefresh: true)
        XCTAssertEqual(refreshed.count, 1)
        XCTAssertEqual(discovery.profile(for: "COM.ACME.INTERNALBROWSER")?.engine, .webkit)

        discovery.setCustomBrowsers([])
        XCTAssertFalse(discovery.isBrowser(bundleIdentifier: "com.other.browser"))

        XCTAssertEqual(counter.current(), 2)
    }

    // MARK: - Host Bundle Checks (Guarded for CI)

    func testHostInstalledBrowsersIfPresentOnDisk() {
        let discovery = BrowserDiscovery()
        let candidates: [(paths: [String], expectedEngine: BrowserEngine, expectedDialect: AppleScriptDialect?)] = [
            (
                ["/Applications/Safari.app", "/System/Cryptexes/App/Applications/Safari.app"],
                .webkit,
                .safariCurrentTab
            ),
            (
                ["/Applications/Google Chrome.app"],
                .chromium,
                .chromiumActiveTab
            ),
            (
                ["/Applications/Helium.app"],
                .chromium,
                nil
            ),
            (
                ["/Applications/Firefox.app"],
                .gecko,
                AppleScriptDialect.none
            ),
            (
                ["/Applications/yab.app"],
                .dualCEFWebKit,
                nil
            ),
        ]

        for candidate in candidates {
            guard let existingPath = candidate.paths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
                continue
            }
            let profile = discovery.inspectBundle(at: URL(fileURLWithPath: existingPath))
            XCTAssertNotNil(profile, "Expected valid profile for \(existingPath)")
            XCTAssertEqual(profile?.engine, candidate.expectedEngine, "Unexpected engine for \(existingPath)")
            if let expectedDialect = candidate.expectedDialect {
                XCTAssertEqual(profile?.scriptingDialect, expectedDialect, "Unexpected dialect for \(existingPath)")
            }
        }
    }

    // MARK: - Fixture Helpers

    private func makeSyntheticApp(
        folderName: String,
        bundleIdentifier: String,
        displayName: String,
        urlSchemes: [String] = ["http", "https"],
        documentUTIs: [String] = ["public.html"],
        osaScriptingDefinition: String? = nil,
        sdefFiles: [String: String] = [:],
        frameworks: [String] = [],
        macOSFiles: [String: Data] = [:],
        resourceFiles: [String: Data] = [:]
    ) throws -> URL {
        let fileManager = FileManager.default
        let appURL = tempDirectory.appendingPathComponent(folderName, isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let frameworksURL = contentsURL.appendingPathComponent("Frameworks", isDirectory: true)
        let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)

        try fileManager.createDirectory(at: frameworksURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

        var plist: [String: Any] = [
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleDisplayName": displayName,
            "CFBundleName": displayName,
            "CFBundlePackageType": "APPL",
            "CFBundleVersion": "1.0",
        ]

        if !urlSchemes.isEmpty {
            plist["CFBundleURLTypes"] = [
                [
                    "CFBundleURLName": "Web URL",
                    "CFBundleURLSchemes": urlSchemes,
                ]
            ]
        }

        if !documentUTIs.isEmpty {
            plist["CFBundleDocumentTypes"] = [
                [
                    "CFBundleTypeName": "HTML Document",
                    "LSItemContentTypes": documentUTIs,
                ]
            ]
        }

        if let osaScriptingDefinition {
            plist["OSAScriptingDefinition"] = osaScriptingDefinition
        }

        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try plistData.write(to: contentsURL.appendingPathComponent("Info.plist"))

        for (filename, content) in sdefFiles {
            try content.write(
                to: resourcesURL.appendingPathComponent(filename),
                atomically: true,
                encoding: .utf8
            )
        }

        for framework in frameworks {
            try fileManager.createDirectory(
                at: frameworksURL.appendingPathComponent(framework, isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        for (filename, data) in macOSFiles {
            try data.write(to: macOSURL.appendingPathComponent(filename))
        }

        for (filename, data) in resourceFiles {
            try data.write(to: resourcesURL.appendingPathComponent(filename))
        }

        return appURL
    }
}
