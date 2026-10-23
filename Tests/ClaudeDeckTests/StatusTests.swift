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

@Test func withoutHooksTheSessionFileDecides() {
    #expect(sessionStatus(hook: nil, hookDate: nil, live: "busy", liveDate: later) == .working)
    #expect(sessionStatus(hook: nil, hookDate: nil, live: "idle", liveDate: later) == .done)
}
