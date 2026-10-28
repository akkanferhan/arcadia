import SwiftUI

// MARK: - Search

/// The on-screen keyboard and the search text, shown in place of the hero.
struct TVSearchPanel: View {
    let navigator: TVNavigator
    let resultCount: Int
    let metrics: TVMetrics
    let tap: (_ row: Int, _ column: Int) -> Void

    var body: some View {
        let unit = metrics.unit
        let keyboard = navigator.keyboard

        VStack(alignment: .leading, spacing: 22 * unit) {
            HStack(alignment: .firstTextBaseline, spacing: 16 * unit) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.white.opacity(0.6))
                if navigator.query.isEmpty {
                    Text("Type a game's name")
                        .foregroundStyle(.white.opacity(0.4))
                } else {
                    Text(navigator.query)
                    + Text(verbatim: "|").foregroundStyle(Theme.accent)
                }
                Spacer()
                if !navigator.query.isEmpty {
                    (resultCount == 0 ? Text("No matches") : Text("\(resultCount) games"))
                        .font(.system(size: 22 * unit, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .font(.system(size: 52 * unit, weight: .bold, design: .rounded))
            .lineLimit(1)

            VStack(alignment: .leading, spacing: 10 * unit) {
                ForEach(Array(TVKeyboard.rows.enumerated()), id: \.offset) { row, keys in
                    HStack(spacing: 10 * unit) {
                        ForEach(Array(keys.enumerated()), id: \.offset) { column, key in
                            TVKeyCap(key: key, isFocused: keyboard?.row == row && keyboard?.column == column, metrics: metrics)
                                .onTapGesture { tap(row, column) }
                        }
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, metrics.margin)
        .padding(.bottom, 36 * unit)
        .transition(.opacity.combined(with: .offset(y: -20 * unit)))
    }
}

private struct TVKeyCap: View {
    let key: TVKeyboard.Key
    let isFocused: Bool
    let metrics: TVMetrics

    var body: some View {
        let unit = metrics.unit
        let size = 62 * unit

        Group {
            switch key {
            case .character(let character): Text(String(character))
            case .space: Image(systemName: "space")
            case .delete: Image(systemName: "delete.left")
            case .done: Text("Done")
            }
        }
        .font(.system(size: 26 * unit, weight: .semibold, design: .rounded))
        .frame(width: key == .done ? size * 1.8 : size, height: size)
        .foregroundStyle(isFocused ? .black : .white)
        .background(isFocused ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.1)),
                    in: RoundedRectangle(cornerRadius: 12 * unit, style: .continuous))
        .scaleEffect(isFocused ? 1.15 : 1)
        .shadow(color: .white.opacity(isFocused ? 0.35 : 0), radius: 16 * unit)
        .zIndex(isFocused ? 1 : 0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isFocused)
    }
}

// MARK: - Hints

/// What each button does right now, bottom right like on a console.
struct TVHintBar: View {
    let controller: TVModeController
    let metrics: TVMetrics

    private struct Hint: Identifiable {
        let button: TVButtonGlyph.Button
        let label: LocalizedStringKey
        var id: TVButtonGlyph.Button { button }
    }

    var body: some View {
        let navigator = controller.navigator
        let atTop = navigator.query.isEmpty && navigator.focus.row == 0

        let hints: [Hint] = if controller.menu != nil {
            [Hint(button: .a, label: "Choose"), Hint(button: .b, label: "Close")]
        } else if navigator.isSearching {
            // On a keyboard, letters type and Return closes the keyboard.
            controller.gamepads.isConnected
                ? [Hint(button: .a, label: "Type"), Hint(button: .b, label: "Done")]
                : [Hint(button: .a, label: "Done")]
        } else {
            [Hint(button: .a, label: "Play"), Hint(button: .x, label: "Favorite"),
             Hint(button: .y, label: "Search"), Hint(button: .menu, label: "Options"),
             Hint(button: .b, label: atTop ? "Exit" : "Back")]
        }

        HStack(spacing: 26 * metrics.unit) {
            ForEach(hints) { hint in
                HStack(spacing: 8 * metrics.unit) {
                    TVButtonGlyph(button: hint.button, keyboard: !controller.gamepads.isConnected, metrics: metrics)
                    Text(hint.label)
                }
            }
        }
        .font(.system(size: 19 * metrics.unit, weight: .semibold))
        .foregroundStyle(.white.opacity(0.75))
        .padding(.horizontal, metrics.margin)
        .padding(.bottom, 34 * metrics.unit)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.top, 70 * metrics.unit)
        .background {
            LinearGradient(colors: [.clear, .black.opacity(0.85), .black], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
        }
        .animation(.easeOut(duration: 0.2), value: hints.map(\.button))
    }
}

/// A controller button, or the matching key while no controller is connected.
struct TVButtonGlyph: View {
    enum Button: Hashable { case a, b, x, y, menu }

    let button: Button
    let keyboard: Bool
    let metrics: TVMetrics

    var body: some View {
        let size = 28 * metrics.unit
        if keyboard {
            Group {
                switch button {
                case .a: Image(systemName: "return")
                case .b: Text(verbatim: "esc")
                case .x: Text(verbatim: "F")
                case .y: Text(verbatim: "/")
                case .menu: Image(systemName: "space")
                }
            }
            .font(.system(size: 14 * metrics.unit, weight: .bold, design: .rounded))
            .padding(.horizontal, 8 * metrics.unit)
            .frame(minWidth: size, minHeight: size)
            .foregroundStyle(.white)
            .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 7 * metrics.unit, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7 * metrics.unit, style: .continuous).strokeBorder(.white.opacity(0.25)))
        } else {
            Image(systemName: symbol)
                .font(.system(size: size))
                .foregroundStyle(.white)
        }
    }

    private var symbol: String {
        switch button {
        case .a: "a.circle.fill"
        case .b: "b.circle.fill"
        case .x: "x.circle.fill"
        case .y: "y.circle.fill"
        case .menu: "line.3.horizontal.circle.fill"
        }
    }
}

/// Emulators being installed after the player said yes in a TV menu.
struct TVInstallStatus: View {
    @Environment(AppModel.self) private var model
    let metrics: TVMetrics

    var body: some View {
        let working = Emulator.all.compactMap { emulator -> (Emulator, Double?)? in
            guard case .working(_, let progress) = model.emulators.state(emulator.id) else { return nil }
            return (emulator, progress)
        }
        if let (emulator, progress) = working.first {
            HStack(spacing: 14 * metrics.unit) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 6 * metrics.unit) {
                    Text("Installing \(emulator.name)…")
                    if let progress {
                        ProgressView(value: progress)
                            .tint(.white)
                            .frame(width: 220 * metrics.unit)
                    }
                }
            }
            .font(.system(size: 19 * metrics.unit, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18 * metrics.unit)
            .padding(.vertical, 12 * metrics.unit)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.horizontal, metrics.margin)
            .padding(.bottom, 26 * metrics.unit)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: - Playing

/// Covers TV Mode while a game starts or runs.
struct TVPlayingOverlay: View {
    @Environment(AppModel.self) private var model
    let game: Game
    let metrics: TVMetrics

    var body: some View {
        let unit = metrics.unit
        let launcher = model.launcher
        let running = launcher.running != nil

        ZStack {
            Color.black
            CoverArt(game: game)
                .blur(radius: 90)
                .scaleEffect(1.6)
                .opacity(0.55)
                .allowsHitTesting(false)

            HStack(spacing: 60 * unit) {
                CoverArt(game: game)
                    .frame(width: metrics.coverWidth * 1.6, height: metrics.coverHeight * 1.6)
                    .clipShape(RoundedRectangle(cornerRadius: 22 * unit, style: .continuous))
                    .shadow(color: game.system.colors[0].opacity(0.6), radius: 60 * unit)
                    .shadow(color: .black.opacity(0.6), radius: 30 * unit, y: 20 * unit)
                    .phaseAnimator([false, true]) { cover, pulse in
                        cover.scaleEffect(running ? 1 : (pulse ? 1.03 : 0.99))
                    } animation: { _ in .easeInOut(duration: 1.2) }

                VStack(alignment: .leading, spacing: 18 * unit) {
                    (running ? Text("NOW PLAYING") : Text("STARTING"))
                        .font(.system(size: 20 * unit, weight: .heavy))
                        .tracking(3 * unit)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(game.title)
                        .font(.system(size: 60 * unit, weight: .bold, design: .rounded))
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                    HStack(spacing: 12 * unit) {
                        SystemBadge(system: game.system, size: 30 * unit)
                        Text(game.system.name)
                    }
                    .font(.system(size: 24 * unit, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))

                    if running {
                        Text("Your controller now plays the game. Quit from the emulator to come back here.")
                            .font(.system(size: 22 * unit))
                            .foregroundStyle(.white.opacity(0.65))
                            .frame(maxWidth: 560 * unit, alignment: .leading)
                        SwiftUI.Button(role: .destructive) {
                            launcher.stop()
                        } label: {
                            Label("Quit Game", systemImage: "stop.fill")
                                .font(.system(size: 22 * unit, weight: .semibold))
                                .padding(.horizontal, 26 * unit)
                                .padding(.vertical, 14 * unit)
                                .background(.white.opacity(0.14), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8 * unit)
                    } else {
                        VStack(alignment: .leading, spacing: 12 * unit) {
                            HStack(spacing: 12 * unit) {
                                ProgressView().controlSize(.small)
                                if let status = launcher.preparingStatus {
                                    Text(status)
                                } else {
                                    Text("Starting…")
                                }
                            }
                            if let progress = launcher.preparingProgress {
                                ProgressView(value: progress)
                                    .tint(.white)
                                    .frame(width: 420 * unit)
                            }
                        }
                        .font(.system(size: 22 * unit, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                    }
                }
                .frame(maxWidth: metrics.size.width * 0.45, alignment: .leading)
            }
            .foregroundStyle(.white)
        }
    }
}

// MARK: - Menus

/// A centered panel of large choices: a game's options or a problem to confirm.
struct TVMenuOverlay: View {
    @Environment(AppModel.self) private var model
    let menu: TVMenu<TVMenuAction>
    let metrics: TVMetrics
    let perform: (TVMenuAction) -> Void
    let dismiss: () -> Void

    var body: some View {
        let unit = metrics.unit

        ZStack {
            Color.black.opacity(0.6)
                .onTapGesture(perform: dismiss)

            VStack(alignment: .leading, spacing: 26 * unit) {
                VStack(alignment: .leading, spacing: 10 * unit) {
                    Text(menu.title)
                        .font(.system(size: 38 * unit, weight: .bold, design: .rounded))
                        .lineLimit(2)
                    if let message = menu.message {
                        Text(message)
                            .font(.system(size: 21 * unit))
                            .foregroundStyle(.white.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                VStack(spacing: 12 * unit) {
                    ForEach(Array(menu.actions.enumerated()), id: \.offset) { index, action in
                        let focused = index == menu.index
                        SwiftUI.Button { perform(action) } label: {
                            HStack(spacing: 16 * unit) {
                                Image(systemName: symbol(action)).frame(width: 30 * unit)
                                Text(title(action))
                                Spacer()
                            }
                            .font(.system(size: 24 * unit, weight: .semibold))
                            .padding(.horizontal, 24 * unit)
                            .frame(height: 64 * unit)
                            .foregroundStyle(focused ? .black : .white)
                            .background(focused ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.08)),
                                        in: RoundedRectangle(cornerRadius: 16 * unit, style: .continuous))
                            .scaleEffect(focused ? 1.04 : 1)
                            .shadow(color: .white.opacity(focused ? 0.25 : 0), radius: 18 * unit)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: focused)
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(40 * unit)
            .frame(width: 620 * unit)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 34 * unit, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 34 * unit, style: .continuous).strokeBorder(.white.opacity(0.12)))
            .shadow(color: .black.opacity(0.5), radius: 50 * unit, y: 20 * unit)
            .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
    }

    private func title(_ action: TVMenuAction) -> LocalizedStringKey {
        switch action {
        case .play: "Play"
        case .toggleFavorite(let game): model.library.record(game).favorite ? "Remove from Favorites" : "Add to Favorites"
        case .search: "Search"
        case .exitTVMode: "Exit TV Mode"
        case .installEmulator(let id): "Install \(Emulator.with(id: id)?.name ?? "")"
        case .installRosetta: "Install Rosetta"
        case .close: menu.actions.count > 1 ? "Not Now" : "OK"
        }
    }

    private func symbol(_ action: TVMenuAction) -> String {
        switch action {
        case .play: "play.fill"
        case .toggleFavorite(let game): model.library.record(game).favorite ? "star.slash" : "star"
        case .search: "magnifyingglass"
        case .exitTVMode: "rectangle.on.rectangle"
        case .installEmulator: "arrow.down.circle"
        case .installRosetta: "arrow.down.circle"
        case .close: "xmark"
        }
    }
}

// MARK: - Window

/// Hands over the NSWindow a view lives in.
struct TVWindowReader: NSViewRepresentable {
    let found: (NSWindow) -> Void

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.found = found
        return view
    }

    func updateNSView(_ view: ReaderView, context: Context) {
        view.found = found
    }

    final class ReaderView: NSView {
        var found: (NSWindow) -> Void = { _ in }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { found(window) }
        }
    }
}
