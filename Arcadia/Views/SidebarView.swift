import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        List(selection: $model.selection) {
            Section {
                Label("Home", systemImage: "house.fill").tag(SidebarItem.home)
                Label("Favorites", systemImage: "star.fill")
                    .badge(model.library.favorites.count)
                    .tag(SidebarItem.favorites)
            }

            CollectionsSection()

            ForEach(Maker.allCases) { maker in
                let systems = visibleSystems(for: maker)
                if !systems.isEmpty {
                    Section(String(localized: maker.title)) {
                        ForEach(systems) { system in
                            HStack(spacing: 10) {
                                SystemBadge(system: system)
                                Text(system.name).lineLimit(1)
                            }
                            .badge(model.library.count(for: system))
                            .tag(SidebarItem.system(system.id))
                        }
                    }
                }
            }

            Section("Manage") {
                Label("Emulators", systemImage: "square.stack.3d.down.right.fill")
                    .badge(Emulator.all.filter { model.emulators.state($0.id).isWorking }.count)
                    .tag(SidebarItem.emulators)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            if model.library.isScanning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Scanning library…").font(.caption).foregroundStyle(.secondary)
                }
                .padding(10)
            }
        }
    }

    /// Systems with games; every system while the library is still empty.
    private func visibleSystems(for maker: Maker) -> [GameSystem] {
        let all = GameSystem.all.filter { $0.maker == maker }
        if model.library.games.isEmpty { return all }
        return all.filter { model.library.count(for: $0) > 0 }
    }
}
