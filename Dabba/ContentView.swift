import SwiftUI
import SwiftData

/// Root of the app: opens on the board. Write opens the live draft; the
/// corner button, or finishing a session, returns to the board.
struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    @Query(filter: #Predicate<Session> { $0.finishedAt == nil },
           sort: \Session.createdAt, order: .reverse)
    private var drafts: [Session]

    @State private var writing = false
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
            if phase != .active { try? context.save() }
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            try? context.save()
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

    private func ensureDraft() {
        guard drafts.isEmpty else { return }
        context.insert(Session())
    }

    private func finish(_ session: Session) {
        // Placeholder transition; the fold-into-a-block animation replaces it.
        withAnimation(.easeInOut(duration: 0.35)) {
            session.finishedAt = .now
            writing = false
        }
        finishedSessions += 1
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Session.self, inMemory: true)
}
