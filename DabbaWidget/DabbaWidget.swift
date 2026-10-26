import WidgetKit
import SwiftUI

/// The board as a widget, for the home screen (iPhone) and the desktop (Mac).
/// For now it shows the same sample blocks as the board in the app; it will
/// show real blocks once finished sessions become blocks.
/// Tapping opens Dabba on your page; "New note" opens a fresh page.
struct DabbaWidget: Widget {
    let kind = "DabbaBoard"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { _ in
            BoardWidgetView()
        }
        .configurationDisplayName("Board")
        .description("Your Dabba board, with a quick way to start a new note.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct Entry: TimelineEntry {
    let date: Date
}

/// The sample board never changes, so one entry is enough.
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry(date: .now)], policy: .never))
    }
}

// MARK: - View

struct BoardWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MiniBoard()
            if family != .systemSmall {
                HStack {
                    Spacer()
                    // Opens Dabba on a fresh page; your current one is kept.
                    Link(destination: URL(string: "dabba://new")!) {
                        Label("New note", systemImage: "plus")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(WidgetInk.muted)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .overlay(Capsule().strokeBorder(WidgetInk.hairline))
                    }
                }
            }
        }
        .widgetURL(URL(string: "dabba://page"))
        .containerBackground(for: .widget) { WidgetInk.paper }
    }
}

enum WidgetInk {
    static let paper = Color(light: 0xFFFFFF, dark: 0x141414)
    static let muted = Color(light: 0x6E6E6E, dark: 0x9A9A9A)
    static let hairline = Color(light: 0xE5E5E5, dark: 0x2E2E2E)
    static let cell = Color(light: 0xF2F2F2, dark: 0x1E1E1E)
    static let mark = Color(red: 0x22 / 255, green: 0x20 / 255, blue: 0x1C / 255)
}

// MARK: - The board, drawn small

/// The app's sample board, packed the same way: 12 columns, blocks placed
/// top-left first, a few drawn as pebbles. Only the rows in use are shown.
private struct MiniBoard: View {
    private static let columns = 12
    private static let blocks = SampleBlock.packed()
    private static let rows = (blocks.map { $0.row + $0.h }.max() ?? 6) + 1

    var body: some View {
        Canvas { context, size in
            let cols = CGFloat(Self.columns), rows = CGFloat(Self.rows)
            let gapRatio: CGFloat = 4 / 24
            let pitch = min(size.width / (cols + gapRatio * 0), size.height / rows)
            let gap = pitch * gapRatio / (1 + gapRatio)
            let cell = pitch - gap
            let origin = CGPoint(x: (size.width - pitch * cols + gap) / 2, y: 0)

            for row in 0..<Self.rows {
                for col in 0..<Self.columns {
                    let rect = CGRect(x: origin.x + CGFloat(col) * pitch, y: origin.y + CGFloat(row) * pitch,
                                      width: cell, height: cell)
                    context.fill(Path(roundedRect: rect, cornerRadius: cell * 0.12), with: .color(WidgetInk.cell))
                }
            }
            for block in Self.blocks {
                let rect = CGRect(x: origin.x + CGFloat(block.col) * pitch,
                                  y: origin.y + CGFloat(block.row) * pitch,
                                  width: CGFloat(block.w) * pitch - gap,
                                  height: CGFloat(block.h) * pitch - gap)
                let path = block.isPebble
                    ? Pebble.path(in: rect, seed: block.index)
                    : Path(roundedRect: rect, cornerRadius: cell * 0.12)
                context.fill(path, with: .color(block.color))
                if block.hasDot {
                    let dot = CGRect(x: rect.minX + cell * 0.2, y: rect.minY + cell * 0.2,
                                     width: cell * 0.2, height: cell * 0.2)
                    context.fill(Path(ellipseIn: block.isPebble ? dot.offsetBy(dx: rect.width / 2 - cell * 0.3,
                                                                              dy: rect.height / 2 - cell * 0.3) : dot),
                                 with: .color(WidgetInk.mark))
                }
            }
        }
    }
}

private struct SampleBlock {
    let index: Int
    var col = 0, row = 0
    let w: Int, h: Int
    let color: Color
    let isPebble: Bool
    let hasDot: Bool

    static let palette: [Color] = [0xE8BC5A, 0xD98A6A, 0x9DBF8E, 0x9EC1D9].map { Color(hex: $0) }

    static func packed() -> [SampleBlock] {
        let sizes = [(4, 3), (2, 2), (3, 2), (1, 1), (2, 3), (2, 1),
                     (3, 3), (1, 2), (2, 2), (3, 1), (1, 1), (2, 2)]
        let pebbles: Set<Int> = [1, 6, 11]
        var placed: [SampleBlock] = []
        var taken = Set<[Int]>()
        for (i, size) in sizes.enumerated() {
            var block = SampleBlock(index: i, w: size.0, h: size.1, color: palette[i % palette.count],
                                    isPebble: pebbles.contains(i), hasDot: i % 4 == 0)
            search: for row in 0..<40 {
                for col in 0...(12 - block.w) {
                    let cells = (col..<col + block.w).flatMap { x in (row..<row + block.h).map { [x, $0] } }
                    if cells.allSatisfy({ !taken.contains($0) }) {
                        block.col = col
                        block.row = row
                        taken.formUnion(cells)
                        break search
                    }
                }
            }
            placed.append(block)
        }
        return placed
    }
}

/// The same soft stone as the app's pebble blocks.
private enum Pebble {
    static func path(in rect: CGRect, seed: Int) -> Path {
        var state = UInt64(seed + 7) &* 2_654_435_761
        func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(1 << 53)
        }
        let k = 9
        let points: [CGPoint] = (0..<k).map { i in
            let angle = Double(i) / Double(k) * 2 * .pi + (next() * 0.3 - 0.15)
            let r = 0.40 + next() * 0.08
            return CGPoint(x: rect.minX + (0.5 + cos(angle) * r) * rect.width,
                           y: rect.minY + (0.5 + sin(angle) * r) * rect.height)
        }
        var path = Path()
        path.move(to: points[0])
        for i in 0..<k {
            let p0 = points[(i - 1 + k) % k], p1 = points[i]
            let p2 = points[(i + 1) % k], p3 = points[(i + 2) % k]
            path.addCurve(to: p2,
                          control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                          control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        path.closeSubpath()
        return path
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    /// Light/dark pair for the widget's own colors.
    init(light: UInt32, dark: UInt32) {
        #if os(macOS)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
        #else
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
        #endif
    }
}

#Preview(as: .systemMedium) {
    DabbaWidget()
} timeline: {
    Entry(date: .now)
}
