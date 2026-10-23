import SwiftUI

@main
struct ClaudeDeckApp: App {
    @State private var store = SessionStore()
    @AppStorage("deckVisible") private var deckVisible = false

    init() {
        guard CommandLine.arguments.contains("--install-hooks") else { return }
        do {
            let changed = try HookInstaller.install()
            print(changed.isEmpty ? "Hooks already installed." : "Hooks added to:\n" + changed.joined(separator: "\n"))
            exit(0)
        } catch {
            fputs("Hook install failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            DeckView(store: store)
        } label: {
            let waiting = store.sessions.filter { $0.status == .needsYou }.count
            if waiting > 0 {
                Image(systemName: "exclamationmark.bubble.fill")
                Text("\(waiting)")
            } else {
                Image(systemName: "square.grid.2x2")
            }
        }
        .menuBarExtraStyle(.window)

        // The same deck as a window that stays open above other apps.
        Window("Claude Deck", id: "deck") {
            DeckView(store: store)
                .onAppear { deckVisible = true }
                .onDisappear { deckVisible = false }
        }
        .windowResizability(.contentSize)
        .windowLevel(.floating)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(deckVisible ? .presented : .suppressed)
    }
}

extension Status {
    var label: String {
        switch self {
        case .working: String(localized: "working")
        case .background: String(localized: "in background")
        case .done: String(localized: "done")
        case .needsYou: String(localized: "needs you")
        }
    }

    var color: Color {
        switch self {
        case .working: Color(red: 0.85, green: 0.47, blue: 0.34)
        case .background: Color(red: 0.35, green: 0.55, blue: 0.95)
        case .done: .green
        case .needsYou: .red
        }
    }
}

extension Session {
    /// "5 shells · 1 agent": what still runs in the background.
    var activity: String {
        var parts: [String] = []
        if shells > 0 { parts.append(shells == 1 ? String(localized: "1 shell") : String(localized: "\(shells) shells")) }
        if agents > 0 { parts.append(agents == 1 ? String(localized: "1 agent") : String(localized: "\(agents) agents")) }
        return parts.joined(separator: " · ")
    }
}

struct DeckView: View {
    let store: SessionStore
    @State private var message: String?
    @State private var gridHeight: CGFloat = 0
    @AppStorage("deckVisible") private var deckVisible = false
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    private var rows: [[Session]] {
        let all = store.sessions
        return stride(from: 0, to: all.count, by: 3).map { Array(all[$0..<min($0 + 3, all.count)]) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Claude Deck").font(.headline)
                Spacer()
                let count = store.sessions.count
                Text(count == 1 ? LocalizedStringKey("1 session") : "\(count) sessions").foregroundStyle(.secondary)
            }
            if store.sessions.isEmpty {
                Text("No Claude sessions running.").foregroundStyle(.secondary)
            } else {
                // A menu bar window sizes to its content, and a ScrollView there collapses to zero height.
                // So the measured height of the grid sets the height of the scroll view, up to most of the screen.
                ScrollView {
                    Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                        ForEach(rows.indices, id: \.self) { index in
                            GridRow { ForEach(rows[index]) { SessionCard(session: $0) } }
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { gridHeight = $0 }
                }
                .frame(height: min(gridHeight, (NSScreen.main?.visibleFrame.height ?? 800) * 0.8))
            }
            Divider()
            HStack {
                Button(deckVisible ? LocalizedStringKey("Hide deck") : "Show deck") {
                    if deckVisible { dismissWindow(id: "deck") } else { openWindow(id: "deck") }
                }
                Button("Install hooks") {
                    do {
                        let changed = try HookInstaller.install()
                        message = changed.isEmpty ? String(localized: "Hooks already installed.") : String(localized: "Hooks installed.")
                    } catch {
                        message = error.localizedDescription
                    }
                }
                if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(12)
        .frame(width: 500)
    }
}

struct SessionCard: View {
    let session: Session
    @State private var error: String?

    var body: some View {
        VStack(spacing: 4) {
            PetView(status: session.status, seed: session.seed)
            Text(session.title ?? session.name)
                .font(.caption.bold())
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
            Text("\(session.account) · \(URL(fileURLWithPath: session.cwd).lastPathComponent)")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            Text(session.status.label).font(.caption2.bold()).foregroundStyle(session.status.color)
            // Every card keeps this line, empty or not, so all cards in a row have the same height.
            Text(session.activity)
                .font(.caption2).foregroundStyle(session.status.color)
                .lineLimit(1, reservesSpace: true)
            Button("Open terminal") { error = TerminalFocus.focus(pid: session.pid) }
                .controlSize(.small)
            if let error { Text(error).font(.caption2).foregroundStyle(.red) }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 8).fill(session.status.color.opacity(0.12)))
        .overlay {
            if session.status == .needsYou {
                RoundedRectangle(cornerRadius: 8).strokeBorder(.red, lineWidth: 2)
            }
        }
        .help("\(session.title ?? session.name)\n\(session.name) · \(session.cwd)")
    }
}
