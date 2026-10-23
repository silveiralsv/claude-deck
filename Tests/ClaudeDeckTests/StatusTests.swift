import Foundation
import Testing
@testable import ClaudeDeck

private func event(_ name: String, tool: String? = nil, type: String? = nil) -> HookEvent {
    HookEvent(hookEventName: name, toolName: tool, notificationType: type)
}

private let earlier = Date(timeIntervalSince1970: 100)
private let later = Date(timeIntervalSince1970: 200)

@Test func hookEventsMapToStatus() {
    #expect(sessionStatus(hook: event("UserPromptSubmit"), hookDate: later, live: "busy", liveDate: earlier) == .working)
    #expect(sessionStatus(hook: event("PreToolUse", tool: "Bash"), hookDate: later, live: nil, liveDate: nil) == .working)
    #expect(sessionStatus(hook: event("PreToolUse", tool: "AskUserQuestion"), hookDate: later, live: nil, liveDate: nil) == .needsYou)
    #expect(sessionStatus(hook: event("Notification", type: "permission_prompt"), hookDate: later, live: nil, liveDate: nil) == .needsYou)
    #expect(sessionStatus(hook: event("Notification", type: "idle_prompt"), hookDate: later, live: nil, liveDate: nil) == .done)
    #expect(sessionStatus(hook: event("Stop"), hookDate: later, live: "busy", liveDate: earlier) == .done)
}

@Test func newerIdleSessionFileEndsAWorkingTurn() {
    // Esc interrupt: no Stop hook, but Claude marks the session idle.
    #expect(sessionStatus(hook: event("PreToolUse", tool: "Bash"), hookDate: earlier, live: "idle", liveDate: later) == .done)
    // A pending question stays visible even when the session file says idle.
    #expect(sessionStatus(hook: event("Notification", type: "permission_prompt"), hookDate: earlier, live: "idle", liveDate: later) == .needsYou)
}

@Test func deckShowsNeedsYouThenWorkingThenMostRecentlyFinished() {
    let sessions = [
        Session(pid: 1, account: "claude", name: "old-done", cwd: "/", status: .done, finishedAt: earlier),
        Session(pid: 2, account: "claude", name: "b-working", cwd: "/", status: .working),
        Session(pid: 3, account: "claude", name: "new-done", cwd: "/", status: .done, finishedAt: later),
        Session(pid: 4, account: "claude", name: "asking", cwd: "/", status: .needsYou),
        Session(pid: 5, account: "claude", name: "a-working", cwd: "/", status: .working),
    ]
    #expect(sessions.sorted(by: deckOrder).map(\.name) == ["asking", "a-working", "b-working", "new-done", "old-done"])
}

@Test func transcriptTitlePrefersTheLatestCustomTitle() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("claude-deck-\(UUID().uuidString).jsonl")
    defer { try? FileManager.default.removeItem(at: url) }
    let lines = [
        #"{"type":"ai-title","aiTitle":"Old AI title","sessionId":"s"}"#,
        #"{"type":"user","message":"the word -title" here"}"#,
        #"{"type":"ai-title","aiTitle":"New AI title","sessionId":"s"}"#,
    ]
    try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    #expect(transcriptTitle(url) == "New AI title")

    let renamed = lines + [#"{"type":"custom-title","customTitle":"My name","sessionId":"s"}"#, lines[2]]
    try renamed.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    #expect(transcriptTitle(url) == "My name")
}

@Test func backgroundWorkAndHooklessTurns() {
    // Turn over, but shells, monitors or agents still run.
    #expect(sessionStatus(hook: event("Stop"), hookDate: later, live: "shell", liveDate: earlier, background: true) == .background)
    #expect(sessionStatus(hook: nil, hookDate: nil, live: "shell", liveDate: later, background: true) == .background)
    // Background work doesn't hide a question.
    #expect(sessionStatus(hook: event("Notification", type: "permission_prompt"), hookDate: later, live: "shell", liveDate: earlier, background: true) == .needsYou)
    // A finished background task starts a turn that fires no hook.
    #expect(sessionStatus(hook: event("Stop"), hookDate: earlier, live: "busy", liveDate: later) == .working)
    #expect(sessionStatus(hook: event("Stop"), hookDate: later, live: "busy", liveDate: earlier) == .done)
}

@Test func countsOnlyChildrenStartedThroughTheShellSnapshot() throws {
    let snapshot = Process()
    snapshot.executableURL = URL(fileURLWithPath: "/bin/sh")
    snapshot.arguments = ["-c", "sleep 5 # /tmp/shell-snapshots/snapshot-zsh.sh"]
    let other = Process()
    other.executableURL = URL(fileURLWithPath: "/bin/sleep")
    other.arguments = ["5"]
    try snapshot.run()
    try other.run()
    defer { snapshot.terminate(); other.terminate() }
    var known: [Int32: Bool] = [:]
    #expect(backgroundShells(of: [getpid()], known: &known)[getpid()] == 1)
    #expect(backgroundShells(of: [getpid()], known: &known)[getpid()] == 1)
}

@Test func countsRunningBackgroundAgents() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("claude-deck-\(UUID().uuidString)")
    let agents = dir.appendingPathComponent("session/subagents")
    try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let metas = [
        "running": #"{"requestShape":"background"}"#,
        "finished": #"{"requestShape":"background","finished":true}"#,
        "foreground": #"{"requestShape":"foreground"}"#,
        "stale": #"{"requestShape":"background"}"#,
    ]
    for (name, meta) in metas {
        try meta.write(to: agents.appendingPathComponent("agent-\(name).meta.json"), atomically: true, encoding: .utf8)
        try "{}".write(to: agents.appendingPathComponent("agent-\(name).jsonl"), atomically: true, encoding: .utf8)
    }
    try FileManager.default.setAttributes(
        [.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: agents.appendingPathComponent("agent-stale.jsonl").path)
    #expect(runningAgents(of: dir.appendingPathComponent("session.jsonl")) == 1)
}

@Test func withoutHooksTheSessionFileDecides() {
    #expect(sessionStatus(hook: nil, hookDate: nil, live: "busy", liveDate: later) == .working)
    #expect(sessionStatus(hook: nil, hookDate: nil, live: "idle", liveDate: later) == .done)
}
