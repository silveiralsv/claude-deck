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
        case .working: "trabalhando"
        case .done: "terminou"
        case .needsYou: "precisa de você"
        }
    }

    var color: Color {
        switch self {
        case .working: Color(red: 0.85, green: 0.47, blue: 0.34)
        case .done: .green
        case .needsYou: .red
        }
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
                Text("\(store.sessions.count) sessões").foregroundStyle(.secondary)
            }
            if store.sessions.isEmpty {
                Text("Nenhuma sessão do Claude rodando.").foregroundStyle(.secondary)
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
                Button(deckVisible ? "Esconder deck" : "Exibir deck") {
                    if deckVisible { dismissWindow(id: "deck") } else { openWindow(id: "deck") }
                }
                Button("Instalar hooks") {
                    do {
                        let changed = try HookInstaller.install()
                        message = changed.isEmpty ? "Hooks já instalados." : "Hooks instalados."
                    } catch {
                        message = error.localizedDescription
                    }
                }
                if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("Sair") { NSApp.terminate(nil) }
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
            PetView(status: session.status)
            Text(session.name).font(.caption.bold()).lineLimit(1)
            Text("\(session.account) · \(URL(fileURLWithPath: session.cwd).lastPathComponent)")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            Text(session.status.label).font(.caption2.bold()).foregroundStyle(session.status.color)
            Button("Abrir terminal") { error = TerminalFocus.focus(pid: session.pid) }
                .controlSize(.small)
            if let error { Text(error).font(.caption2).foregroundStyle(.red) }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 8).fill(session.status.color.opacity(0.12)))
        .help(session.cwd)
    }
}

/// A 12x12 pixel blob with two eyes. "#" is body, "o" is white, "x" is black.
struct PetView: View {
    let status: Status

    private static let lookRight = [
        "....####....",
        "..########..",
        ".##########.",
        ".##########.",
        "###oo##oo###",
        "###ox##ox###",
        "###oo##oo###",
        "############",
        ".##########.",
        ".##########.",
        "..########..",
        "....####....",
    ]
    private static let lookLeft = lookRight.enumerated().map { $0.offset == 5 ? "###xo##xo###" : $0.element }
    private static let happy = [
        "....####....",
        "..########..",
        ".##########.",
        ".##########.",
        "###x####x###",
        "##x#x##x#x##",
        "############",
        "####x##x####",
        ".####xx####.",
        ".##########.",
        "..########..",
        "....####....",
    ]
    private static let alarmed = [
        "....####....",
        "..########..",
        ".##########.",
        ".##########.",
        "##ooo##ooo##",
        "##oxo##oxo##",
        "##ooo##ooo##",
        "############",
        ".####xx####.",
        ".####xx####.",
        "..########..",
        "....####....",
    ]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.4)) { context in
            let frame = Int(context.date.timeIntervalSinceReferenceDate / 0.4)
            let art = switch status {
            case .working: frame % 2 == 0 ? Self.lookRight : Self.lookLeft
            case .done: Self.happy
            case .needsYou: Self.alarmed
            }
            // One spare pixel on each side leaves room to bounce (working) and shake (needs you).
            let dx = status == .needsYou ? (frame % 2 == 0 ? 0.0 : 2.0) : 1.0
            let dy = status == .working && frame % 2 == 0 ? 0.0 : 1.0
            Canvas { ctx, size in
                let px = size.width / 14
                for (y, row) in art.enumerated() {
                    for (x, char) in row.enumerated() {
                        let color: Color? = switch char {
                        case "#": status.color
                        case "o": .white
                        case "x": .black
                        default: nil
                        }
                        guard let color else { continue }
                        let rect = CGRect(x: (Double(x) + dx) * px, y: (Double(y) + dy) * px, width: px, height: px)
                        ctx.fill(Path(rect), with: .color(color))
                    }
                }
            }
            .frame(width: 56, height: 56)
            .overlay(alignment: .topTrailing) {
                if status == .needsYou {
                    Text("!").font(.system(size: 18, weight: .black, design: .monospaced)).foregroundStyle(.red)
                }
            }
        }
    }
}
