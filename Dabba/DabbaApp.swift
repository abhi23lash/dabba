import SwiftUI
import SwiftData

@main
struct DabbaApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: Session.self)
        #if os(macOS)
        .defaultSize(width: 760, height: 860)
        #endif
    }
}
