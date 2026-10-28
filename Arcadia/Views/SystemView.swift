import SwiftUI

/// A console's page: banner, emulator status and its games. Drop files here to add games.
struct SystemView: View {
    @Environment(AppModel.self) private var model
    let system: GameSystem
    @State private var dropTargeted = false

    var body: some View {
        let games = model.library.games(for: system)

        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Banner(system: system, count: games.count)
                if games.isEmpty {
                    emptyState
                } else {
                    GameBrowser(games: games, scope: system.id)
                }
            }
            .padding(32)
            .padding(.bottom, 80)
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
                    .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
                    .overlay {
                        Label("Add to \(system.name)", systemImage: "plus.circle.fill")
                            .font(.title2.weight(.bold))
                    }
                    .padding(16)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.importGames(urls, into: system)
            return true
        } isTargeted: { dropTargeted = $0 }
        .animation(.easeOut(duration: 0.15), value: dropTargeted)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No \(system.name) games yet")
                .font(.title3.weight(.semibold))
            (system.gameIsFolder
                 ? Text("Drag installed game folders here, or copy them into the \(system.id) folder.")
                 : Text("Drag game files here, or copy them into the \(system.id) folder.\nSupported: \(system.extensions.map { "." + $0 }.joined(separator: " "))"))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button {
                let folder = model.library.folder(for: system)
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                NSWorkspace.shared.open(folder)
            } label: {
                Label("Open Folder", systemImage: "folder")
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct Banner: View {
    @Environment(AppModel.self) private var model
    let system: GameSystem
    let count: Int

    var body: some View {
        let emulator = Bios.player(for: system, bios: model.library.biosFolder).emulator

        ZStack(alignment: .bottomLeading) {
            system.gradient
            Image(systemName: system.symbol)
                .font(.system(size: 180, weight: .bold))
                .foregroundStyle(.white.opacity(0.1))
                .rotationEffect(.degrees(-12))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .offset(x: 30)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: "\(String(localized: system.maker.title).uppercased()) · \(String(system.year))")
                        .font(.caption.weight(.heavy))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(system.name)
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                    HStack(spacing: 8) {
                        Text("\(count) games")
                        Text("·")
                        Text("Plays with \(emulator.name)")
                        if emulator.experimental { Tag(text: "Experimental", color: .orange) }
                        if emulator.needsRosetta { Tag(text: "Rosetta", color: .white) }
                    }
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.85))
                    if BiosRule.rule(for: system.id) != nil {
                        BiosStatusLabel(system: system)
                            .padding(.top, 4)
                    } else if let hint = system.biosHint {
                        Label { Text(hint) } icon: { Image(systemName: "info.circle") }
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.top, 4)
                    }
                }
                Spacer()
                EmulatorButton(emulator: emulator)
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(28)
        }
        .foregroundStyle(.white)
        .frame(minHeight: 200)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
