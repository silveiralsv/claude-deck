import Foundation

enum HookInstaller {
    static let events = ["UserPromptSubmit", "PreToolUse", "PostToolUse", "Notification", "Stop", "SessionEnd"]

    /// Copies hook.sh to ~/.claude-deck and registers it in the settings.json of every Claude config dir.
    /// Each changed settings.json is backed up first. Returns the settings files it changed.
    static func install() throws -> [String] {
        let fm = FileManager.default
        guard let source = Bundle.main.url(forResource: "hook", withExtension: "sh") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "hook.sh is missing from the app bundle"])
        }
        let hook = home.appendingPathComponent(".claude-deck/hook.sh")
        try fm.createDirectory(at: hook.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: hook.path) { try fm.removeItem(at: hook) }
        try fm.copyItem(at: source, to: hook)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)

        // Config dirs often symlink a shared settings.json. Resolve it so the atomic write
        // replaces the real file, not the link, and each file is written once.
        let settingsFiles = Set(claudeConfigDirs().map { $0.appendingPathComponent("settings.json").resolvingSymlinksInPath() })
        var changed: [String] = []
        for settings in settingsFiles.sorted(by: { $0.path < $1.path }) {
            var root: [String: Any] = [:]
            if let data = try? Data(contentsOf: settings) {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: settings.path])
                }
                root = json
            }
            var hooks = root["hooks"] as? [String: Any] ?? [:]
            var added = false
            for event in events {
                var groups = hooks[event] as? [[String: Any]] ?? []
                let present = groups.contains { group in
                    (group["hooks"] as? [[String: Any]])?.contains { $0["command"] as? String == hook.path } == true
                }
                if present { continue }
                groups.append(["hooks": [["type": "command", "command": hook.path]]])
                hooks[event] = groups
                added = true
            }
            guard added else { continue }
            if fm.fileExists(atPath: settings.path) {
                let backup = URL(fileURLWithPath: settings.path + ".claude-deck.bak")
                try? fm.removeItem(at: backup)
                try fm.copyItem(at: settings, to: backup)
            }
            root["hooks"] = hooks
            try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
                .write(to: settings, options: .atomic)
            changed.append(settings.path)
        }
        return changed
    }
}
