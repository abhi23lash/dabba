import SwiftUI
import SwiftData

/// Root of the app: always opens straight onto the live draft.
struct ContentView: View {
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<Session> { $0.finishedAt == nil },
           sort: \Session.createdAt, order: .reverse)
    private var drafts: [Session]

    @State private var showingSessions = false

    var body: some View {
        ZStack {
            Paper.paper.ignoresSafeArea()

            if let draft = drafts.first {
                PageView(session: draft) { finish(draft) }
                    .id(draft.id)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                showingSessions = true
            } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 15))
                    .foregroundStyle(Paper.inkMuted)
                    .padding(16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sessions")
        }
        .sheet(isPresented: $showingSessions) { SessionsView() }
        .tint(Paper.accent) // cursor and focus color
        .onAppear(perform: ensureDraft)
        .onChange(of: drafts.isEmpty) { _, isEmpty in
            if isEmpty { ensureDraft() }
        }
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
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Session.self, inMemory: true)
}
