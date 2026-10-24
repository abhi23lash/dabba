import SwiftUI
import SwiftData

/// Root of the app: opens straight onto the live draft, cursor ready. The
/// board is one click away (corner button) and never required; finishing a
/// session gives you a fresh page.
struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    @Query(filter: #Predicate<Session> { $0.finishedAt == nil },
           sort: \Session.createdAt, order: .reverse)
    private var drafts: [Session]

    @State private var writing = true
    /// Counts finished sessions; early ones get a faint "type /" hint.
    @AppStorage("finishedSessions") private var finishedSessions = 0

    var body: some View {
        ZStack {
            Paper.paper.ignoresSafeArea()

            if writing, let draft = drafts.first {
                PageView(session: draft) { finish(draft) }
                    .id(draft.id)
                    .overlay(alignment: .topTrailing) { boardButton }
                    .transition(.opacity)
            } else {
                BoardView { withAnimation(.easeInOut(duration: 0.25)) { writing = true } }
                    .transition(.opacity)
            }
        }
        .tint(Paper.accent) // cursor and focus color
        // Save the moment Dabba goes to the background or quits.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { saveNow() }
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            saveNow()
        }
        .task {
            // First launch with local files: ask once where to keep them.
            try? await Task.sleep(for: .seconds(0.6))
            FileMirror.askOnceIfNeeded()
        }
        #endif
        .onAppear(perform: ensureDraft)
        .onChange(of: drafts.isEmpty) { _, isEmpty in
            if isEmpty { ensureDraft() }
        }
    }

    /// Back to the board from the page.
    private var boardButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { writing = false }
        } label: {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 15))
                .foregroundStyle(Paper.inkMuted)
                .padding(16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Board")
    }

    /// Saves the database and the draft's Markdown copy.
    private func saveNow() {
        try? context.save()
        #if os(macOS)
        if let draft = drafts.first { FileMirror.write(draft) }
        #endif
    }

    private func ensureDraft() {
        guard drafts.isEmpty else { return }
        context.insert(Session())
    }

    private func finish(_ session: Session) {
        // Placeholder transition; the fold-into-a-block animation replaces it.
        withAnimation(.easeInOut(duration: 0.35)) {
            session.finishedAt = .now
        }
        try? context.save()
        #if os(macOS)
        FileMirror.write(session)   // its file records when it finished
        #endif
        finishedSessions += 1
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Session.self, inMemory: true)
}
