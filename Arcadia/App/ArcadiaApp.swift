import SwiftUI

@main
struct ArcadiaApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .frame(minWidth: 960, minHeight: 620)
                .preferredColorScheme(.dark)
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(after: .newItem) {
                Button("Rescan Library") { Task { await model.library.scan() } }
                    .keyboardShortcut("r")
                Button("Show Library in Finder") { NSWorkspace.shared.open(model.library.folder) }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environment(model)
                .preferredColorScheme(.dark)
        }
    }
}
