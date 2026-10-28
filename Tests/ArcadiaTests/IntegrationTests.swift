import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Arcadia

@Suite struct ArcadiaLinkTests {
    @Test func roundTripsGamePaths() throws {
        let id = "/Users/me/Games/snes/Tom & Jerry = Fun + #1 (USA) [!] ü.sfc"
        for link in [ArcadiaLink.play(game: id), .open(game: id), .play(game: nil), .open(game: nil)] {
            #expect(ArcadiaLink(url: link.url) == link)
        }
        #expect(ArcadiaLink.play(game: "/a b").url.absoluteString == "arcadia://play?game=/a%20b")
    }

    @Test func readsHandWrittenLinks() {
        #expect(ArcadiaLink(url: URL(string: "arcadia://play?game=%2Fg%2Fx.sfc")!) == .play(game: "/g/x.sfc"))
        #expect(ArcadiaLink(url: URL(string: "ARCADIA://Open")!) == .open(game: nil))
        #expect(ArcadiaLink(url: URL(string: "arcadia://play?game=")!) == .play(game: nil))
        #expect(ArcadiaLink(url: URL(string: "arcadia://delete?game=x")!) == nil)
        #expect(ArcadiaLink(url: URL(string: "https://play?game=x")!) == nil)
    }
}

@Suite struct SpotlightTests {
    private func game(_ name: String, _ system: String = "snes") -> Game {
        Game(url: URL(fileURLWithPath: "/g/\(system)/\(name).sfc"), systemID: system)
    }

    @Test func indexesOnlyWhatChanged() {
        let mario = Spotlight.Entry(game: game("Super Mario World (USA)"), cover: nil)
        let zelda = Spotlight.Entry(game: game("Zelda (USA)"), cover: URL(fileURLWithPath: "/a/zelda.png"))
        let gone = game("Gone")

        let first = Spotlight.changes(from: [:], to: [mario, zelda])
        #expect(first.index == [mario, zelda])
        #expect(first.remove.isEmpty)

        let indexed = [mario.game.id: mario.signature, gone.id: "old"]
        let next = Spotlight.changes(from: indexed, to: [mario, zelda])
        #expect(next.index == [zelda])
        #expect(next.remove == [gone.id])
    }

    @Test func newCoversRefreshTheItem() {
        let bare = Spotlight.Entry(game: game("Metroid"), cover: nil)
        let covered = Spotlight.Entry(game: bare.game, cover: URL(fileURLWithPath: "/a/metroid.png"))
        #expect(Spotlight.changes(from: [bare.game.id: bare.signature], to: [covered]).index == [covered])
    }
}

@Suite struct GameQueryTests {
    private let games = [
        Game(url: URL(fileURLWithPath: "/g/snes/Super Mario World (USA).sfc"), systemID: "snes"),
        Game(url: URL(fileURLWithPath: "/g/n64/Super Mario 64 (USA).z64"), systemID: "n64"),
        Game(url: URL(fileURLWithPath: "/g/n64/Paper Mario (USA).z64"), systemID: "n64"),
        Game(url: URL(fileURLWithPath: "/g/gba/Metroid Fusion (USA).gba"), systemID: "gba"),
    ]

    @Test func matchesEveryWordAndPrefersPrefixes() {
        let marios = GameQuery.games(matching: "mario", in: games).map(\.title)
        #expect(Set(marios) == ["Super Mario World", "Super Mario 64", "Paper Mario"])
        #expect(GameQuery.games(matching: "paper", in: games).map(\.title) == ["Paper Mario"])
        // "64" also matches the system, Nintendo 64.
        #expect(GameQuery.games(matching: "Mario 64", in: games).map(\.title) == ["Super Mario 64", "Paper Mario"])
        #expect(GameQuery.games(matching: "super mario", in: games).map(\.title) == ["Super Mario World", "Super Mario 64"])
        #expect(GameQuery.games(matching: "Mario", in: Array(games.reversed())).first?.title == "Paper Mario")
    }

    @Test func findsGamesBySystem() {
        #expect(GameQuery.games(matching: "gba", in: games).map(\.title) == ["Metroid Fusion"])
        #expect(GameQuery.games(matching: "  ", in: games).count == games.count)
    }

    @Test func suggestsRecentGamesFirstWithoutRepeats() {
        let suggestions = GameQuery.suggestions(recent: [games[3], games[1]], all: games)
        #expect(suggestions.map(\.id) == [games[3], games[1], games[0], games[2]].map(\.id))
    }
}

@Suite struct WidgetPublisherTests {
    private func item(_ game: Game) -> ContinuePlayingSnapshot.Item {
        ContinuePlayingSnapshot.Item(id: game.id, title: game.title, systemName: game.system.name,
                                     systemShortName: game.system.shortName, systemSymbol: game.system.symbol,
                                     systemColors: [0x7C5CFF], lastPlayed: Date(timeIntervalSince1970: 1_800_000_000),
                                     playTime: 90)
    }

    private func image() -> NSImage {
        NSImage(size: NSSize(width: 600, height: 800), flipped: false) { rect in
            NSColor.systemPurple.setFill()
            rect.fill()
            return true
        }
    }

    @Test func writesSnapshotAndCovers() throws {
        let folder = TemporaryFolder()
        let mario = Game(url: URL(fileURLWithPath: "/g/snes/Super Mario World (USA).sfc"), systemID: "snes")
        let zelda = Game(url: URL(fileURLWithPath: "/g/snes/Zelda (USA).sfc"), systemID: "snes")
        folder.write("Covers/stale.jpg", Data([1]))

        var snapshot = ContinuePlayingSnapshot(items: [item(mario), item(zelda)])
        #expect(WidgetPublisher.write(&snapshot, covers: [mario: image()], to: folder.url))
        #expect(snapshot.items[0].cover == Artwork.key(for: mario) + ".jpg")
        #expect(snapshot.items[1].cover == nil)

        let covers = try FileManager.default.contentsOfDirectory(atPath: folder.url.appendingPathComponent("Covers").path)
        #expect(covers == [Artwork.key(for: mario) + ".jpg"])
        let cover = try #require(snapshot.coverURL(for: snapshot.items[0], in: folder.url))
        let thumbnail = try #require(NSImage(contentsOf: cover))
        #expect(max(thumbnail.size.width, thumbnail.size.height) <= 360)

        #expect(ContinuePlayingSnapshot.load(from: folder.url) == snapshot)
        // Nothing changed, so the widget does not need reloading.
        var again = ContinuePlayingSnapshot(items: [item(mario), item(zelda)])
        #expect(!WidgetPublisher.write(&again, covers: [mario: image()], to: folder.url))
    }

    @Test func colorsBecomeHex() {
        #expect(Color(hex: 0x7C5CFF).hexValue == 0x7C5CFF)
        #expect(Color(hex: 0x000000).hexValue == 0)
    }
}
