// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Foundation

// ~/.config/vorssaint/config.json — snippets + future settings.

struct Snippet: Codable {
    var trigger: String
    var expansion: String
    var created: String
}

struct Config: Codable {
    var snippets: [Snippet] = []
}

enum Store {
    static var dir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/vorssaint", isDirectory: true)
    }
    static var configPath: URL { dir.appendingPathComponent("config.json") }

    static func load() -> Config {
        guard let d = try? Data(contentsOf: configPath) else { return Config() }
        return (try? JSONDecoder().decode(Config.self, from: d)) ?? Config()
    }

    static func save(_ c: Config) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try e.encode(c).write(to: configPath, options: .atomic)
    }

    /// Render {{date}} {{time}} {{datetime}} {{clipboard}} {{uuid}} {{user}} variables.
    static func expand(_ s: String) -> String {
        var out = s
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        out = out.replacingOccurrences(of: "{{date}}", with: df.string(from: Date()))
        df.dateFormat = "HH:mm"
        out = out.replacingOccurrences(of: "{{time}}", with: df.string(from: Date()))
        df.dateFormat = "yyyy-MM-dd HH:mm"
        out = out.replacingOccurrences(of: "{{datetime}}", with: df.string(from: Date()))
        out = out.replacingOccurrences(of: "{{clipboard}}", with: NSPasteboard.general.string(forType: .string) ?? "")
        out = out.replacingOccurrences(of: "{{uuid}}", with: UUID().uuidString)
        out = out.replacingOccurrences(of: "{{user}}", with: NSUserName())
        return out
    }
}
