// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Permission-free sanity checks for CI and post-install verification.
/// Run with `vorssaint --selftest`; never touches the network, TCC-gated
/// APIs, the pasteboard or the user's files.
enum SelfTest {
    static func run() throws {
        var failures: [(name: String, detail: String)] = []

        func check(_ name: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
            if !condition { failures.append((name, detail())) }
        }
        func equal(_ name: String, _ got: String, _ want: String) {
            check(name, got == want, "got \(got.debugDescription), want \(want.debugDescription)")
        }
        func rule(_ entry: String, name: String, bundle: String?) -> Apps.MatchRule? {
            Apps.matchRule(entry: entry, appName: name, bundleID: bundle)
        }

        // url clean — pure URL parsing, no permissions.
        equal("url clean strips utm_*",
              URLGroup.Clean.clean("https://example.com/?a=1&utm_source=x&b=2"),
              "https://example.com/?a=1&b=2")
        equal("url clean strips fbclid",
              URLGroup.Clean.clean("https://x.com/p?fbclid=abc"),
              "https://x.com/p")
        equal("url clean passes non-URLs through",
              URLGroup.Clean.clean("not a url"), "not a url")

        // Capability catalog — the agent discovery endpoint.
        check("catalog is non-empty", !Catalog.entries.isEmpty)
        check("catalog statuses are known",
              Catalog.entries.allSatisfy { ["available", "planned"].contains($0.status) })
        check("catalog entries are complete",
              Catalog.entries.allSatisfy { !$0.command.isEmpty && !$0.summary.isEmpty })

        // apps uninstall match rules — never bare substring matches.
        check("uninstall: exact bundle id matches",
              rule("com.example.App", name: "App", bundle: "com.example.App") == .bundleID)
        check("uninstall: bundle id prefix matches",
              rule("com.example.App.ShipIt", name: "App", bundle: "com.example.App") == .bundleIDPrefix)
        check("uninstall: exact name matches",
              rule("App", name: "App", bundle: nil) == .name)
        check("uninstall: name boundary matches",
              rule("com.example.App", name: "App", bundle: nil) == .nameBoundary)
        check("uninstall: rejects substring sibling",
              rule("app-cli", name: "App", bundle: nil) == nil)

        // Output helpers.
        check("display width: CJK counts 2 cells", "漢".displayWidth == 2)
        equal("fmtBytes", fmtBytes(1536), "1.5 KB")

        guard failures.isEmpty else {
            for f in failures {
                let detail = f.detail.isEmpty ? "" : " — \(f.detail)"
                FileHandle.standardError.write(Data("selftest: FAIL \(f.name)\(detail)\n".utf8))
            }
            throw VExit.runtime
        }
        print("selftest: all checks passed")
    }
}
