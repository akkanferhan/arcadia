import SwiftUI

/// A game grid with a sort menu and genre / decade / players filters (once metadata is known).
struct GameBrowser: View {
    @Environment(AppModel.self) private var model
    let games: [Game]
    /// Identifies the page; filters reset when it changes.
    let scope: String
    var showsSystem = false

    @AppStorage("gameSort") private var sort: GameSort = .name
    @State private var filter = GameFilter()

    var body: some View {
        let facts = GameFacts(record: { model.library.record($0) },
                              info: { model.metadata.info(for: $0) },
                              added: { GameDates.added($0) })
        let shown = facts.arrange(games, by: sort, filter: filter)
        let choices = facts.choices(for: games)

        VStack(alignment: .leading, spacing: 18) {
            controls(choices, shown: shown.count)
            if shown.isEmpty {
                ContentUnavailableView {
                    Label("No games match", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("Try another filter.")
                } actions: {
                    Button("Clear Filters") { filter = GameFilter() }
                }
                .padding(.top, 40)
            } else {
                GameGrid(games: shown, showsSystem: showsSystem)
            }
        }
        .task(id: Set(games.map(\.systemID))) {
            await model.metadata.load(games.map(\.systemID))
        }
        .onChange(of: scope) { filter = GameFilter() }
    }

    private func controls(_ choices: (genres: [String], decades: [Int], players: [Int]), shown: Int) -> some View {
        HStack(spacing: 8) {
            if !choices.genres.isEmpty {
                FilterMenu(title: "Genre", symbol: "tag", activeSymbol: "tag.fill", value: filter.genre.map { Text(verbatim: $0) },
                           clear: { filter.genre = nil }) {
                    ForEach(choices.genres, id: \.self) { genre in
                        Toggle(isOn: Binding(get: { filter.genre == genre },
                                             set: { filter.genre = $0 ? genre : nil })) {
                            Text(verbatim: genre)
                        }
                    }
                }
            }
            if !choices.decades.isEmpty {
                FilterMenu(title: "Decade", symbol: "calendar", activeSymbol: "calendar.circle.fill", value: filter.decade.map(decadeText),
                           clear: { filter.decade = nil }) {
                    ForEach(choices.decades, id: \.self) { decade in
                        Toggle(isOn: Binding(get: { filter.decade == decade },
                                             set: { filter.decade = $0 ? decade : nil })) {
                            decadeText(decade)
                        }
                    }
                }
            }
            if !choices.players.isEmpty {
                FilterMenu(title: "Players", symbol: "person.2", activeSymbol: "person.2.fill", value: filter.players.map(playersText),
                           clear: { filter.players = nil }) {
                    ForEach(choices.players, id: \.self) { count in
                        Toggle(isOn: Binding(get: { filter.players == count },
                                             set: { filter.players = $0 ? count : nil })) {
                            playersText(count)
                        }
                    }
                }
            }
            if filter.isActive {
                Button("Clear") { filter = GameFilter() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                Text("\(shown) of \(games.count)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
            Menu {
                Picker("Sort By", selection: $sort) {
                    ForEach(GameSort.allCases) { option in
                        Label { Text(option.title) } icon: { Image(systemName: option.symbol) }
                            .tag(option)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label { Text(sort.title) } icon: { Image(systemName: "arrow.up.arrow.down") }
            }
            .menuStyle(.button)
            .fixedSize()
            .help("Sort By")
        }
        .controlSize(.regular)
    }

    private func decadeText(_ decade: Int) -> Text { Text("\(String(decade))s") }

    private func playersText(_ count: Int) -> Text {
        count == 1 ? Text("Single player") : Text("\(count)+ players")
    }
}

/// A filter button: its title while unset, the chosen value (tinted) once set.
private struct FilterMenu<Items: View>: View {
    let title: LocalizedStringKey
    let symbol: String
    let activeSymbol: String
    let value: Text?
    let clear: () -> Void
    @ViewBuilder let items: Items

    var body: some View {
        Menu {
            items
            if value != nil {
                Divider()
                Button("Any", action: clear)
            }
        } label: {
            Label {
                value ?? Text(title)
            } icon: {
                Image(systemName: value == nil ? symbol : activeSymbol)
            }
        }
        .menuStyle(.button)
        .fixedSize()
        .tint(value == nil ? nil : Theme.accent)
        .buttonStyle(.bordered)
    }
}
