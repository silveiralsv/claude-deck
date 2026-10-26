import Foundation
import Observation

// $HOME first, like hook.sh, so both agree on where the state lives.
let home = URL(fileURLWithPath: ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory())
let stateDir = home.appendingPathComponent(".claude-deck/state")

/// The declaration order is the order of the groups in the deck.
/// Background: the turn is over, but shells, monitors or agents it started still run.
enum Status: Int { case needsYou, working, background, done }

struct Session: Identifiable, Equatable {
    let pid: Int32
    let account: String
    let name: String
    let cwd: String
    let status: Status
    var finishedAt: Date? = nil
    var title: String? = nil
    var shells = 0
    var agents = 0
    /// Picks the color and hat of the session's pet.
    var seed: UInt64 = 0
    var id: Int32 { pid }
}

/// Needs you, working and background, each by name so their cards don't jump around.
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
    let startedAt: Double?
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
/// were installed, and turns that fire no hook: an Esc interrupt ends one without a Stop, and a
/// finished background task starts one without a UserPromptSubmit.
/// A done session whose background work still runs is in the background.
func sessionStatus(hook: HookEvent?, hookDate: Date?, live: String?, liveDate: Date?, background: Bool = false) -> Status {
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
    // "shell" is how Claude marks an idle session with background shells.
    let idle = live == "idle" || live == "shell"
    let liveIsNewer = (liveDate ?? .distantPast) > (hookDate ?? .distantPast)
    // Claude marks a session "waiting" while a question, a permission dialog or a menu waits for the user.
    if live == "waiting", hook == nil || liveIsNewer { return .needsYou }
    let status: Status
    switch fromHook {
    case nil:
        status = idle ? .done : .working
    case .working? where idle && liveIsNewer:
        status = .done
    case .done? where live == "busy" && liveIsNewer:
        status = .working
    case let fromHook?:
        status = fromHook
    }
    return status == .done && background ? .background : status
}

private func isAlive(_ pid: Int32) -> Bool {
    kill(pid, 0) == 0 || errno == EPERM
}

/// Background shells and monitors per session pid: the children Claude Code starts through
/// its shell snapshot (zsh -c source …/shell-snapshots/…). MCP servers don't match.
/// `known` remembers which child pids matched, since reading the arguments of a process is the expensive part.
func backgroundShells(of pids: Set<Int32>, known: inout [Int32: Bool]) -> [Int32: Int] {
    guard !pids.isEmpty else { return [:] }
    var counts: [Int32: Int] = [:]
    var seen: [Int32: Bool] = [:]
    for proc in processes() where pids.contains(proc.kp_eproc.e_ppid) {
        let pid = proc.kp_proc.p_pid
        let isShell = known[pid] ?? arguments(of: pid).contains("shell-snapshots")
        seen[pid] = isShell
        if isShell { counts[proc.kp_eproc.e_ppid, default: 0] += 1 }
    }
    known = seen
    return counts
}

func processes() -> [kinfo_proc] {
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
    var size = 0
    guard sysctl(&mib, 4, nil, &size, nil, 0) == 0 else { return [] }
    // Room for processes started between the two calls.
    var procs = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride + 32)
    size = procs.count * MemoryLayout<kinfo_proc>.stride
    guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else { return [] }
    procs.removeSubrange((size / MemoryLayout<kinfo_proc>.stride)...)
    return procs
}

/// The arguments of a process, then its environment, separated by NUL bytes.
func arguments(of pid: Int32) -> String {
    var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
    var size = 0
    guard sysctl(&mib, 3, nil, &size, nil, 0) == 0 else { return "" }
    var buffer = [UInt8](repeating: 0, count: size)
    guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return "" }
    return String(decoding: buffer.prefix(size), as: UTF8.self)
}

/// What Claude Code writes next to each subagent transcript.
private struct AgentMeta: Decodable {
    let requestShape: String?
    let finished: Bool?
}

/// Background subagents still running for a session: unfinished, with a transcript written in the last 10 minutes.
/// Older Claude Code versions never set `finished`, hence the time limit.
/// ponytail: an agent silent in one tool call for over 10 minutes drops out, and a killed one lingers up to 10 minutes.
func runningAgents(of transcript: URL, now: Date = Date()) -> Int {
    let dir = transcript.deletingPathExtension().appendingPathComponent("subagents")
    let files = (try? FileManager.default.contentsOfDirectory(
        at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
    return files.filter { file in
        guard file.pathExtension == "jsonl",
              let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
              now.timeIntervalSince(modified) < 600,
              let data = try? Data(contentsOf: file.deletingPathExtension().appendingPathExtension("meta.json")),
              let meta = try? JSONDecoder().decode(AgentMeta.self, from: data)
        else { return false }
        return meta.requestShape == "background" && meta.finished != true
    }.count
}

/// A title line of a session transcript. Claude Code appends both titles again on every turn.
private struct TitleEntry: Decodable {
    let type: String
    let aiTitle: String?
    let customTitle: String?
}

/// The title of a session from its transcript: the one set with /rename, else the AI-generated one.
/// Transcripts reach tens of MB, so only the end is read: the last 256 KB, then the last 4 MB.
/// With `after`, only the bytes written since that offset are read, so a growing transcript stays cheap.
/// ponytail: a title further back than 4 MB is missed until Claude appends it again on the next turn.
func transcriptTitle(_ url: URL, after offset: UInt64? = nil) -> String? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    let size = (try? handle.seekToEnd()) ?? 0
    let starts = offset.map { [$0] } ?? [256 << 10, 4 << 20].map { size > $0 ? size - $0 : 0 }
    for start in starts {
        guard (try? handle.seek(toOffset: start)) != nil, let data = try? handle.readToEnd() else { return nil }
        if let title = latestTitle(in: data) { return title }
        if start == 0 { return nil }
    }
    return nil
}

private func latestTitle(in data: Data) -> String? {
    var ai: String?
    // The first line can be cut by the read. It then fails to decode and is skipped.
    for line in data.split(separator: UInt8(ascii: "\n")).reversed() {
        guard line.range(of: Data("-title\"".utf8)) != nil,
              let entry = try? JSONDecoder().decode(TitleEntry.self, from: Data(line))
        else { continue }
        if entry.type == "custom-title" { return entry.customTitle }
        if entry.type == "ai-title", ai == nil { ai = entry.aiTitle }
    }
    return ai
}

/// FNV-1a: unlike Hasher, it gives the same value on every launch.
func stableHash(_ text: String) -> UInt64 {
    text.utf8.reduce(0xcbf2_9ce4_8422_2325) { ($0 ^ UInt64($1)) &* 0x100_0000_01b3 }
}

@MainActor @Observable
final class SessionStore {
    private(set) var sessions: [Session] = []
    private var timer: Timer?
    @ObservationIgnored private var transcripts: [String: URL] = [:]
    @ObservationIgnored private var titles: [URL: (size: Int, title: String?)] = [:]
    @ObservationIgnored private var shellChildren: [Int32: Bool] = [:]
    @ObservationIgnored private var agentCounts: [URL: (checked: Date, count: Int)] = [:]

    init() {
        refresh()
        // ponytail: polls a few small files every second; move to FSEvents if it ever shows up in Activity Monitor.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        let lives = claudeConfigDirs().flatMap { dir -> [(URL, LiveSession)] in
            let files = (try? FileManager.default.contentsOfDirectory(
                at: dir.appendingPathComponent("sessions"), includingPropertiesForKeys: nil)) ?? []
            return files.filter { $0.pathExtension == "json" }.compactMap { file in
                guard let data = try? Data(contentsOf: file),
                      let live = try? JSONDecoder().decode(LiveSession.self, from: data),
                      live.kind == nil || live.kind == "interactive",
                      isAlive(live.pid)
                else { return nil }
                return (dir, live)
            }
        }
        let shells = backgroundShells(of: Set(lives.map { $0.1.pid }), known: &shellChildren)
        let fresh = lives.map { dir, live in session(live, in: dir, shells: shells[live.pid] ?? 0) }
            .sorted(by: deckOrder)
        // Every assignment redraws the whole deck, so skip the ones that change nothing.
        if fresh != sessions { sessions = fresh }
    }

    private func session(_ live: LiveSession, in dir: URL, shells: Int) -> Session {
        let hookURL = stateDir.appendingPathComponent("\(live.sessionId).json")
        let hook = (try? Data(contentsOf: hookURL)).flatMap { try? snakeCase.decode(HookEvent.self, from: $0) }
        let hookDate = (try? hookURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let liveDate = live.statusUpdatedAt.map { Date(timeIntervalSince1970: $0 / 1000) }
        let transcript = transcript(of: live.sessionId, in: dir)
        // Only an idle session can be in the background, so only then are its agents counted.
        let idle = live.status == "idle" || live.status == "shell"
        let agents = idle ? transcript.map(agentCount) ?? 0 : 0
        let status = sessionStatus(
            hook: hook, hookDate: hookDate, live: live.status, liveDate: liveDate,
            background: live.status == "shell" || shells > 0 || agents > 0)
        // Claude stamps the moment a session goes idle. The hook file can be a later
        // idle_prompt notification, so it is only the fallback.
        let finishedAt = status == .done ? ((idle ? liveDate : nil) ?? hookDate) : nil
        return Session(
            pid: live.pid,
            account: String(dir.lastPathComponent.dropFirst()),
            name: live.name ?? URL(fileURLWithPath: live.cwd).lastPathComponent,
            cwd: live.cwd,
            status: status,
            finishedAt: finishedAt,
            title: transcript.flatMap(title),
            shells: status == .background ? shells : 0,
            agents: status == .background ? agents : 0,
            // The process, not the conversation: the pet stays the same after /clear.
            seed: stableHash("\(live.pid)-\(live.startedAt ?? 0)"))
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

    /// Lists the subagents folder at most every 5 seconds.
    private func agentCount(_ transcript: URL) -> Int {
        if let cached = agentCounts[transcript], Date().timeIntervalSince(cached.checked) < 5 { return cached.count }
        let count = runningAgents(of: transcript)
        agentCounts[transcript] = (Date(), count)
        return count
    }

    /// Reads only what the transcript gained since the last look.
    private func title(_ transcript: URL) -> String? {
        let size = (try? transcript.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        let cached = titles[transcript]
        if let cached, cached.size == size { return cached.title }
        let grewFrom = cached.flatMap { size > $0.size ? UInt64($0.size) : nil }
        let title = transcriptTitle(transcript, after: grewFrom) ?? cached?.title
        titles[transcript] = (size, title)
        return title
    }
}
