import Foundation
import Observation

// $HOME first, like hook.sh, so both agree on where the state lives.
let home = URL(fileURLWithPath: ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory())
let stateDir = home.appendingPathComponent(".claude-deck/state")

/// The declaration order is the order of the groups in the deck.
enum Status: Int { case needsYou, working, done }

struct Session: Identifiable {
    let pid: Int32
    let account: String
    let name: String
    let cwd: String
    let status: Status
    var finishedAt: Date? = nil
    var title: String? = nil
    var id: Int32 { pid }
}

/// Needs you, then working, both by name so their cards don't jump around.
/// Then done, the most recently finished first.
func deckOrder(_ a: Session, _ b: Session) -> Bool {
    if a.status != b.status { return a.status.rawValue < b.status.rawValue }
    if a.status == .done, a.finishedAt != b.finishedAt {
        return (a.finishedAt ?? .distantPast) > (b.finishedAt ?? .distantPast)
    }
    return (a.account, a.name) < (b.account, b.name)
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

/// A title line of a session transcript. Claude Code appends both titles again on every turn.
private struct TitleEntry: Decodable {
    let type: String
    let aiTitle: String?
    let customTitle: String?
}

/// The title of a session from the end of its transcript: the one set with /rename, else the AI-generated one.
/// Transcripts reach tens of MB, so only the end is read.
/// ponytail: gives up past the last 4 MB; the store then keeps the title it had before.
func transcriptTitle(_ url: URL) -> String? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    let size = (try? handle.seekToEnd()) ?? 0
    for window: UInt64 in [256 << 10, 4 << 20] {
        guard (try? handle.seek(toOffset: size > window ? size - window : 0)) != nil,
              let data = try? handle.readToEnd()
        else { return nil }
        var ai: String?
        var custom: String?
        // The first line can be cut by the window. It then fails to decode and is skipped.
        for line in data.split(separator: UInt8(ascii: "\n")).reversed() where custom == nil {
            guard line.range(of: Data("-title\"".utf8)) != nil,
                  let entry = try? JSONDecoder().decode(TitleEntry.self, from: Data(line))
            else { continue }
            if entry.type == "custom-title" { custom = entry.customTitle }
            if entry.type == "ai-title", ai == nil { ai = entry.aiTitle }
        }
        if let title = custom ?? ai { return title }
        if size <= window { return nil }
    }
    return nil
}

@MainActor @Observable
final class SessionStore {
    private(set) var sessions: [Session] = []
    private var timer: Timer?
    @ObservationIgnored private var transcripts: [String: URL] = [:]
    @ObservationIgnored private var titles: [URL: (size: Int, title: String?)] = [:]

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
                let liveDate = live.statusUpdatedAt.map { Date(timeIntervalSince1970: $0 / 1000) }
                let status = sessionStatus(hook: hook, hookDate: hookDate, live: live.status, liveDate: liveDate)
                // Claude stamps the moment a session goes idle. The hook file can be a later
                // idle_prompt notification, so it is only the fallback.
                let finishedAt = status == .done ? ((live.status == "idle" ? liveDate : nil) ?? hookDate) : nil
                return Session(
                    pid: live.pid,
                    account: account,
                    name: live.name ?? URL(fileURLWithPath: live.cwd).lastPathComponent,
                    cwd: live.cwd,
                    status: status,
                    finishedAt: finishedAt,
                    title: transcript(of: live.sessionId, in: dir).flatMap(title))
            }
        }
        .sorted(by: deckOrder)
    }

    /// <config dir>/projects/<folder>/<session id>.jsonl, searched once per session.
    private func transcript(of sessionId: String, in dir: URL) -> URL? {
        if let url = transcripts[sessionId] { return url }
        let projects = dir.appendingPathComponent("projects")
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: projects.path)) ?? []
        let url = folders.lazy
            .map { projects.appendingPathComponent($0).appendingPathComponent("\(sessionId).jsonl") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
        transcripts[sessionId] = url
        return url
    }

    /// Reads the transcript again only when it grew.
    private func title(_ transcript: URL) -> String? {
        let size = (try? transcript.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        if let cached = titles[transcript], cached.size == size { return cached.title }
        let title = transcriptTitle(transcript) ?? titles[transcript]?.title
        titles[transcript] = (size, title)
        return title
    }
}
