import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let library = model.library

        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                if let game = library.recentlyPlayed.first {
                    ContinueHero(game: game)
                } else {
                    WelcomeHero()
                }

                if library.recentlyPlayed.count > 1 {
                    Shelf(title: "Recently Played", games: Array(library.recentlyPlayed.dropFirst().prefix(12)))
                }
                if !library.favorites.isEmpty {
                    Shelf(title: "Favorites", games: Array(library.favorites.prefix(12)))
                }

                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader(title: "Consoles",
                                  subtitle: library.games.isEmpty
                                    ? "Every system Arcadia can play"
                                    : "\(library.games.count) games across \(library.stockedSystems.count) systems" as LocalizedStringKey)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 16)], spacing: 16) {
                        ForEach(library.games.isEmpty ? GameSystem.all : library.stockedSystems) { system in
                            SystemTile(system: system)
                        }
                    }
                }
            }
            .padding(32)
            .padding(.bottom, 80)
        }
    }
}

/// Large banner for the most recently played game.
private struct ContinueHero: View {
    @Environment(AppModel.self) private var model
    let game: Game

    var body: some View {
        let record = model.library.record(game)

        ZStack(alignment: .bottomLeading) {
            Color.clear
                .overlay { CoverArt(game: game).blur(radius: 40).scaleEffect(1.4) }
                .clipped()
                .overlay(LinearGradient(colors: [.black.opacity(0.2), .black.opacity(0.75)],
                                        startPoint: .top, endPoint: .bottom))

            HStack(alignment: .bottom, spacing: 24) {
                CoverArt(game: game)
                    .frame(width: 150, height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.5), radius: 20, y: 10)

                VStack(alignment: .leading, spacing: 10) {
                    Text("CONTINUE PLAYING")
                        .font(.caption.weight(.heavy))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(game.title)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        SystemBadge(system: game.system, size: 20)
                        Text(game.system.name)
                        if record.playTime > 0 {
                            Text("·")
                            Text("Played \(record.playTime.playTimeText)")
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.8))

                    Button {
                        model.play(game)
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .font(.headline)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
                    .controlSize(.large)
                    .padding(.top, 6)
                }
                Spacer()
            }
            .padding(28)
        }
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.stroke))
    }
}

/// Shown until something has been played.
private struct WelcomeHero: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let hasGames = !model.library.games.isEmpty

        ZStack(alignment: .leading) {
            LinearGradient(colors: [Theme.accent, Color(hex: 0x2B1C6E), Color(hex: 0x0E0B24)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 220))
                .foregroundStyle(.white.opacity(0.07))
                .rotationEffect(.degrees(-15))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .offset(x: 40)

            VStack(alignment: .leading, spacing: 12) {
                (hasGames ? Text("Ready when you are") : Text("Welcome to Arcadia"))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                (hasGames
                     ? Text("Pick a console, double-click a game and play. Arcadia installs the emulator for you.")
                     : Text("Put your games in a system's folder, or drag them onto a console page. Arcadia does the rest."))
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: 520, alignment: .leading)
                HStack {
                    Button {
                        NSWorkspace.shared.open(model.library.folder)
                    } label: {
                        Label("Open Games Folder", systemImage: "folder.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
                    Button {
                        model.selection = .emulators
                    } label: {
                        Label("Emulators", systemImage: "square.stack.3d.down.right")
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)
                .padding(.top, 6)
            }
            .padding(32)
        }
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// Horizontal row of games.
private struct Shelf: View {
    let title: LocalizedStringKey
    let games: [Game]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: title)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 20) {
                    ForEach(games) { game in
                        GameCard(game: game, showsSystem: true).frame(width: 160)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, -4)
        }
    }
}

/// Colorful card that opens a system's page.
struct SystemTile: View {
    @Environment(AppModel.self) private var model
    let system: GameSystem

    var body: some View {
        let count = model.library.count(for: system)

        Button {
            model.selection = .system(system.id)
        } label: {
            ZStack(alignment: .bottomLeading) {
                system.gradient
                Image(systemName: system.symbol)
                    .font(.system(size: 70, weight: .bold))
                    .foregroundStyle(.white.opacity(0.14))
                    .rotationEffect(.degrees(-10))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .offset(x: 14, y: -8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(system.name)
                        .font(.headline)
                        .lineLimit(1)
                    (count == 0 ? Text(verbatim: String(system.year)) : Text("\(count) games"))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
                .padding(14)
            }
            .foregroundStyle(.white)
            .frame(height: 104)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .hoverLift()
    }
}
