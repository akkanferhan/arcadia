import SwiftUI

/// Sizes for TV Mode, scaled from a 1080-point-tall screen so the 10-foot layout fits any window.
struct TVMetrics {
    let size: CGSize

    var unit: CGFloat { max(min(size.height / 1080, size.width / 1700), 0.55) }
    var margin: CGFloat { 88 * unit }
    var heroHeight: CGFloat { size.height * 0.46 }
    var coverWidth: CGFloat { 196 * unit }
    var coverHeight: CGFloat { coverWidth / Theme.coverRatio }
    var coverSpacing: CGFloat { 30 * unit }
    var focusScale: CGFloat { 1.12 }
}

/// The 10-foot, controller-first interface: a hero for the focused game over shelves of covers.
struct TVModeView: View {
    @Environment(AppModel.self) private var model
    @State private var controller = TVModeController()
    @State private var window: NSWindow?
    #if DEBUG
    /// Shows the "Starting" overlay without launching anything (`-tvDemo starting`).
    @State private var demoStarting: Game?
    #endif

    private var shelves: [TVShelf] {
        let library = model.library
        return TVShelf.make(games: library.games, recentlyPlayed: library.recentlyPlayed,
                            favorites: library.favorites, query: controller.navigator.query)
    }

    var body: some View {
        let navigator = controller.navigator
        let focus = navigator.focus
        let launcher = model.launcher
        #if DEBUG
        let playing = launcher.running ?? launcher.preparing ?? demoStarting
        #else
        let playing = launcher.running ?? launcher.preparing
        #endif

        GeometryReader { geometry in
            let metrics = TVMetrics(size: geometry.size)

            ZStack(alignment: .topLeading) {
                Color.black
                TVBackdrop(game: playing ?? focus.game)

                VStack(alignment: .leading, spacing: 0) {
                    TVTopBar(controller: controller, metrics: metrics)
                    Group {
                        if navigator.isSearching {
                            TVSearchPanel(navigator: navigator, resultCount: focus.shelves.first?.games.count ?? 0,
                                          metrics: metrics) { row, column in
                                controller.navigator.tapKey(row: row, column: column)
                            }
                        } else if let game = focus.game {
                            TVHero(game: game, shelf: focus.shelf?.kind, metrics: metrics)
                        } else {
                            Color.clear
                        }
                    }
                    .frame(height: metrics.heroHeight - metrics.unit * 100, alignment: .bottomLeading)

                    TVShelves(controller: controller, metrics: metrics)
                }

                TVInstallStatus(metrics: metrics)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

                if let playing {
                    TVPlayingOverlay(game: playing, metrics: metrics)
                        .transition(.opacity.combined(with: .scale(scale: 1.04)))
                }
                if let menu = controller.menu {
                    TVMenuOverlay(menu: menu, metrics: metrics) { controller.perform($0) } dismiss: { controller.close() }
                        .transition(.opacity)
                }
                if playing == nil {
                    TVHintBar(controller: controller, metrics: metrics)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: playing)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: controller.menu)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: navigator.isSearching)
        }
        .ignoresSafeArea()
        .background(TVWindowReader { attach($0) })
        .onAppear {
            model.isTVModeActive = true
            controller.update(shelves)
            controller.start(model: model)
        }
        .onDisappear {
            controller.stop()
            model.isTVModeActive = false
            TVMode.showMainWindow(excluding: window)
        }
        .onChange(of: shelves) { _, shelves in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { controller.update(shelves) }
        }
        .onChange(of: model.problem?.id, initial: true) {
            if let problem = model.problem { controller.showProblem(problem) }
        }
        .onChange(of: launcher.running) { old, new in
            if old != nil, new == nil { controller.returnToFront() }
        }
        #if DEBUG
        .task { await showDemoOverlayIfAsked() }
        #endif
    }

    private func attach(_ window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        controller.window = window
        controller.onExit = { [weak window] in window?.close() }
        window.backgroundColor = .black
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.makeKeyAndOrderFront(nil)
        // `-tvWindowed YES` keeps TV Mode in a window (handy for development).
        if !UserDefaults.standard.bool(forKey: "tvWindowed"), !window.styleMask.contains(.fullScreen) {
            DispatchQueue.main.async { window.toggleFullScreen(nil) }
        }
    }

    #if DEBUG
    /// `-tvDemo options|search` opens a menu or the keyboard right away, for screenshots.
    private func showDemoOverlayIfAsked() async {
        guard let demo = UserDefaults.standard.string(forKey: "tvDemo") else { return }
        try? await Task.sleep(for: .seconds(1.5))
        switch demo {
        case "options": controller.handle(.options, fromKeyboard: true)
        case "search":
            controller.handle(.search, fromKeyboard: true)
            for command in [TVCommand.type("m"), .type("a"), .move(.down), .move(.right), .move(.right)] {
                controller.handle(command, fromKeyboard: true)
            }
        case "problem":
            model.problem = AppModel.Problem(message: String(localized: "\(Emulator.all[0].name) plays \(GameSystem.all[0].name) games. Install it now? It's free and takes about a minute."),
                                             missing: Emulator.all[0])
        case "starting": demoStarting = controller.navigator.focus.game
        case "down":
            for _ in 0..<2 { controller.handle(.move(.down), fromKeyboard: true) }
            for _ in 0..<2 { controller.handle(.move(.right), fromKeyboard: true) }
        default: break
        }
    }
    #endif
}

extension TVNavigator {
    /// Presses a key on the on-screen keyboard with the pointer.
    mutating func tapKey(row: Int, column: Int) {
        while keyboard.map({ $0.row > row }) == true { _ = handle(.move(.up)) }
        while keyboard.map({ $0.row < row }) == true { _ = handle(.move(.down)) }
        while keyboard.map({ $0.column > column }) == true { _ = handle(.move(.left)) }
        while keyboard.map({ $0.column < column }) == true { _ = handle(.move(.right)) }
        _ = handle(.select)
    }
}

// MARK: - Backdrop and hero

/// The focused game's box art, blurred across the whole screen.
private struct TVBackdrop: View {
    let game: Game?

    var body: some View {
        ZStack {
            if let game {
                CoverArt(game: game)
                    .blur(radius: 70)
                    .scaleEffect(1.5)
                    .saturation(1.3)
                    .opacity(0.6)
                    .id(game.id)
                    .transition(.opacity)
            }
            LinearGradient(colors: [.black.opacity(0.85), .black.opacity(0.35), .clear],
                           startPoint: .leading, endPoint: .trailing)
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .clear, location: 0.35),
                                   .init(color: .black.opacity(0.92), location: 0.72), .init(color: .black, location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
        .animation(.easeInOut(duration: 0.6), value: game?.id)
        .clipped()
        .allowsHitTesting(false)
    }
}

private struct TVTopBar: View {
    @Environment(AppModel.self) private var model
    let controller: TVModeController
    let metrics: TVMetrics

    var body: some View {
        let unit = metrics.unit
        let query = controller.navigator.query

        HStack(spacing: 18 * unit) {
            HStack(spacing: 10 * unit) {
                Image(systemName: "gamecontroller.fill")
                    .foregroundStyle(Theme.accent)
                Text(verbatim: "Arcadia")
            }
            .font(.system(size: 26 * unit, weight: .bold, design: .rounded))

            if !query.isEmpty, !controller.navigator.isSearching {
                Label(query, systemImage: "magnifyingglass")
                    .font(.system(size: 20 * unit, weight: .semibold))
                    .padding(.horizontal, 16 * unit)
                    .padding(.vertical, 8 * unit)
                    .background(.white.opacity(0.14), in: Capsule())
                    .transition(.scale.combined(with: .opacity))
            }
            Spacer()
            if controller.gamepads.isConnected {
                Image(systemName: "gamecontroller")
                    .help("Controller connected")
            }
            TimelineView(.everyMinute) { context in
                Text(context.date, format: .dateTime.hour().minute())
                    .monospacedDigit()
            }
            Button {
                controller.onExit()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18 * unit, weight: .bold))
                    .frame(width: 44 * unit, height: 44 * unit)
                    .background(.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Exit TV Mode")
        }
        .font(.system(size: 22 * unit, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, metrics.margin)
        .padding(.top, 40 * unit)
        .frame(height: 100 * unit, alignment: .top)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: query)
    }
}

/// Title, system and play time of the focused game, with its cover large on the right.
private struct TVHero: View {
    @Environment(AppModel.self) private var model
    let game: Game
    let shelf: TVShelf.Kind?
    let metrics: TVMetrics

    var body: some View {
        let unit = metrics.unit
        let record = model.library.record(game)

        HStack(alignment: .bottom, spacing: 40 * unit) {
            VStack(alignment: .leading, spacing: 16 * unit) {
                HStack(spacing: 12 * unit) {
                    SystemBadge(system: game.system, size: 34 * unit)
                    Text(game.system.name.uppercased())
                        .tracking(2.5 * unit)
                    if record.favorite {
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                    }
                }
                .font(.system(size: 18 * unit, weight: .heavy))
                .foregroundStyle(.white.opacity(0.8))

                Text(game.title)
                    .font(.system(size: 68 * unit, weight: .bold, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .shadow(color: .black.opacity(0.5), radius: 12, y: 4)

                HStack(spacing: 12 * unit) {
                    if let region = game.region { TVMetaPill(text: region, metrics: metrics) }
                    if record.playTime > 0 {
                        Label("Played \(record.playTime.playTimeText)", systemImage: "clock")
                    }
                    if let last = record.lastPlayed {
                        Text("·")
                        Text("Last played \(last, format: .relative(presentation: .named))")
                    } else {
                        Text("Not played yet")
                    }
                }
                .font(.system(size: 22 * unit, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
            }
            .frame(maxWidth: metrics.size.width * 0.55, alignment: .leading)
            .id(game.id)
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 12 * unit)), removal: .opacity))

            Spacer(minLength: 0)

            CoverArt(game: game)
                .frame(width: metrics.coverWidth * 1.25, height: metrics.coverHeight * 1.25)
                .clipShape(RoundedRectangle(cornerRadius: 18 * unit, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18 * unit, style: .continuous).strokeBorder(.white.opacity(0.15)))
                .shadow(color: game.system.colors[0].opacity(0.45), radius: 50 * unit)
                .shadow(color: .black.opacity(0.6), radius: 24 * unit, y: 16 * unit)
                .rotation3DEffect(.degrees(-8), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                .id(game.id)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, metrics.margin)
        .padding(.bottom, 36 * unit)
        .animation(.easeOut(duration: 0.3), value: game.id)
    }
}

private struct TVMetaPill: View {
    let text: String
    let metrics: TVMetrics

    var body: some View {
        Text(text)
            .font(.system(size: 16 * metrics.unit, weight: .bold))
            .padding(.horizontal, 10 * metrics.unit)
            .padding(.vertical, 4 * metrics.unit)
            .overlay(RoundedRectangle(cornerRadius: 6 * metrics.unit).strokeBorder(.white.opacity(0.5), lineWidth: 1.5))
    }
}

// MARK: - Shelves

private struct TVShelves: View {
    @Environment(AppModel.self) private var model
    let controller: TVModeController
    let metrics: TVMetrics

    var body: some View {
        let navigator = controller.navigator
        let focus = navigator.focus
        let active = !navigator.isSearching && controller.menu == nil

        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10 * metrics.unit) {
                    ForEach(Array(focus.shelves.enumerated()), id: \.element.id) { index, shelf in
                        TVShelfRow(shelf: shelf,
                                   column: focus.column(in: shelf),
                                   isFocusedRow: index == focus.row,
                                   isActive: active && index == focus.row,
                                   bumps: controller.bumps,
                                   metrics: metrics) { column, play in
                            controller.navigator.focus.focus(row: index, column: column)
                            if play, let game = controller.navigator.focus.game { model.play(game) }
                        }
                        .id(shelf.id)
                    }
                    if focus.shelves.isEmpty {
                        TVEmptyShelves(query: navigator.query, metrics: metrics)
                    }
                }
                .padding(.bottom, metrics.size.height)
            }
            .scrollDisabled(true)
            .onChange(of: focus.row) { _, _ in
                guard let shelf = controller.navigator.focus.shelf else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                    proxy.scrollTo(shelf.id, anchor: .top)
                }
            }
        }
    }
}

private struct TVShelfRow: View {
    let shelf: TVShelf
    let column: Int
    let isFocusedRow: Bool
    let isActive: Bool
    let bumps: Int
    let metrics: TVMetrics
    let tap: (_ column: Int, _ play: Bool) -> Void

    var body: some View {
        let unit = metrics.unit

        VStack(alignment: .leading, spacing: 0) {
            TVShelfTitle(kind: shelf.kind, count: shelf.games.count, metrics: metrics)
                .padding(.horizontal, metrics.margin)
                .opacity(isFocusedRow ? 1 : 0.6)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: metrics.coverSpacing) {
                        ForEach(Array(shelf.games.enumerated()), id: \.element.id) { index, game in
                            TVCover(game: game, isFocused: isActive && index == column,
                                    bumps: bumps, metrics: metrics)
                                .id(game.id)
                                .onTapGesture(count: 2) { tap(index, true) }
                                .onTapGesture { tap(index, false) }
                        }
                    }
                    .padding(.horizontal, metrics.margin)
                    .padding(.vertical, 30 * unit)
                }
                .scrollDisabled(true)
                // The focused cover's glow and lift reach past the row.
                .scrollClipDisabled()
                .onAppear { scroll(proxy, animated: false) }
                .onChange(of: column) { _, _ in scroll(proxy, animated: true) }
            }
        }
    }

    /// Keeps one cover of context to the left of the focused one.
    private func scroll(_ proxy: ScrollViewProxy, animated: Bool) {
        guard shelf.games.indices.contains(column) else { return }
        let lead = metrics.margin + CGFloat(min(column, 1)) * (metrics.coverWidth + metrics.coverSpacing)
        let anchor = UnitPoint(x: lead / max(metrics.size.width - metrics.coverWidth, 1), y: 0.5)
        let id = shelf.games[column].id
        if animated {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) { proxy.scrollTo(id, anchor: anchor) }
        } else {
            proxy.scrollTo(id, anchor: anchor)
        }
    }
}

private struct TVShelfTitle: View {
    let kind: TVShelf.Kind
    let count: Int
    let metrics: TVMetrics

    var body: some View {
        HStack(spacing: 12 * metrics.unit) {
            switch kind {
            case .continuePlaying: Text("Continue Playing")
            case .favorites: Text("Favorites")
            case .results: Text("Results")
            case .system(let id):
                if let system = GameSystem.with(id: id) {
                    SystemBadge(system: system, size: 30 * metrics.unit)
                    Text(system.name)
                }
            }
            Text("\(count) games")
                .font(.system(size: 18 * metrics.unit, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        }
        .font(.system(size: 28 * metrics.unit, weight: .bold, design: .rounded))
        .foregroundStyle(.white)
    }
}

/// A big cover that lifts and glows while it has the focus.
private struct TVCover: View {
    @Environment(AppModel.self) private var model
    let game: Game
    let isFocused: Bool
    let bumps: Int
    let metrics: TVMetrics

    var body: some View {
        let unit = metrics.unit
        let shape = RoundedRectangle(cornerRadius: 16 * unit, style: .continuous)
        let favorite = model.library.record(game).favorite

        CoverArt(game: game)
            .frame(width: metrics.coverWidth, height: metrics.coverHeight)
            .overlay {
                // A soft sheen across the focused cover, like Apple TV's.
                LinearGradient(colors: [.white.opacity(isFocused ? 0.22 : 0), .clear],
                               startPoint: .topLeading, endPoint: .center)
            }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(.white.opacity(isFocused ? 0.85 : 0.08), lineWidth: isFocused ? 3 * unit : 1)
            }
            .overlay(alignment: .topTrailing) {
                if favorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 16 * unit, weight: .bold))
                        .foregroundStyle(.yellow)
                        .padding(8 * unit)
                        .background(.black.opacity(0.55), in: Circle())
                        .padding(10 * unit)
                }
            }
            .brightness(isFocused ? 0 : -0.12)
            .shadow(color: game.system.colors[0].opacity(isFocused ? 0.75 : 0), radius: 34 * unit)
            .shadow(color: .black.opacity(isFocused ? 0.6 : 0.3), radius: isFocused ? 26 * unit : 8 * unit,
                    y: isFocused ? 18 * unit : 6 * unit)
            .scaleEffect(isFocused ? metrics.focusScale : 1)
            .zIndex(isFocused ? 1 : 0)
            .modifier(TVShake(phase: isFocused ? CGFloat(bumps) : 0, distance: 10 * unit))
            .animation(.spring(response: 0.32, dampingFraction: 0.68), value: isFocused)
            .animation(isFocused ? .linear(duration: 0.3) : nil, value: bumps)
            .contentShape(shape)
    }
}

/// A quick side-to-side shake for a press that leads nowhere.
private struct TVShake: GeometryEffect {
    var phase: CGFloat
    var distance: CGFloat

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: sin(phase * .pi * 3) * distance * (1 - phase.truncatingRemainder(dividingBy: 1)), y: 0))
    }
}

private struct TVEmptyShelves: View {
    let query: String
    let metrics: TVMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 12 * metrics.unit) {
            if query.isEmpty {
                Text("No games yet")
                    .font(.system(size: 40 * metrics.unit, weight: .bold, design: .rounded))
                Text("Add games to your library folder and they'll show up here.")
            } else {
                Text("No matches for “\(query)”")
                    .font(.system(size: 40 * metrics.unit, weight: .bold, design: .rounded))
                Text("Try a shorter search.")
            }
        }
        .font(.system(size: 24 * metrics.unit))
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, metrics.margin)
        .padding(.top, 40 * metrics.unit)
    }
}
