import SwiftUI
import SwiftData

/// Root of the app: opens straight onto the live draft, cursor ready. The
/// corner buttons open the board (the dabba) and the list of finished
/// sessions; finishing a session gives you a fresh page.
struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    /// Unfinished sessions, the current page first (the one opened most recently).
    @Query(filter: #Predicate<Session> { $0.finishedAt == nil },
           sort: \Session.lastOpenedAt, order: .reverse)
    private var drafts: [Session]

    private enum Screen { case page, board, sessions }
    @State private var screen: Screen = .page
    /// Counts finished sessions; early ones get a faint "type /" hint.
    @AppStorage("finishedSessions") private var finishedSessions = 0

    var body: some View {
        ZStack {
            Paper.paper.ignoresSafeArea()

            switch screen {
            case .page:
                if let draft = drafts.first {
                    PageView(session: draft) { finish(draft) }
                        .id(draft.id)
                        .overlay(alignment: .topTrailing) { cornerButtons }
                        .transition(.opacity)
                }
            case .board:
                BoardView { show(.page) }
                    .transition(.opacity)
            case .sessions:
                SessionsView { show(.page) }
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
        // The widget: "dabba://page" opens your page, "dabba://new" a fresh one.
        .onOpenURL { url in
            if url.host() == "new" { newPage() }
            show(.page)
        }
        .onAppear(perform: ensureDraft)
        .onChange(of: drafts.isEmpty) { _, isEmpty in
            if isEmpty { ensureDraft() }
        }
    }

    /// From the page: your finished sessions, and the board.
    private var cornerButtons: some View {
        HStack(spacing: 0) {
            cornerButton("list.bullet", label: "Sessions") { show(.sessions) }
            cornerButton("square.grid.2x2", label: "Board") { show(.board) }
        }
    }

    private func cornerButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(Paper.inkMuted)
                .padding(.vertical, 16)
                .padding(.horizontal, 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    private func show(_ next: Screen) {
        withAnimation(.easeInOut(duration: 0.25)) { screen = next }
    }

    /// Saves the database and the draft's Markdown copy.
    private func saveNow() {
        try? context.save()
        #if os(macOS)
        if let draft = drafts.first { FileMirror.write(draft) }
        #endif
    }

    /// A fresh page. If the current one has writing, it's kept as unfinished
    /// (it shows at the top of Sessions); an empty page is just reused.
    private func newPage() {
        guard let current = drafts.first, current.hasWriting else { return }
        saveNow()
        context.insert(Session())
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
