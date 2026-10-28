import SwiftUI

/// The sidebar's "Collections" section. Drop games on a collection to add them.
struct CollectionsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let collections = model.collections

        Section {
            ForEach(collections.sorted) { collection in
                CollectionRow(collection: collection)
            }
            if collections.all.isEmpty {
                NewCollectionRow()
            }
        } header: {
            HStack {
                Text("Collections")
                Spacer()
                Button {
                    collections.prompt = .create(adding: [])
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .help("New Collection")
            }
        }
    }
}

private struct CollectionRow: View {
    @Environment(AppModel.self) private var model
    let collection: GameCollection
    @State private var targeted = false

    var body: some View {
        let count = model.collections.games(in: collection.id, from: model.library.games).count

        Label(collection.name, systemImage: targeted ? "plus.square.fill.on.square.fill" : "square.stack.fill")
            .badge(count)
            .tag(SidebarItem.collection(collection.id))
            .contextMenu {
                Button("Rename…", systemImage: "pencil") { model.collections.prompt = .rename(collection.id) }
                Button("Delete Collection", systemImage: "trash", role: .destructive) {
                    if model.selection == .collection(collection.id) { model.selection = .home }
                    model.collections.delete(collection.id)
                }
            }
            .dropDestination(for: String.self) { ids, _ in
                let games = model.library.games.filter { ids.contains($0.id) }
                guard !games.isEmpty else { return false }
                model.collections.add(games, to: collection.id)
                return true
            } isTargeted: { targeted = $0 }
    }
}

/// Shown while there are no collections yet; also takes dropped games.
private struct NewCollectionRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            model.collections.prompt = .create(adding: [])
        } label: {
            Label("New Collection", systemImage: "plus")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .dropDestination(for: String.self) { ids, _ in
            let games = model.library.games.filter { ids.contains($0.id) }
            guard !games.isEmpty else { return false }
            model.collections.prompt = .create(adding: games)
            return true
        }
    }
}

/// Menu entries that put a game in or take it out of each collection.
struct CollectionMenuItems: View {
    @Environment(AppModel.self) private var model
    let game: Game

    var body: some View {
        let collections = model.collections
        ForEach(collections.sorted) { collection in
            Toggle(isOn: Binding(get: { collections.contains(game, in: collection.id) },
                                 set: { _ in collections.toggle(game, in: collection.id) })) {
                Text(collection.name)
            }
        }
        if !collections.all.isEmpty { Divider() }
        Button("New Collection…", systemImage: "plus") {
            collections.prompt = .create(adding: [game])
        }
    }
}

/// A collection's page.
struct CollectionView: View {
    @Environment(AppModel.self) private var model
    let id: UUID

    var body: some View {
        if let collection = model.collections.collection(id) {
            let games = model.collections.games(in: id, from: model.library.games)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .firstTextBaseline) {
                        SectionHeader(title: "\(collection.name)", subtitle: "\(games.count) games")
                        Menu {
                            Button("Rename…", systemImage: "pencil") { model.collections.prompt = .rename(id) }
                            Button("Delete Collection", systemImage: "trash", role: .destructive) {
                                model.selection = .home
                                model.collections.delete(id)
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.button)
                        .menuIndicator(.hidden)
                        .buttonStyle(.borderless)
                        .fixedSize()
                    }
                    if games.isEmpty {
                        ContentUnavailableView("This collection is empty", systemImage: "square.stack",
                                               description: Text("Drag games onto the collection in the sidebar, or choose Collections in a game's menu."))
                            .padding(.top, 60)
                    } else {
                        GameBrowser(games: games, scope: id.uuidString, showsSystem: true)
                    }
                }
                .padding(32)
                .padding(.bottom, 80)
            }
            .environment(\.currentCollection, id)
        } else {
            ContentUnavailableView("Collection not found", systemImage: "square.stack")
        }
    }
}

extension EnvironmentValues {
    /// The collection whose page shows a card, so its menu can offer to remove it.
    @Entry var currentCollection: UUID?
}

/// Names a new collection or renames one.
struct CollectionNameSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let prompt: Collections.Prompt
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "square.stack.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isRename ? "Rename Collection" : "New Collection").font(.headline)
                    if case .create(let games) = prompt, let game = games.first {
                        (games.count == 1 ? Text("Adds \(game.title)") : Text("Adds \(games.count) games"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            TextField("Name", text: $name, prompt: Text("Couch Co-op, RPGs to Finish…"))
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isRename ? "Rename" : "Create", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            if case .rename(let id) = prompt { name = model.collections.collection(id)?.name ?? "" }
        }
    }

    private var isRename: Bool {
        if case .rename = prompt { return true }
        return false
    }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        switch prompt {
        case .create(let games):
            let collection = model.collections.create(named: name, adding: games)
            if games.isEmpty { model.selection = .collection(collection.id) }
        case .rename(let id):
            model.collections.rename(id, to: name)
        }
        dismiss()
    }
}
