import SwiftUI
import WidgetKit

/// The last played games, written by Arcadia into the shared App Group.
struct ContinuePlayingEntry: TimelineEntry {
    let date: Date
    let items: [ContinuePlayingSnapshot.Item]
    let covers: [String: NSImage]
    var isPlaceholder = false

    static func load() -> ContinuePlayingEntry {
        guard let folder = SharedContainer.url, let snapshot = ContinuePlayingSnapshot.load(from: folder) else {
            return ContinuePlayingEntry(date: .now, items: [], covers: [:])
        }
        var covers: [String: NSImage] = [:]
        for item in snapshot.items {
            if let url = snapshot.coverURL(for: item, in: folder), let image = NSImage(contentsOf: url) {
                covers[item.id] = image
            }
        }
        return ContinuePlayingEntry(date: .now, items: snapshot.items, covers: covers)
    }

    static let placeholder = ContinuePlayingEntry(
        date: .now,
        items: [("Super Mario World", "Super Nintendo", "SNES", 0x7B5CD6, 0x3D2A8C),
                ("Crash Bandicoot", "PlayStation", "PS1", 0x2E6BE6, 0x1A2F7A),
                ("Metroid Fusion", "Game Boy Advance", "GBA", 0x5A4FCF, 0x2B2470)].map { title, name, short, from, to in
            ContinuePlayingSnapshot.Item(id: title, title: title, systemName: name, systemShortName: short,
                                         systemSymbol: "gamecontroller.fill", systemColors: [from, to],
                                         lastPlayed: .now, playTime: 0)
        },
        covers: [:], isPlaceholder: true)
}

struct ContinuePlayingProvider: TimelineProvider {
    func placeholder(in context: Context) -> ContinuePlayingEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (ContinuePlayingEntry) -> Void) {
        let entry = ContinuePlayingEntry.load()
        completion(context.isPreview && entry.items.isEmpty ? .placeholder : entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ContinuePlayingEntry>) -> Void) {
        // Arcadia reloads the widget after every scan and session, so it never needs to refresh itself.
        completion(Timeline(entries: [.load()], policy: .never))
    }
}

struct ContinuePlayingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ContinuePlaying", provider: ContinuePlayingProvider()) { entry in
            ContinuePlayingView(entry: entry)
                .environment(\.colorScheme, .dark)
                .containerBackground(for: .widget) { WidgetTheme.background }
        }
        .configurationDisplayName("Continue Playing")
        .description("Jump back into the games you played last.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

enum WidgetTheme {
    static let accent = Color(rgb: 0x7C5CFF)
    static let background = LinearGradient(colors: [Color(rgb: 0x111218), Color(rgb: 0x0A0A0F)],
                                           startPoint: .top, endPoint: .bottom)
    static let stroke = Color.white.opacity(0.08)
}

extension Color {
    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255)
    }
}

struct ContinuePlayingView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ContinuePlayingEntry

    var body: some View {
        Group {
            if entry.items.isEmpty {
                empty
            } else if family == .systemSmall {
                small(entry.items[0])
            } else {
                medium
            }
        }
        .redacted(reason: entry.isPlaceholder ? .placeholder : [])
    }

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: "gamecontroller.fill")
                .foregroundStyle(WidgetTheme.accent)
                .widgetAccentable()
            Text("CONTINUE PLAYING")
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(.system(size: 10, weight: .heavy))
    }

    private func small(_ item: ContinuePlayingSnapshot.Item) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            HStack(alignment: .bottom, spacing: 10) {
                WidgetCover(item: item, image: entry.covers[item.id])
                    .frame(width: 66, height: 88)
                Spacer(minLength: 0)
                Image(systemName: "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 30, height: 30)
                    .background(.white, in: Circle())
                    .widgetAccentable()
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(item.systemShortName)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(ArcadiaLink.play(game: item.id).url)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            HStack(alignment: .top, spacing: 12) {
                ForEach(entry.items.prefix(3)) { item in
                    Link(destination: ArcadiaLink.play(game: item.id).url) {
                        VStack(alignment: .leading, spacing: 4) {
                            WidgetCover(item: item, image: entry.covers[item.id])
                                .frame(width: 57, height: 76)
                            Text(item.title)
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(item.systemShortName)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                // Keep covers the same size when fewer than three games have been played.
                ForEach(entry.items.count..<3, id: \.self) { _ in
                    Color.clear.frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(ArcadiaLink.open(game: nil).url)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Spacer(minLength: 0)
            Text("No games played yet")
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
            Text("Games you play in Arcadia show up here.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(ArcadiaLink.open(game: nil).url)
    }
}

/// Box art, or the system's colors and symbol when there is none.
struct WidgetCover: View {
    let item: ContinuePlayingSnapshot.Item
    let image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Color.black
                Image(nsImage: image)
                    .resizable()
                    .widgetAccentedRenderingMode(.fullColor)
                    .aspectRatio(contentMode: .fit)
            } else {
                LinearGradient(colors: item.systemColors.map { Color(rgb: $0) }, startPoint: .topLeading,
                               endPoint: .bottomTrailing)
                Image(systemName: item.systemSymbol)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(WidgetTheme.stroke))
        .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
    }
}
