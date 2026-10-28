import SwiftUI

@main
struct ArcadiaApp: App {
    @State private var model: AppModel

    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        Integration.start(model)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .frame(minWidth: 960, minHeight: 620)
                .preferredColorScheme(.dark)
                .handlesArcadiaLinks(model)
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(after: .newItem) {
                Button("Find Games on This Mac…") { model.showFinder = true }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                Button("Rescan Library") { Task { await model.library.scan() } }
                    .keyboardShortcut("r")
                Button("Save Disk Space…") { model.showSaveSpace = true }
                Button("Show Library in Finder") { NSWorkspace.shared.open(model.library.folder) }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            TVModeCommands(model: model)
        }

        TVModeScene(model: model)

        Settings {
            SettingsView()
                .environment(model)
                .preferredColorScheme(.dark)
        }
    }
}
