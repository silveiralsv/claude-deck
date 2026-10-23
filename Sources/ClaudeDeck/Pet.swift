import SwiftUI

/// Clawd, the Claude Code mascot, built from the same block glyphs and poses Claude Code prints in the terminal.
/// Each terminal cell becomes 2x4 pixels, and each quadrant of a glyph a 1x2 pixel block.
enum Clawd {
    enum Eyes { case open, left, right }
    enum Arms { case down, up, oneUp }

    static let width = 18
    static let height = 10

    // Quadrants: 0 top left, 1 top right, 2 bottom left, 3 bottom right.
    private static let quadrants: [Character: Set<Int>] = [
        " ": [], "█": [0, 1, 2, 3], "▐": [1, 3], "▌": [0, 2], "▀": [0, 1], "▄": [2, 3],
        "▖": [2], "▗": [3], "▘": [0], "▝": [1], "▛": [0, 1, 2], "▜": [0, 1, 3], "▟": [1, 2, 3], "▙": [0, 2, 3],
    ]
    // Row 0 left, row 0 right, row 1 left, row 1 right.
    private static let armGlyphs: [Arms: [String]] = [
        .down: [" ▐", "", "▝▜", "█▀"],
        .up: ["▗▟", "▄", " ▜", "█▘"],
        .oneUp: [" ▐", "▄", "▝▜", "█▘"],
    ]
    private static let eyeGlyphs: [Eyes: String] = [.open: "▛███▛█", .left: "▟███▟█", .right: "█▟███▟"]
    private static let feet = " ▝▝   ▝▝ "

    /// Rows of "#" body, "x" eye and "." empty.
    static func pixels(eyes: Eyes, arms: Arms) -> [[Character]] {
        var grid = Array(repeating: Array(repeating: Character("."), count: width), count: 12)
        // In the eye row, Claude Code paints the empty quadrants dark: those are the eyes.
        func put(_ glyphs: String, column: Int, row: Int, darkGaps: Bool = false) {
            for (offset, glyph) in glyphs.enumerated() {
                let x = (column + offset) * 2
                let y = row * 4
                let filled = quadrants[glyph] ?? []
                for quadrant in 0..<4 where darkGaps || filled.contains(quadrant) {
                    let px = x + quadrant % 2
                    let py = y + quadrant / 2 * 2
                    grid[py][px] = filled.contains(quadrant) ? "#" : "x"
                    grid[py + 1][px] = grid[py][px]
                }
            }
        }
        let arm = armGlyphs[arms]!
        put(arm[0], column: 0, row: 0)
        put(eyeGlyphs[eyes]!, column: 2, row: 0, darkGaps: true)
        put(arm[1], column: 8, row: 0)
        put(arm[2], column: 0, row: 1)
        put("█████", column: 2, row: 1, darkGaps: true)
        put(arm[3], column: 7, row: 1)
        put(feet, column: 0, row: 2)
        return Array(grid.prefix(height))
    }
}

extension Clawd {
    static let menuBar = menuBarImage(arms: .down)
    static let menuBarAlert = menuBarImage(arms: .up)

    /// Clawd as a menu bar template image: macOS colors the body for a light or dark menu bar, and the eyes are holes.
    private static func menuBarImage(arms: Arms) -> NSImage {
        let rows = pixels(eyes: .open, arms: arms)
        let px = 1.5
        let image = NSImage(size: NSSize(width: Double(width) * px, height: Double(height) * px), flipped: true) { _ in
            // One path for all pixels: filled one by one, their antialiased edges leave a grid on a 1x display.
            let shape = NSBezierPath()
            for (y, row) in rows.enumerated() {
                for (x, pixel) in row.enumerated() where pixel == "#" {
                    shape.appendRect(NSRect(x: Double(x) * px, y: Double(y) * px, width: px, height: px))
                }
            }
            NSColor.black.setFill()
            shape.fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// Hats drawn above Clawd's head, 18 x 6 pixels.
/// "a" is an accent color, "w" white, "g" gold, "r" ruby, "k" dark.
enum Hat: CaseIterable {
    case none, party, cap, crown, topHat, bow, beanie

    var pixels: [String] {
        switch self {
        case .none: []
        case .party: [
            ".........w........",
            "........aaa.......",
            "........awa.......",
            ".......aaaaa......",
            ".......wwwww......",
            "......aaaaaaa.....",
        ]
        case .cap: [
            "..................",
            "..................",
            ".........w........",
            "......aaaaaaa.....",
            ".....aaaaaaaaa....",
            "....aaaaaaaaaaaaa.",
        ]
        case .crown: [
            "..................",
            "..................",
            "..................",
            "....g....g....g...",
            "....gg..ggg..gg...",
            "....ggrggrggrgg...",
        ]
        case .topHat: [
            "......kkkkkkk.....",
            "......kkkkkkk.....",
            "......kkkkkkk.....",
            "......aaaaaaa.....",
            "......kkkkkkk.....",
            "...kkkkkkkkkkkkk..",
        ]
        case .bow: [
            "..................",
            "..................",
            "..................",
            "......aa...aa.....",
            "......aaawaaa.....",
            "......aa...aa.....",
        ]
        case .beanie: [
            "..................",
            ".........w........",
            "........aaa.......",
            "......aaaaaaa.....",
            ".....aaaaaaaaa....",
            "....wwwwwwwwwww...",
        ]
        }
    }
}

/// The look of a session's pet: a body color from a palette picked for dark backgrounds, a hat and an accent color.
struct PetLook {
    private static let hexes: [Int] = [
        0xD97757, 0xF2A65A, 0xF5D547, 0xA3D65C, 0x4CC38A, 0x2EC4B6, 0x6FD3E8, 0x4FB3F6,
        0x5B8DEF, 0x8B7CF6, 0xB57EDC, 0xE879C6, 0xF28AA0, 0xC9A27E, 0x9AA5B1, 0xE3E3E3,
    ]
    static let palette: [Color] = hexes.map { hex in
        Color(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    let body: Color
    let accent: Color
    let hat: Hat

    init(seed: UInt64) {
        let index = Int(seed % 16)
        body = Self.palette[index]
        // 5 to 10 steps away in the palette, so the accent never matches the body.
        accent = Self.palette[(index + 5 + Int((seed >> 8) % 6)) % 16]
        hat = Hat.allCases[Int((seed >> 16) % UInt64(Hat.allCases.count))]
    }

    func color(_ pixel: Character) -> Color? {
        switch pixel {
        case "#": body
        case "x": .black
        case "a": accent
        case "w": .white
        case "g": Color(red: 0.96, green: 0.77, blue: 0.26)
        case "r": Color(red: 0.90, green: 0.28, blue: 0.30)
        case "k": Color(red: 0.29, green: 0.29, blue: 0.33)
        default: nil
        }
    }
}

/// The session's Clawd. Its color and hat are the session's; its pose is the status.
struct PetView: View {
    let status: Status
    let look: PetLook

    init(status: Status, seed: UInt64) {
        self.status = status
        look = PetLook(seed: seed)
    }

    private var step: Double { status == .background ? 1.2 : 0.4 }

    var body: some View {
        // A done pet doesn't move. Every pet redraw is a layout pass of the whole window, and blinking
        // done pets cost 2 to 4 points of CPU.
        if status == .done {
            sprite(at: .now)
        } else {
            // A plain timer, not the animation schedule, which wakes on every display refresh.
            TimelineView(.periodic(from: .now, by: step)) { sprite(at: $0.date) }
        }
    }

    private func sprite(at date: Date) -> some View {
        let frame = Int(date.timeIntervalSinceReferenceDate / step)
        let pose: (eyes: Clawd.Eyes, arms: Clawd.Arms) = switch status {
        case .working, .background: (frame % 2 == 0 ? .left : .right, .down)
        case .needsYou: (.open, frame % 2 == 0 ? .up : .oneUp)
        case .done: (.open, .down)
        }
        // The hat takes 6 rows, Clawd 10, and one spare row lets a working pet hop.
        let hop = status == .working && frame % 2 == 0 ? 0.0 : 1.0
        let hat = look.hat.pixels
        let clawd = Clawd.pixels(eyes: pose.eyes, arms: pose.arms)
        return Canvas { context, size in
            let px = size.width / Double(Clawd.width + 2)
            func draw(_ rows: [[Character]], top: Int) {
                for (y, row) in rows.enumerated() {
                    for (x, pixel) in row.enumerated() {
                        guard let color = look.color(pixel) else { continue }
                        let rect = CGRect(x: Double(x + 1) * px, y: (Double(top + y) + hop) * px, width: px, height: px)
                        context.fill(Path(rect), with: .color(color))
                    }
                }
            }
            draw(hat.map(Array.init), top: 6 - hat.count)
            draw(clawd, top: 6)
        }
        .frame(width: 60, height: 51)
        .overlay(alignment: .topTrailing) {
            if status == .needsYou {
                Text("!").font(.system(size: 18, weight: .black, design: .monospaced)).foregroundStyle(.red)
            }
        }
    }
}
