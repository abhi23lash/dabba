import SwiftUI

/// The column beside the page where tangents live as small notes, each level
/// with its mark in the main text. Notes never overlap: one that would
/// collide is pushed down below the one above it.
struct TangentColumn: View {
    let tangents: [Tangent]
    /// Mark positions from the text view, from the top of the writing area.
    let marks: [UUID: CGFloat]
    @Binding var open: UUID?
    let onClose: () -> Void
    let onRemove: (Tangent) -> Void
    /// Past sessions: notes can be read, not opened or removed.
    var readOnly = false

    static let width: CGFloat = 220
    private let collapsed: CGFloat = 64
    private let expanded: CGFloat = 220
    private let gap: CGFloat = 8

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(placed, id: \.tangent.id) { item in
                TangentNote(tangent: item.tangent,
                            isOpen: open == item.tangent.id,
                            onOpen: { open = item.tangent.id },
                            onClose: onClose,
                            onRemove: { onRemove(item.tangent) },
                            readOnly: readOnly)
                    .frame(width: Self.width,
                           height: open == item.tangent.id ? expanded : collapsed,
                           alignment: .topLeading)
                    .offset(y: item.y)
            }
        }
        .frame(width: Self.width, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .animation(.easeOut(duration: 0.2), value: open)
        .animation(.easeOut(duration: 0.15), value: marks)
    }

    /// Notes in mark order. A tangent whose mark was deleted keeps its note,
    /// placed after the others.
    private var placed: [(tangent: Tangent, y: CGFloat)] {
        let ordered = tangents.sorted { a, b in
            switch (marks[a.id], marks[b.id]) {
            case let (ya?, yb?): return ya < yb
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return a.number < b.number
            }
        }
        var result: [(Tangent, CGFloat)] = []
        var nextFree: CGFloat = 0
        for tangent in ordered {
            let y = max(marks[tangent.id] ?? nextFree, nextFree)
            result.append((tangent, y))
            nextFree = y + (open == tangent.id ? expanded : collapsed) + gap
        }
        return result
    }
}

/// One tangent. Collapsed it shows the start of the thought; open, you write in it.
private struct TangentNote: View {
    @Bindable var tangent: Tangent
    let isOpen: Bool
    let onOpen: () -> Void
    let onClose: () -> Void
    let onRemove: () -> Void
    var readOnly = false

    @FocusState private var focused: Bool
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(tangent.mark)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Paper.inkMuted)
                Spacer()
                if isOpen {
                    Button("Remove", action: onRemove)
                        .buttonStyle(.plain)
                        .font(Paper.label)
                        .foregroundStyle(Paper.inkMuted)
                    Button("Back  ⌘[", action: onClose)
                        .buttonStyle(.plain)
                        .font(Paper.label)
                        .foregroundStyle(Paper.inkMuted)
                        .keyboardShortcut("[", modifiers: .command)
                } else if hovering && !readOnly {
                    // Hover a note to remove it.
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Paper.inkMuted)
                            .padding(2)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Remove this note")
                    .accessibilityLabel("Remove note \(tangent.mark)")
                }
            }

            if isOpen {
                TextEditor(text: $tangent.text)
                    .font(.system(size: 15))
                    .foregroundStyle(Paper.ink)
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    #if os(macOS)
                    .onExitCommand(perform: onClose)   // Escape
                    #endif
            } else {
                Text(tangent.text.isEmpty ? " " : tangent.text)
                    .font(.system(size: 13))
                    .foregroundStyle(Paper.ink)
                    .lineLimit(readOnly ? 3 : 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Paper.note(tangent.number), in: RoundedRectangle(cornerRadius: 6))
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture { if !isOpen && !readOnly { onOpen() } }
        .onHover { hovering = $0 }
        .onChange(of: isOpen, initial: true) { _, open in
            if open { DispatchQueue.main.async { focused = true } }
        }
    }
}
