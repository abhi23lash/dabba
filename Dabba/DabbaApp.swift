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
                Button("Commands…") {
                    NotificationCenter.default.post(name: .showCommands, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("Branch Tangent") {
                    NotificationCenter.default.post(name: .branchTangent, object: nil)
                }
                .keyboardShortcut("]", modifiers: .command)

                Divider()

                Button("Next") {
                    NotificationCenter.default.post(name: .nextMethod, object: nil)
                }
                .keyboardShortcut(.downArrow, modifiers: .command)
                Button("Previous") {
                    NotificationCenter.default.post(name: .previousMethod, object: nil)
                }
                .keyboardShortcut(.upArrow, modifiers: .command)
            }
        }
        #endif
    }
}
