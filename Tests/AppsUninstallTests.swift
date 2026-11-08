// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import vorssaint

final class AppsUninstallTests: XCTestCase {
    private func rule(_ entry: String,
                      name: String = "Vorssaint",
                      bundle: String? = "com.example.Vorssaint") -> String? {
        Apps.matchRule(entry: entry, appName: name, bundleID: bundle)?.rawValue
    }

    // MARK: - Match rules

    func testExactBundleID() {
        XCTAssertEqual(rule("com.example.Vorssaint"), "bundle-id")
    }

    func testBundleIDPrefixAndGroupContainer() {
        XCTAssertEqual(rule("com.example.Vorssaint.plist"), "bundle-id-prefix")
        XCTAssertEqual(rule("com.example.Vorssaint.ShipIt"), "bundle-id-prefix")
        XCTAssertEqual(rule("group.com.example.Vorssaint"), "bundle-id-prefix")
        XCTAssertEqual(rule("group.com.example.Vorssaint.shared"), "bundle-id-prefix")
    }

    func testExactName() {
        XCTAssertEqual(rule("Vorssaint", bundle: nil), "name")
    }

    func testNameBoundaries() {
        XCTAssertEqual(rule("Vorssaint.plist", bundle: nil), "name-boundary")
        XCTAssertEqual(rule("com.example.Vorssaint", bundle: nil), "name-boundary")
        XCTAssertEqual(rule("com.example.Vorssaint.helper", bundle: nil), "name-boundary")
    }

    func testSubstringSiblingsDoNotMatch() {
        // The regression from issue #1: "vorssaint-cli" is a sibling product,
        // not this app's data.
        XCTAssertNil(rule("vorssaint-cli", bundle: nil))
        XCTAssertNil(rule("vorssaint-cli.plist", bundle: nil))
        XCTAssertNil(rule("com.example.VorssaintCLI", bundle: nil))
    }

    func testArcDoesNotMatchArcade() {
        XCTAssertEqual(rule("com.company.arc", name: "Arc", bundle: "com.company.arc"), "bundle-id")
        XCTAssertNil(rule("com.example.arcade", name: "Arc", bundle: "com.company.arc"))
        XCTAssertNil(rule("arcade", name: "Arc", bundle: nil))
    }

    // MARK: - relatedFiles

    func testRelatedFilesExcludesSubstringMatches() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("vorssaint-test-\(UUID().uuidString)")
        let caches = home.appendingPathComponent("Library/Caches")
        try fm.createDirectory(at: caches, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }

        for entry in ["com.example.Vorssaint", "Vorssaint", "vorssaint-cli", "com.example.arcade"] {
            try fm.createDirectory(at: caches.appendingPathComponent(entry), withIntermediateDirectories: true)
        }

        let files = Apps.relatedFiles(appName: "Vorssaint", bundleID: "com.example.Vorssaint", home: home.path)
        let names = Set(files.map { URL(fileURLWithPath: $0.path).lastPathComponent })

        XCTAssertTrue(names.contains("com.example.Vorssaint"))
        XCTAssertTrue(names.contains("Vorssaint"))
        XCTAssertFalse(names.contains("vorssaint-cli"))
        XCTAssertFalse(names.contains("com.example.arcade"))

        let byName = Dictionary(uniqueKeysWithValues: files.map {
            (URL(fileURLWithPath: $0.path).lastPathComponent, $0.confidence)
        })
        XCTAssertEqual(byName["com.example.Vorssaint"], "bundle-id")
        XCTAssertEqual(byName["Vorssaint"], "name")
    }
}
