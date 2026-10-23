import Foundation
import Observation

// $HOME first, like hook.sh, so both agree on where the state lives.
let home = URL(fileURLWithPath: ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory())
let stateDir = home.appendingPathComponent(".claude-deck/state")

enum Status { case working, done, needsYou }

struct Session: Identifiable {
    let pid: Int32
    let account: String
    let name: String
    let cwd: String
    let status: Status
    var id: Int32 { pid }
}

/// What Claude Code writes to <config dir>/sessions/<pid>.json while a session runs.
/// The format is undocumented, so only the fields the deck needs are decoded.
private struct LiveSession: Decodable {
    let pid: Int32
    let sessionId: String
    let cwd: String
    let name: String?
    let kind: String?
    let status: String?
    let statusUpdatedAt: Double?
}

/// The latest hook event of a session, as stored by hook.sh.
struct HookEvent: Decodable {
    let hookEventName: String
    let toolName: String?
    let notificationType: String?
}

private let snakeCase: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
}()

/// Every Claude Code config dir in $HOME (~/.claude, ~/.claude-ed, ...): the ones with a sessions folder.
func claudeConfigDirs() -> [URL] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: home.path)) ?? []
    return names.filter { $0.hasPrefix(".claude") }
        .map { home.appendingPathComponent($0) }
        .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("sessions").path) }
        .sorted { $0.path < $1.path }
}

/// Hooks carry the status. Claude's own session file covers sessions started before the hooks
/// were installed, and an Esc interrupt, which ends the turn without a Stop hook.
func sessionStatus(hook: HookEvent?, hookDate: Date?, live: String?, liveDate: Date?) -> Status {
    let fromHook: Status? = hook.map {
        switch $0.hookEventName {
        case "Stop":
            return .done
        case "Notification":
            return ["idle_prompt", "auth_success"].contains($0.notificationType) ? .done : .needsYou
        case "PreToolUse":
            return ["AskUserQuestion", "ExitPlanMode"].contains($0.toolName) ? .needsYou : .working
        default:
            return .working
        }
    }
    let idle = live == "idle"
    switch fromHook {
    case nil:
        return idle ? .done : .working
    case .working? where idle && (liveDate ?? .distantPast) > (hookDate ?? .distantPast):
        return .done
    case let status?:
        return status
    }
}

private func isAlive(_ pid: Int32) -> Bool {
    kill(pid, 0) == 0 || errno == EPERM
}

@MainActor @Observable
final class SessionStore {
    private(set) var sessions: [Session] = []
    private var timer: Timer?

    init() {
        refresh()
        // ponytail: polls a few small files every second; move to FSEvents if it ever shows up in Activity Monitor.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        sessions = claudeConfigDirs().flatMap { dir -> [Session] in
            let account = String(dir.lastPathComponent.dropFirst())
            let files = (try? FileManager.default.contentsOfDirectory(
                at: dir.appendingPathComponent("sessions"), includingPropertiesForKeys: nil)) ?? []
            return files.filter { $0.pathExtension == "json" }.compactMap { file in
                guard let data = try? Data(contentsOf: file),
                      let live = try? JSONDecoder().decode(LiveSession.self, from: data),
                      live.kind == nil || live.kind == "interactive",
                      isAlive(live.pid)
                else { return nil }
                let hookURL = stateDir.appendingPathComponent("\(live.sessionId).json")
                let hook = (try? Data(contentsOf: hookURL)).flatMap { try? snakeCase.decode(HookEvent.self, from: $0) }
                let hookDate = (try? hookURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                return Session(
                    pid: live.pid,
                    account: account,
                    name: live.name ?? URL(fileURLWithPath: live.cwd).lastPathComponent,
                    cwd: live.cwd,
                    status: sessionStatus(
                        hook: hook, hookDate: hookDate,
                        live: live.status, liveDate: live.statusUpdatedAt.map { Date(timeIntervalSince1970: $0 / 1000) }))
            }
        }
        .sorted { ($0.account, $0.name) < ($1.account, $1.name) }
    }
}
