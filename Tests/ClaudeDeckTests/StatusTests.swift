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

@Test func withoutHooksTheSessionFileDecides() {
    #expect(sessionStatus(hook: nil, hookDate: nil, live: "busy", liveDate: later) == .working)
    #expect(sessionStatus(hook: nil, hookDate: nil, live: "idle", liveDate: later) == .done)
}
