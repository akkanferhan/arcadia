import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        } detail: {
            ZStack(alignment: .bottom) {
                Theme.background.ignoresSafeArea()
                detail
                NowPlayingBar()
                    .padding(.bottom, 20)
            }
        }
        .searchable(text: $model.search, placement: .toolbar, prompt: "Search games")
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.library.scan() }
        }
        .sheet(isPresented: $model.showOnboarding) {
            OnboardingView()
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: $model.showFinder) {
            FindGamesView()
        }
        .alert(item: $model.problem) { problem in
            if let emulator = problem.missing {
                Alert(title: Text("Almost ready"), message: Text(problem.message),
                      primaryButton: .default(Text("Install \(emulator.name)")) {
                          model.emulators.install(emulator)
                      },
                      secondaryButton: .cancel())
            } else {
                Alert(title: Text("Couldn't start the game"), message: Text(problem.message))
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if !model.search.isEmpty {
            GameGridPage(title: "Search", subtitle: "Results for “\(model.search)”",
                         games: model.library.games.filter { $0.title.localizedCaseInsensitiveContains(model.search) })
        } else {
            switch model.selection ?? .home {
            case .home:
                HomeView()
            case .favorites:
                GameGridPage(title: "Favorites", subtitle: "Games you've starred", games: model.library.favorites)
            case .system(let id):
                if let system = GameSystem.with(id: id) { SystemView(system: system) }
            case .emulators:
                EmulatorsView()
            }
        }
    }
}
