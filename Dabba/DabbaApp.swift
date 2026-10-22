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
        .defaultSize(width: 1100, height: 860)
        .commands {
            CommandMenu("Page") {
                Button("Branch Tangent") {
                    NotificationCenter.default.post(name: .branchTangent, object: nil)
                }
                .keyboardShortcut("]", modifiers: .command)
            }
        }
        #endif
    }
}
