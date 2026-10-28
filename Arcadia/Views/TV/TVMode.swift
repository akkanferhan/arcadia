import SwiftUI
import GameController

/// Ways into and out of TV Mode.
enum TVMode {
    static let windowID = "tv"
    /// Settings key: open TV Mode as soon as a controller connects.
    static let openOnControllerKey = "openTVModeOnController"

    /// Brings the library window back after TV Mode closes.
    @MainActor
    static func showMainWindow(excluding tvWindow: NSWindow?) {
        let main = NSApp.windows.first { $0 !== tvWindow && $0.canBecomeMain && $0.isVisible }
        main?.makeKeyAndOrderFront(nil)
    }
}

/// The full-screen TV Mode window.
struct TVModeScene: Scene {
    let model: AppModel

    var body: some Scene {
        Window("TV Mode", id: TVMode.windowID) {
            TVModeView()
                .environment(model)
                .frame(minWidth: 960, minHeight: 600)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1600, height: 900)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        .commandsRemoved()
    }
}

/// View ▸ TV Mode (⇧⌘T).
struct TVModeCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some Commands {
        CommandGroup(before: .sidebar) {
            Button(model.isTVModeActive ? "Exit TV Mode" : "TV Mode") {
                if model.isTVModeActive {
                    dismissWindow(id: TVMode.windowID)
                } else {
                    openWindow(id: TVMode.windowID)
                }
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            Divider()
        }
    }
}

/// Adds the TV Mode toolbar button to the library window, and opens TV Mode when a controller
/// connects if the player asked for that.
private struct TVModeEntry: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @AppStorage(TVMode.openOnControllerKey) private var openOnController = false
    @MainActor private static var openedFromArgument = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        openWindow(id: TVMode.windowID)
                    } label: {
                        Label("TV Mode", systemImage: "tv")
                    }
                    .help("Play from the couch with a controller (⇧⌘T)")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidConnect)) { _ in
                let launcher = model.launcher
                guard openOnController, !model.isTVModeActive, launcher.running == nil, launcher.preparing == nil else { return }
                openWindow(id: TVMode.windowID)
            }
            .onAppear {
                // Starts the GameController framework so connections are announced.
                _ = GCController.controllers()
                // `-tvMode YES` opens TV Mode right away (handy for development).
                if UserDefaults.standard.bool(forKey: "tvMode"), !Self.openedFromArgument {
                    Self.openedFromArgument = true
                    openWindow(id: TVMode.windowID)
                }
            }
    }
}

extension View {
    func tvModeEntry() -> some View { modifier(TVModeEntry()) }
}
