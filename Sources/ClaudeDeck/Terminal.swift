import AppKit

enum TerminalFocus {
    /// Brings the terminal tab that runs `pid` to the front. Returns an error message, or nil on success.
    /// Only the app that runs the session is asked: the Ghostty title marker written to a Terminal.app
    /// session would stay in its title.
    @MainActor
    static func focus(pid: Int32) -> String? {
        let herdr = herdrVariables(arguments(of: pid))
        if !herdr.isEmpty { return focusHerdr(herdr) }
        guard let tty = tty(of: pid) else { return String(localized: "No terminal") }
        let found: Bool
        switch hostApp(of: pid) {
        case "com.mitchellh.ghostty": found = focusGhostty(tty: tty)
        case "com.apple.Terminal": found = run(terminalScript(tty: tty))?.booleanValue == true
        default: return String(localized: "Terminal not supported")
        }
        return found ? nil : String(localized: "Tab not found")
    }

    static func tty(of pid: Int32) -> String? {
        guard let dev = process(pid)?.kp_eproc.e_tdev, dev != -1, let name = devname(dev, S_IFCHR) else { return nil }
        let tty = String(cString: name)
        return tty == "??" ? nil : "/dev/" + tty
    }

    /// The bundle id of the app the session runs in: its closest ancestor process that is an app
    /// (claude → zsh → login → Terminal, for example).
    static func hostApp(of pid: Int32) -> String? {
        var current = pid
        for _ in 0..<10 {
            guard let parent = process(current)?.kp_eproc.e_ppid, parent > 1 else { return nil }
            if let bundleID = NSRunningApplication(processIdentifier: parent)?.bundleIdentifier { return bundleID }
            current = parent
        }
        return nil
    }

    /// The variables herdr sets in each of its panes, from the arguments and environment of a process.
    static func herdrVariables(_ arguments: String) -> [String: String] {
        var variables: [String: String] = [:]
        for entry in arguments.split(separator: "\0") where entry.hasPrefix("HERDR_") {
            let parts = entry.split(separator: "=", maxSplits: 1)
            if parts.count == 2 { variables[String(parts[0])] = String(parts[1]) }
        }
        return variables
    }

    /// Herdr runs each session in a pty of its own, which no terminal app knows about. So the herdr
    /// CLI focuses the session's pane, then the terminal tab that runs the herdr client comes to the front.
    @MainActor
    private static func focusHerdr(_ herdr: [String: String]) -> String? {
        guard let bin = herdr["HERDR_BIN_PATH"], let pane = herdr["HERDR_PANE_ID"] else {
            return String(localized: "Tab not found")
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: bin)
        task.arguments = ["agent", "focus", pane]
        // The socket picks the herdr session the pane belongs to.
        if let socket = herdr["HERDR_SOCKET_PATH"] {
            task.environment = ProcessInfo.processInfo.environment.merging(["HERDR_SOCKET_PATH": socket]) { $1 }
        }
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return String(localized: "Tab not found") }
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return String(localized: "Tab not found") }
        // A herdr client runs in a terminal and, unlike herdr commands run inside a pane, has no pane.
        // ponytail: the first client found, which can be attached to another named herdr session.
        let client = processes().first {
            name(of: $0) == "herdr" && $0.kp_eproc.e_tdev != -1
                && herdrVariables(arguments(of: $0.kp_proc.p_pid))["HERDR_PANE_ID"] == nil
        }
        guard let client else { return String(localized: "No terminal") }
        return focus(pid: client.kp_proc.p_pid)
    }

    private static func name(of proc: kinfo_proc) -> String {
        withUnsafeBytes(of: proc.kp_proc.p_comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }

    private static func process(_ pid: Int32) -> kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info
    }

    /// Ghostty 1.3 doesn't expose a terminal's tty over AppleScript. So the title of the tab is set
    /// to a marker through the tty, the terminal with that title is focused, and the title is put back.
    /// ponytail: drop the title trick once Ghostty exposes the tty (expected in 1.4).
    @MainActor
    private static func focusGhostty(tty: String) -> Bool {
        guard let before = run(#"tell application "Ghostty" to get {id, name} of every terminal"#) else { return false }
        let ids = strings(before.atIndex(1))
        let names = strings(before.atIndex(2))
        let marker = "claude-deck-\(UUID().uuidString.prefix(8))"
        var id: String?
        // Claude redraws the title while it works, so the marker can be overwritten before the lookup.
        for _ in 0..<3 where id == nil {
            setTitle(marker, tty: tty)
            Thread.sleep(forTimeInterval: 0.15)
            id = run(#"tell application "Ghostty" to get id of first terminal whose name is "\#(marker)""#)?.stringValue
        }
        guard let id else { return false }
        if let index = ids.firstIndex(of: id), index < names.count { setTitle(names[index], tty: tty) }
        return run("""
            tell application "Ghostty"
                focus (first terminal whose id is "\(id)")
                activate
            end tell
            """) != nil
    }

    private static func terminalScript(tty: String) -> String {
        """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(tty)" then
                        set miniaturized of w to false
                        set selected of t to true
                        set index of w to 1
                        activate
                        return true
                    end if
                end repeat
            end repeat
        end tell
        return false
        """
    }

    private static func setTitle(_ title: String, tty: String) {
        guard let handle = FileHandle(forWritingAtPath: tty) else { return }
        handle.write(Data("\u{1B}]2;\(title)\u{07}".utf8))
        try? handle.close()
    }

    private static func strings(_ list: NSAppleEventDescriptor?) -> [String] {
        guard let list, list.numberOfItems > 0 else { return [] }
        return (1...list.numberOfItems).map { list.atIndex($0)?.stringValue ?? "" }
    }

    @MainActor @discardableResult
    private static func run(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { NSLog("Claude Deck AppleScript error: \(error)") }
        return error == nil ? result : nil
    }
}
