import SwiftUI
import SwiftData

/// Finished sessions, newest first: a small, plain list until the board's
/// meaning is decided. Opening one shows it exactly as it was written.
struct SessionsView: View {
    /// Back to the page.
    let onClose: () -> Void

    @Query(filter: #Predicate<Session> { $0.finishedAt != nil },
           sort: \Session.finishedAt, order: .reverse)
    private var sessions: [Session]

    /// Unfinished sessions; the first is the current page, so it's left out.
    @Query(filter: #Predicate<Session> { $0.finishedAt == nil },
           sort: \Session.lastOpenedAt, order: .reverse)
    private var drafts: [Session]
    private var unfinished: [Session] { Array(drafts.dropFirst()).filter(\.hasWriting) }

    @State private var reading: Session?

    var body: some View {
        ZStack {
            Paper.paper.ignoresSafeArea()
            if let session = reading {
                SessionReadView(session: session) {
                    withAnimation(.easeInOut(duration: 0.2)) { reading = nil }
                }
                .transition(.opacity)
            } else {
                list.transition(.opacity)
            }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sessions")
                    .font(Paper.question)
                    .foregroundStyle(Paper.ink)
                Spacer()
                Button("Page", action: onClose)
                    .buttonStyle(.plain)
                    .font(Paper.label)
                    .foregroundStyle(Paper.inkMuted)
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.bottom, 20)

            if sessions.isEmpty && unfinished.isEmpty {
                Text("Finished sessions show up here.")
                    .font(Paper.page)
                    .foregroundStyle(Paper.inkMuted)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if !unfinished.isEmpty {
                            sectionLabel("Unfinished")
                            ForEach(unfinished) { session in
                                // Opening one makes it your page again.
                                SessionRow(session: session) {
                                    session.lastOpenedAt = .now
                                    onClose()
                                }
                                Rectangle().fill(Paper.hairline).frame(height: 1)
                            }
                            if !sessions.isEmpty { sectionLabel("Finished").padding(.top, 20) }
                        }
                        ForEach(sessions) { session in
                            SessionRow(session: session) {
                                withAnimation(.easeInOut(duration: 0.2)) { reading = session }
                            }
                            Rectangle().fill(Paper.hairline).frame(height: 1)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: Paper.column)
        .padding(.horizontal, Paper.margin)
        .padding(.top, Paper.margin + 24)
        .padding(.bottom, Paper.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private func sectionLabel(_ text: String) -> some View {
    Text(text)
        .font(Paper.label)
        .foregroundStyle(Paper.inkMuted)
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
}

/// One session: its landing (or question, or last line if unfinished), then mode and date.
private struct SessionRow: View {
    let session: Session
    let onOpen: () -> Void

    @State private var hovering = false

    private var title: String {
        let landing = session.landing.trimmingCharacters(in: .whitespacesAndNewlines)
        if session.isFinished, !landing.isEmpty { return landing }
        let question = session.question.trimmingCharacters(in: .whitespacesAndNewlines)
        if !question.isEmpty { return question }
        // An unfinished page with no question: its last line, in your words.
        let last = session.text.split(separator: "\n").last.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return last.isEmpty ? "Untitled" : last
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Paper.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Text(session.mode.name)
                    Text("·")
                    Text(session.finishedAt ?? session.lastOpenedAt,
                         format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                }
                .font(Paper.label)
                .foregroundStyle(Paper.inkMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .padding(.horizontal, 10)
            .background(hovering ? Paper.hairline.opacity(0.5) : .clear,
                        in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// A finished session, read-only and laid out like the page it was written
/// on: question, writing with struck text and model boxes, side notes beside
/// it on the Mac, and the landing.
struct SessionReadView: View {
    let session: Session
    let onBack: () -> Void

    @State private var markPositions: [UUID: CGFloat] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Button(action: onBack) {
                    Label("Sessions", systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .font(Paper.label)
                .foregroundStyle(Paper.inkMuted)
                .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Text(session.finishedAt ?? session.createdAt,
                     format: .dateTime.weekday(.wide).day().month(.wide).hour().minute())
                    .font(Paper.label)
                    .foregroundStyle(Paper.inkMuted)
            }

            Text(session.question.isEmpty ? "Untitled" : session.question)
                .font(Paper.question)
                .foregroundStyle(Paper.ink)
                .textSelection(.enabled)

            writing

            Rectangle().fill(Paper.hairline).frame(height: 1)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if !session.mode.landingStem.isEmpty {
                    Text(session.mode.landingStem)
                        .font(Paper.landing)
                        .foregroundStyle(Paper.ink)
                }
                Text(session.landing)
                    .font(Paper.landing)
                    .foregroundStyle(Paper.ink)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: Paper.column)
        .padding(.horizontal, Paper.margin)
        .padding(.top, Paper.margin + 24)
        .padding(.bottom, Paper.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The same native text view as the page, not editable, so struck text,
    /// model boxes and the decision tree look exactly as they did.
    private var writing: some View {
        PageTextView(
            text: .constant(session.text),
            struck: .constant(session.struck),
            focusRequest: 0,
            tangents: TangentHooks(
                saved: (session.tangents ?? []).map {
                    TangentAnchor(id: $0.id, mark: $0.mark, anchor: $0.anchor)
                },
                onScreen: { markPositions = $0 }),
            models: ModelHooks(
                saved: session.orderedSteps.filter { $0.method != .catchAll }.map {
                    HeadingAnchor(id: $0.id, method: $0.method, anchor: $0.anchor, end: $0.endAnchor)
                }),
            readOnly: true
        )
        #if os(macOS)
        .overlay(alignment: .topTrailing) {
            if !(session.tangents ?? []).isEmpty {
                TangentColumn(tangents: session.tangents ?? [], marks: markPositions,
                              open: .constant(nil), onClose: {}, onRemove: { _ in },
                              readOnly: true)
                    .offset(x: TangentColumn.width + Paper.margin)
            }
        }
        #endif
    }
}
