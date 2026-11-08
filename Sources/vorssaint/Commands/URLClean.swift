// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import ArgumentParser
import Foundation

struct URLGroup: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "url",
        abstract: "URL tools",
        subcommands: [Clean.self]
    )

    struct Clean: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Strip tracking parameters from URLs",
            discussion: """
            Removes utm_*, fbclid, gclid, msclkid, igshid, si, spm, ref_* and friends.
            Reads URLs from arguments or stdin, prints cleaned URLs (and --copy to clipboard).
            """
        )
        @OptionGroup var g: GlobalOptions
        @Argument(help: "URLs to clean; omit to read stdin") var urls: [String] = []
        @Flag(name: .long, help: "Copy result(s) to clipboard") var copy = false

        static let blockedParams: Set<String> = [
            "fbclid", "gclid", "dclid", "gbraid", "wbraid", "msclkid", "yclid", "vero_id",
            "mc_cid", "mc_eid", "igshid", "igsh", "si", "pp", "spm", "scm", "sxsrf",
            "ved", "ei", "oq", "gs_lcp", "sclient", "bih", "bvm", "sa", "usg",
            "mkt_tok", "trk", "trkInfo", "ref_src", "ref_url", "_openstat", "wt.mc_id",
            "pk_campaign", "pk_kwd", "pk_source", "pk_medium", "pk_content", "pk_cid",
            "hsa_acc", "hsa_cam", "hsa_grp", "hsa_ad", "hsa_src", "hsa_tgt", "hsa_kw",
            "hsa_mt", "hsa_net", "hsa_ver", "fb_source", "twclid", "ttclid", "li_fat_id",
            "wickedid", "wickedsource", "irclickid", "irgwc", "cmpid", "campaignid",
            "zanpid", "feature", "kw", "csi", "ncid", "sr_share", "share_token",
        ]

        static func clean(_ raw: String) -> String {
            // Pass non-URL input through unchanged: URLComponents would
            // otherwise percent-encode e.g. "not a url" into "not%20a%20url".
            guard var c = URLComponents(string: raw),
                  c.scheme != nil || c.query != nil else { return raw }
            let items = (c.queryItems ?? []).filter { item in
                let n = item.name.lowercased()
                if n.hasPrefix("utm_") || n.hasPrefix("ref_") || n.hasPrefix("fb_") && n != "fb_source" { return false }
                return !blockedParams.contains(n)
            }
            c.queryItems = items.isEmpty ? nil : items
            // strip tracking fragments like :~:text= keep (it's content), but remove "smid"/"smtyp" style
            return c.string ?? raw
        }

        struct Result: Encodable { var input: String, output: String, removed: Int }

        func run() throws {
            wireOutput(g, command: "vorssaint url clean")
            var inputs = urls
            if inputs.isEmpty {
                let stdin = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
                inputs = stdin.split(whereSeparator: \.isWhitespace).map(String.init)
            }
            guard !inputs.isEmpty else { throw ValidationError("no URLs given") }
            let results = inputs.map { raw -> Result in
                let cleaned = Clean.clean(raw)
                let before = URLComponents(string: raw)?.queryItems?.count ?? 0
                let after = URLComponents(string: cleaned)?.queryItems?.count ?? 0
                return Result(input: raw, output: cleaned, removed: before - after)
            }
            if copy {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(results.map(\.output).joined(separator: "\n"), forType: .string)
            }
            if Out.json { Out.emit(results) { "" } }
            else {
                for r in results {
                    print(r.output + (Out.plain ? "" : (r.removed > 0 ? ANSI.dim("  (-\(r.removed) params)") : "")))
                }
            }
        }
    }
}
