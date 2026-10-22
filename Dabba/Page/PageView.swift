import SwiftUI

/// The writing page: question at the top, free writing in the middle,
/// the landing pinned at the bottom as the destination.
///
/// Fields bind straight to the model, so SwiftData autosaves as you type and
/// nothing is lost if the app quits mid-session.
struct PageView: View {
    @Bindable var session: Session
    let onFinish: () -> Void

    @FocusState private var focus: Field?
    private enum Field { case question, landing }
    /// Bumped to move focus into the writing area (a native text view).
    @State private var textFocusRequest = 0
    /// The tangent note being written in, if any.
    @State private var openTangent: UUID?
    /// Where each tangent's mark is drawn, from the top of the writing area.
    @State private var markPositions: [UUID: CGFloat] = [:]

    /// Design decision: a session can only finish once it has landed.
    private var canFinish: Bool {
        !session.landing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            TextField("Question", text: $session.question, axis: .vertical)
                .font(Paper.question)
                .foregroundStyle(Paper.ink)
                .textFieldStyle(.plain)
                .lineLimit(1...3)
                .focused($focus, equals: .question)
                .onSubmit { textFocusRequest += 1 }

            writing

            Rectangle()
                .fill(Paper.hairline)
                .frame(height: 1)

            HStack(alignment: .firstTextBaseline, spacing: 16) {
                TextField("Landing", text: $session.landing, axis: .vertical)
                    .font(Paper.landing)
                    .foregroundStyle(Paper.ink)
                    .textFieldStyle(.plain)
                    .lineLimit(1...3)
                    .focused($focus, equals: .landing)

                Button("Finish", action: onFinish)
                    .buttonStyle(.plain)
                    .font(Paper.label)
                    .foregroundStyle(canFinish ? Paper.accent : Paper.inkMuted)
                    .disabled(!canFinish)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .frame(maxWidth: Paper.column)
        .padding(.horizontal, Paper.margin)
        .padding(.top, Paper.margin + 24) // clears the corner button
        .padding(.bottom, Paper.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            if session.question.isEmpty { focus = .question } else { textFocusRequest += 1 }
        }
    }

    /// No placeholder: the empty page is the invitation. Selected text that
    /// gets deleted is struck through instead (see `Strike`). On the Mac,
    /// tangents sit in a column to the right of the writing.
    private var writing: some View {
        PageTextView(text: $session.text, struck: $session.struck,
                     focusRequest: textFocusRequest, tangents: tangentHooks)
            #if os(macOS)
            .overlay(alignment: .topTrailing) {
                if !(session.tangents ?? []).isEmpty {
                    TangentColumn(tangents: session.tangents ?? [], marks: markPositions,
                                  open: $openTangent, onClose: closeTangent)
                        .offset(x: TangentColumn.width + Paper.margin)
                }
            }
            #endif
    }

    private var tangentHooks: TangentHooks {
        TangentHooks(
            saved: (session.tangents ?? []).map {
                TangentAnchor(id: $0.id, mark: $0.mark, anchor: $0.anchor)
            },
            branch: { picked, location in
                let number = ((session.tangents ?? []).map(\.number).max() ?? 0) + 1
                let tangent = Tangent(number: number, text: picked, anchor: location)
                session.tangents = (session.tangents ?? []) + [tangent]
                // Nothing selected: the tangent opens so you can follow it now.
                // Text selected: it's parked, and you keep writing.
                if picked.isEmpty { openTangent = tangent.id }
                return (tangent.id, tangent.mark)
            },
            open: { openTangent = $0 },
            moved: { anchors in
                for tangent in session.tangents ?? [] {
                    if let anchor = anchors[tangent.id], anchor != tangent.anchor {
                        tangent.anchor = anchor
                    }
                }
            },
            onScreen: { markPositions = $0 }
        )
    }

    /// Back to the main text, exactly where you were.
    private func closeTangent() {
        openTangent = nil
        textFocusRequest += 1
    }
}
