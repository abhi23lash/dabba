import SwiftUI

/// SPIKE (throwaway): a board of sample blocks to feel out drag-and-place.
/// Not wired to sessions yet. Positions live in memory and reset on close.
struct BoardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var blocks = BoardBlock.samples(columns: Board.columns)
    @State private var dragging: UUID?
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Board")
                    .font(Paper.label)
                    .foregroundStyle(Paper.inkMuted)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
                    .font(Paper.label)
                    .foregroundStyle(Paper.ink)
            }
            .frame(width: Board.width)

            board
            Spacer(minLength: 0)
        }
        .padding(.top, Paper.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Paper.paper.ignoresSafeArea())
        #if os(macOS)
        .frame(minWidth: Board.width + 2 * Paper.margin,
               minHeight: Board.height + 120)
        #endif
    }

    private var board: some View {
        ZStack(alignment: .topLeading) {
            grid

            if let id = dragging, let block = blocks.first(where: { $0.id == id }) {
                let target = target(for: block)
                if isFree(target, ignoring: id) {
                    RoundedRectangle(cornerRadius: Board.radius)
                        .strokeBorder(Paper.inkMuted, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .frame(width: target.pixelWidth, height: target.pixelHeight)
                        .offset(x: target.x, y: target.y)
                }
            }

            ForEach(blocks) { block in
                let isDragging = dragging == block.id
                BlockView(block: block)
                    .frame(width: block.pixelWidth, height: block.pixelHeight)
                    .scaleEffect(isDragging ? 1.04 : 1)
                    .shadow(color: .black.opacity(isDragging ? 0.18 : 0), radius: 10, y: 6)
                    .offset(x: block.x + (isDragging ? dragOffset.width : 0),
                            y: block.y + (isDragging ? dragOffset.height : 0))
                    .zIndex(isDragging ? 1 : 0)
                    .gesture(drag(block))
            }
        }
        .frame(width: Board.width, height: Board.height, alignment: .topLeading)
    }

    /// Faint cells so the writer can see where things will snap.
    private var grid: some View {
        Canvas { context, _ in
            for row in 0..<Board.rows {
                for col in 0..<Board.columns {
                    let rect = CGRect(x: CGFloat(col) * Board.pitch, y: CGFloat(row) * Board.pitch,
                                      width: Board.cell, height: Board.cell)
                    context.fill(Path(roundedRect: rect, cornerRadius: Board.radius),
                                 with: .color(Paper.hairline.opacity(0.45)))
                }
            }
        }
        .frame(width: Board.width, height: Board.height)
        .allowsHitTesting(false)
    }

    // MARK: Dragging

    private func drag(_ block: BoardBlock) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragging == nil {
                    withAnimation(motion(0.18)) { dragging = block.id }
                }
                dragOffset = value.translation
            }
            .onEnded { _ in drop(block.id) }
    }

    private func drop(_ id: UUID) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        let target = target(for: blocks[index])
        withAnimation(motion(0.3)) {
            if isFree(target, ignoring: id) {
                blocks[index].col = target.col
                blocks[index].row = target.row
            }
            // Not free: the block settles back where it came from.
            dragOffset = .zero
            dragging = nil
        }
    }

    /// Where `block` would land if dropped now: nearest cell, kept on the board.
    private func target(for block: BoardBlock) -> BoardBlock {
        var moved = block
        moved.col = min(max(block.col + Int((dragOffset.width / Board.pitch).rounded()), 0),
                        Board.columns - block.w)
        moved.row = min(max(block.row + Int((dragOffset.height / Board.pitch).rounded()), 0),
                        Board.rows - block.h)
        return moved
    }

    private func isFree(_ block: BoardBlock, ignoring id: UUID) -> Bool {
        !blocks.contains { $0.id != id && $0.overlaps(block) }
    }

    /// Slow and settled, never bouncy. Reduce Motion gets a quick ease.
    private func motion(_ duration: Double) -> Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: duration)
    }
}

// MARK: - Geometry

enum Board {
    static let cell: CGFloat = 24
    static let gap: CGFloat = 4
    static let pitch = cell + gap
    static let radius: CGFloat = 3
    static let columns = 12
    static let rows = 20
    static let width = CGFloat(columns) * pitch - gap
    static let height = CGFloat(rows) * pitch - gap
}

// MARK: - Block

enum BlockMark { case dot, bar, notch, ring }

struct BoardBlock: Identifiable {
    let id = UUID()
    var col: Int
    var row: Int
    let w: Int
    let h: Int
    let color: Color
    let marks: [BlockMark]
    let line: String

    var x: CGFloat { CGFloat(col) * Board.pitch }
    var y: CGFloat { CGFloat(row) * Board.pitch }
    var pixelWidth: CGFloat { CGFloat(w) * Board.pitch - Board.gap }
    var pixelHeight: CGFloat { CGFloat(h) * Board.pitch - Board.gap }

    func overlaps(_ other: BoardBlock) -> Bool {
        col < other.col + other.w && other.col < col + w &&
        row < other.row + other.h && other.row < row + h
    }

    // Provisional placeholder palette from CLAUDE.md; not final.
    static let palette: [Color] = [
        Color(light: 0xE8BC5A, dark: 0xE8BC5A), // turmeric
        Color(light: 0xD98A6A, dark: 0xD98A6A), // terracotta
        Color(light: 0x9DBF8E, dark: 0x9DBF8E), // leaf
        Color(light: 0x9EC1D9, dark: 0x9EC1D9), // sky
    ]

    /// A dozen sample blocks packed top-left first, leaving open board below.
    static func samples(columns: Int) -> [BoardBlock] {
        let sizes = [(4, 3), (2, 2), (3, 2), (1, 1), (2, 3), (2, 1),
                     (3, 3), (1, 2), (2, 2), (3, 1), (1, 1), (2, 2)]
        let markSets: [[BlockMark]] = [[.dot], [.bar], [.ring], [.notch],
                                       [.dot, .bar], [.ring, .notch], [], [.dot]]
        let lines = ["My next step is to call her.", "The one thing is sleep.",
                     "I'm choosing the smaller flat.", "Ship it Friday.",
                     "What I actually feel is tired, not stuck."]

        var placed: [BoardBlock] = []
        for (i, size) in sizes.enumerated() {
            var block = BoardBlock(col: 0, row: 0, w: size.0, h: size.1,
                                   color: palette[i % palette.count],
                                   marks: markSets[i % markSets.count],
                                   line: lines[i % lines.count])
            search: for row in 0..<100 {
                for col in 0...(columns - block.w) {
                    block.col = col
                    block.row = row
                    if !placed.contains(where: { $0.overlaps(block) }) { break search }
                }
            }
            placed.append(block)
        }
        return placed
    }
}

struct BlockView: View {
    let block: BoardBlock

    private static let markInk = Color(light: 0x22201C, dark: 0x22201C)

    var body: some View {
        RoundedRectangle(cornerRadius: Board.radius)
            .fill(block.color)
            .overlay(alignment: .topLeading) {
                if block.marks.contains(.dot) {
                    Circle().fill(Self.markInk).frame(width: 5, height: 5).padding(5)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if block.marks.contains(.bar) {
                    Capsule().fill(Self.markInk).frame(width: 12, height: 3).padding(5)
                }
            }
            .overlay(alignment: .topTrailing) {
                if block.marks.contains(.notch) {
                    Rectangle().fill(Paper.paper).frame(width: 7, height: 7)
                }
            }
            .overlay {
                if block.marks.contains(.ring) {
                    Circle().strokeBorder(Self.markInk, lineWidth: 1.5).frame(width: 9, height: 9)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(block.line)
    }
}

#Preview {
    BoardView()
}
