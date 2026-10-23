import AppKit

enum TerminalFocus {
    /// Brings the terminal tab that runs `pid` to the front. Returns an error message, or nil on success.
    @MainActor
    static func focus(pid: Int32) -> String? {
        guard let tty = tty(of: pid) else { return String(localized: "No terminal") }
        if isRunning("com.mitchellh.ghostty"), focusGhostty(tty: tty) { return nil }
        if isRunning("com.apple.Terminal"), run(terminalScript(tty: tty))?.booleanValue == true { return nil }
        return String(localized: "Tab not found")
    }

    static func tty(of pid: Int32) -> String? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let dev = info.kp_eproc.e_tdev
        guard dev != -1, let name = devname(dev, S_IFCHR) else { return nil }
        let tty = String(cString: name)
        return tty == "??" ? nil : "/dev/" + tty
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

    private static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
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
