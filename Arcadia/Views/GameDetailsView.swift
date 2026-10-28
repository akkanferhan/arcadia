import SwiftUI

/// A game's page: artwork, facts from libretro-database, a Wikipedia summary, play stats and how it runs.
struct GameDetailsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let game: Game

    @State private var snap: NSImage?
    @State private var titleScreen: NSImage?
    @State private var summary: WikiSummary?
    @State private var summaryLoaded = false

    var body: some View {
        let info = model.metadata.info(for: game)

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero(info)
                HStack(alignment: .top, spacing: 28) {
                    VStack(alignment: .leading, spacing: 28) {
                        about
                        if snap != nil || titleScreen != nil { screenshots }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 16) {
                        facts(info)
                        playing
                    }
                    .frame(width: 290)
                }
                .padding(.horizontal, 32)
                .padding(.top, 26)
                .padding(.bottom, 32)
            }
        }
        .scrollIndicators(.never)
        .background(Theme.background)
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close")
            .padding(16)
        }
        .frame(minWidth: 820, idealWidth: 900, minHeight: 600, idealHeight: 720)
        // Names a collection made from this sheet; the main window can't while the sheet is up.
        .sheet(item: Bindable(model.collections).prompt) { prompt in
            CollectionNameSheet(prompt: prompt)
        }
        .task(id: game.id) { await model.metadata.load(game.systemID) }
        .task(id: game.id) {
            async let snap = Screenshots.shared.image(.snap, for: game)
            async let title = Screenshots.shared.image(.title, for: game)
            let (loadedSnap, loadedTitle) = await (snap, title)
            withAnimation(.easeOut(duration: 0.3)) {
                self.snap = loadedSnap
                self.titleScreen = loadedTitle
            }
        }
        .task(id: game.id) {
            let loaded = await Wikipedia.shared.summary(for: game)
            withAnimation(.easeOut(duration: 0.2)) {
                summary = loaded
                summaryLoaded = true
            }
        }
    }

    // MARK: Hero

    private func hero(_ info: GameInfo?) -> some View {
        let record = model.library.record(game)

        return ZStack(alignment: .bottomLeading) {
            backdrop
            HStack(alignment: .bottom, spacing: 26) {
                Color.clear
                    .frame(width: 180, height: 240)
                    .overlay { CoverArt(game: game) }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke))
                    .shadow(color: .black.opacity(0.6), radius: 24, y: 12)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        SystemBadge(system: game.system, size: 20)
                        Text(verbatim: [game.system.name.uppercased(), info?.year.map { String($0) }]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.caption.weight(.heavy))
                            .tracking(1.5)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    Text(game.title)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .textSelection(.enabled)
                    HStack(spacing: 6) {
                        if let region = game.region { HeroChip(text: region, symbol: "globe") }
                        if let genre = info?.genre { HeroChip(text: genre, symbol: "tag") }
                        if let players = info?.players {
                            HeroChip(text: players.playersText, symbol: players > 1 ? "person.2.fill" : "person.fill")
                        }
                    }

                    HStack(spacing: 10) {
                        Button {
                            dismiss()
                            model.play(game)
                        } label: {
                            Label("Play", systemImage: "play.fill")
                                .font(.headline)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 5)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.white)
                        .foregroundStyle(.black)
                        .disabled(model.launcher.preparing != nil)

                        Button {
                            model.library.toggleFavorite(game)
                        } label: {
                            Label(record.favorite ? "Remove from Favorites" : "Add to Favorites",
                                  systemImage: record.favorite ? "star.fill" : "star")
                                .labelStyle(.iconOnly)
                                .foregroundStyle(record.favorite ? .yellow : .white)
                                .frame(width: 18)
                        }
                        .help(record.favorite ? "Remove from Favorites" : "Add to Favorites")

                        Menu {
                            CollectionMenuItems(game: game)
                        } label: {
                            Label("Collections", systemImage: "square.stack")
                        }
                        .menuStyle(.button)
                        .fixedSize()

                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([game.url])
                        } label: {
                            Label("Show in Finder", systemImage: "folder")
                                .labelStyle(.iconOnly)
                                .frame(width: 18)
                        }
                        .help("Show in Finder")
                    }
                    .fixedSize()
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .padding(.top, 6)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 26)
        }
        .foregroundStyle(.white)
        .frame(height: 380)
    }

    /// The snapshot (or title screen, or cover) blurred behind the hero, fading into the page.
    private var backdrop: some View {
        Color.clear
            .overlay {
                if let image = snap ?? titleScreen {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.medium)
                        .aspectRatio(contentMode: .fill)
                        .blur(radius: 26)
                        .scaleEffect(1.15)
                        .opacity(0.85)
                        .transition(.opacity)
                } else {
                    CoverArt(game: game)
                        .blur(radius: 50)
                        .scaleEffect(1.5)
                        .opacity(0.8)
                }
            }
            .clipped()
            .overlay(LinearGradient(stops: [.init(color: .black.opacity(0.25), location: 0),
                                            .init(color: .black.opacity(0.55), location: 0.55),
                                            .init(color: Color(hex: 0x111218), location: 1)],
                                    startPoint: .top, endPoint: .bottom))
    }

    // MARK: Content

    private var about: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("About").font(.title3.weight(.bold))
            if let summary {
                Text(summary.extract)
                    .font(.body)
                    .lineSpacing(3)
                    .foregroundStyle(.white.opacity(0.85))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Link(destination: summary.url) {
                    Label("From Wikipedia", systemImage: "arrow.up.right.square")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.secondary)
                .help(summary.url.absoluteString)
            } else if summaryLoaded {
                Text("No description found. Arcadia looks one up on Wikipedia when you're online.")
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking up a description…").foregroundStyle(.secondary)
                }
            }
        }
    }

    private var screenshots: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Screens").font(.title3.weight(.bold))
            HStack(alignment: .top, spacing: 14) {
                ForEach([titleScreen, snap].compactMap { $0 }, id: \.self) { image in
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(image.size.width / max(image.size.height, 1), contentMode: .fit)
                        .frame(maxWidth: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.stroke))
                }
            }
        }
    }

    private func facts(_ info: GameInfo?) -> some View {
        let record = model.library.record(game)

        return DetailsCard {
            FactRow(label: "Genre", value: info?.genre)
            FactRow(label: "Developer", value: info?.developer)
            FactRow(label: "Publisher", value: info?.publisher)
            FactRow(label: "Released", value: info?.year.map { String($0) })
            FactRow(label: "Players", value: info?.players?.playersText)
            Divider().padding(.vertical, 2)
            FactRow(label: "Last Played",
                    value: record.lastPlayed?.formatted(.relative(presentation: .named)) ?? String(localized: "Never"))
            FactRow(label: "Play Time", value: record.playTime > 0 ? record.playTime.playTimeText : String(localized: "None yet"))
        }
    }

    private var playing: some View {
        let player = Bios.player(for: game.system, bios: model.library.biosFolder)

        return DetailsCard {
            Text("Plays with").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.emulator.name).font(.headline)
                    if let core = player.core {
                        Text("\(core) core").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                EmulatorButton(emulator: player.emulator)
                    .controlSize(.small)
            }
            HStack(spacing: 6) {
                if player.emulator.experimental { Tag(text: "Experimental", color: .orange) }
                if player.emulator.needsRosetta { Tag(text: "Rosetta", color: .white) }
            }
            BiosStatusLabel(system: game.system)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Rounded panel on the details page.
private struct DetailsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke))
    }
}

/// "Genre    Platform" with a dash while the value is unknown.
private struct FactRow: View {
    let label: LocalizedStringKey
    let value: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(verbatim: value ?? "—")
                .foregroundStyle(value == nil ? .tertiary : .primary)
                .lineLimit(2)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .font(.callout)
    }
}

/// Small translucent capsule in the hero, e.g. the region or genre.
private struct HeroChip: View {
    let text: String
    let symbol: String

    var body: some View {
        Label { Text(verbatim: text) } icon: { Image(systemName: symbol) }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(.white.opacity(0.14), in: Capsule())
            .foregroundStyle(.white.opacity(0.9))
    }
}

extension Int {
    /// "1 player" or "Up to 4 players".
    var playersText: String {
        self == 1 ? String(localized: "1 player") : String(localized: "Up to \(self) players")
    }
}

extension View {
    /// Opens the details sheet of the game named by `-details <title>` (handy for development and screenshots).
    func detailsLaunchArgument() -> some View { modifier(DetailsLaunchArgument()) }
}

private struct DetailsLaunchArgument: ViewModifier {
    @Environment(AppModel.self) private var model
    @State private var done = false

    func body(content: Content) -> some View {
        content.onChange(of: model.library.games) {
            guard !done, let wanted = UserDefaults.standard.string(forKey: "details") else { return }
            done = true
            model.details = model.library.games.first { $0.title.localizedCaseInsensitiveContains(wanted) }
        }
    }
}
