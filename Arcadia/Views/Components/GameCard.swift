import SwiftUI

/// A cover with the title underneath. Double-click or press the play button to start the game.
struct GameCard: View {
    @Environment(AppModel.self) private var model
    let game: Game
    var showsSystem = false
    @State private var hovering = false

    var body: some View {
        let record = model.library.record(game)

        VStack(alignment: .leading, spacing: 8) {
            Color.clear
                .aspectRatio(Theme.coverRatio, contentMode: .fit)
                .overlay { CoverArt(game: game) }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.stroke)
                }
                .overlay(alignment: .topTrailing) {
                    if record.favorite {
                        Image(systemName: "star.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.yellow)
                            .padding(6)
                            .background(.black.opacity(0.5), in: Circle())
                            .padding(8)
                    }
                }
                .overlay {
                    if hovering || model.launcher.preparing == game {
                        playOverlay
                    }
                }
                .hoverLift()
                .onHover { hovering = $0 }

            VStack(alignment: .leading, spacing: 2) {
                Text(game.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if showsSystem { Text(game.system.shortName) }
                    if showsSystem, game.region != nil { Text("·") }
                    if let region = game.region { Text(region) }
                    if record.playTime > 0 {
                        Spacer(minLength: 4)
                        Text(record.playTime.playTimeText)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.play(game) }
        .contextMenu {
            Button("Play", systemImage: "play.fill") { model.play(game) }
            if record.favorite {
                Button("Remove from Favorites", systemImage: "star.slash") { model.library.toggleFavorite(game) }
            } else {
                Button("Add to Favorites", systemImage: "star") { model.library.toggleFavorite(game) }
            }
            Divider()
            Button("Show in Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([game.url])
            }
        }
        .help(game.fileTitle)
    }

    private var playOverlay: some View {
        ZStack {
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
            Button {
                model.play(game)
            } label: {
                Group {
                    if model.launcher.preparing == game {
                        ProgressView().controlSize(.small).tint(.black)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.title2.weight(.bold))
                            .offset(x: 2)
                    }
                }
                .frame(width: 54, height: 54)
                .foregroundStyle(.black)
                .background(.white, in: Circle())
                .shadow(radius: 10)
            }
            .buttonStyle(.plain)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .transition(.opacity)
    }
}

/// An adaptive grid of game cards.
struct GameGrid: View {
    let games: [Game]
    var showsSystem = false

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 210), spacing: 22)], spacing: 26) {
            ForEach(games) { game in
                GameCard(game: game, showsSystem: showsSystem)
            }
        }
    }
}

/// A full page with a title and a grid, used for favorites and search.
struct GameGridPage: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let games: [Game]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SectionHeader(title: title, subtitle: subtitle)
                if games.isEmpty {
                    ContentUnavailableView("Nothing here yet", systemImage: "sparkles",
                                           description: Text("Games will show up here."))
                        .padding(.top, 60)
                } else {
                    GameGrid(games: games, showsSystem: true)
                }
            }
            .padding(32)
            .padding(.bottom, 80)
        }
    }
}
