import SwiftUI
import SwiftData

/// Finished sessions, newest first. A plain list for now; the board replaces it.
struct SessionsView: View {
    @Query(filter: #Predicate<Session> { $0.finishedAt != nil },
           sort: \Session.createdAt, order: .reverse)
    private var sessions: [Session]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(sessions) { session in
                NavigationLink(value: session) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.landing)
                            .font(.system(size: 17, weight: .semibold, design: .serif))
                            .foregroundStyle(Paper.ink)
                            .lineLimit(2)
                        Text(session.createdAt, format: .dateTime.weekday().day().month())
                            .font(Paper.label)
                            .foregroundStyle(Paper.inkMuted)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Paper.paperRaised)
            }
            .scrollContentBackground(.hidden)
            .background(Paper.paper)
            .overlay {
                if sessions.isEmpty {
                    ContentUnavailableView("No sessions yet",
                                           systemImage: "square.grid.2x2",
                                           description: Text("Finish a session and it lands here."))
                }
            }
            .navigationTitle("Sessions")
            .navigationDestination(for: Session.self) { SessionReadView(session: $0) }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 520)
        #endif
    }
}

/// Read-only view of a finished session.
struct SessionReadView: View {
    let session: Session

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(session.createdAt, format: .dateTime.weekday(.wide).day().month(.wide).hour().minute())
                    .font(Paper.label)
                    .foregroundStyle(Paper.inkMuted)
                if !session.question.isEmpty {
                    Text(session.question)
                        .font(Paper.question)
                        .foregroundStyle(Paper.ink)
                }
                Text(session.text)
                    .font(Paper.page)
                    .foregroundStyle(Paper.ink)
                    .lineSpacing(8)
                    .textSelection(.enabled)
                Rectangle()
                    .fill(Paper.hairline)
                    .frame(height: 1)
                Text(session.landing)
                    .font(Paper.landing)
                    .foregroundStyle(Paper.ink)
            }
            .frame(maxWidth: Paper.column, alignment: .leading)
            .padding(Paper.margin)
            .frame(maxWidth: .infinity)
        }
        .background(Paper.paper)
    }
}
