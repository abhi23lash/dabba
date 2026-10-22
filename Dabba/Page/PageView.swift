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
    private enum Field { case question, text, landing }

    /// Design decision: a session can only finish once it has landed.
    private var canFinish: Bool {
        !session.landing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            TextField("What are you thinking about?", text: $session.question, axis: .vertical)
                .font(Paper.question)
                .foregroundStyle(Paper.ink)
                .textFieldStyle(.plain)
                .lineLimit(1...3)
                .focused($focus, equals: .question)
                .onSubmit { focus = .text }

            writing

            Rectangle()
                .fill(Paper.hairline)
                .frame(height: 1)

            HStack(alignment: .firstTextBaseline, spacing: 16) {
                TextField("What do I think now?", text: $session.landing, axis: .vertical)
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
        .task { focus = session.question.isEmpty ? .question : .text }
    }

    private var writing: some View {
        ZStack(alignment: .topLeading) {
            if session.text.isEmpty {
                // Approximates TextEditor's internal text inset.
                Text("Write. Don't fix anything yet.")
                    .font(Paper.page)
                    .foregroundStyle(Paper.inkMuted)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $session.text)
                .font(Paper.page)
                .foregroundStyle(Paper.ink)
                .lineSpacing(8)
                .scrollContentBackground(.hidden)
                .focused($focus, equals: .text)
                #if os(iOS)
                .autocorrectionDisabled()
                #endif
        }
    }
}
