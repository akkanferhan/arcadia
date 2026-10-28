import Foundation
import Testing
@testable import Arcadia

private func game(_ file: String, _ system: String = "snes") -> Game {
    Game(url: URL(fileURLWithPath: "/games/\(system)/\(file)"), systemID: system)
}

private func field(_ folder: String) -> MetadataIndex.Field {
    MetadataIndex.fields.first { $0.folder == folder }!
}

@Suite struct DatFileTests {
    @Test func readsGameBlocks() {
        let dat = """
        clrmamepro (
        \tname "Nintendo - Super Nintendo Entertainment System"
        \tversion "2024"
        )

        game (
        \tcomment "Super Mario World (USA)"
        \tgenre "Platform"
        \trom ( crc B19ED489 )
        )

        game (
        \tname "Chrono Trigger (USA)"
        \tgenre "Role-Playing (RPG)"
        \trom ( name "Chrono Trigger (USA).sfc" size 4194304 crc 2D206BF7 )
        )
        """
        let entries = DatFile.parse(dat)
        #expect(entries.count == 2)
        #expect(entries[0].fields["genre"] == "Platform")
        #expect(entries[0].names == ["Super Mario World (USA)"])
        #expect(entries[1].fields["genre"] == "Role-Playing (RPG)")
        #expect(entries[1].names == ["Chrono Trigger (USA)"])
        #expect(entries[1].romNames == ["Chrono Trigger (USA)"])
    }

    @Test func readsRomNamesAndBareValues() {
        let dat = """
        game (
        \trom ( name "Crash Bandicoot (USA).cue" serial "SCUS-94900" )
        \tusers 2
        )
        """
        let entries = DatFile.parse(dat)
        #expect(entries.first?.fields["users"] == "2")
        #expect(entries.first?.names == ["Crash Bandicoot (USA)"])
    }
}

@Suite struct MetadataIndexTests {
    private func index() -> MetadataIndex {
        var index = MetadataIndex()
        index.add("""
        game ( comment "Super Mario World (USA)" genre "Platform" rom ( crc 1 ) )
        game ( comment "Super Mario World (Europe) (Rev 1)" genre "Platform" rom ( crc 2 ) )
        """, field: field("genre"))
        index.add("""
        game ( comment "Super Mario World (USA)" developer "Nintendo EAD" )
        """, field: field("developer"))
        index.add("""
        game ( comment "Super Mario World (Japan)" publisher "Nintendo" )
        """, field: field("publisher"))
        index.add("""
        game ( comment "Super Mario World (USA)" releaseyear "1991" )
        game ( comment "Super Mario World (Japan)" releaseyear "1990" )
        """, field: field("releaseyear"))
        index.add("""
        game ( comment "Super Mario World (USA)" users 2 )
        """, field: field("maxusers"))
        return index
    }

    @Test func matchesByNoIntroName() {
        let info = index().info(for: game("Super Mario World (USA).sfc"))
        #expect(info == GameInfo(genre: "Platform", developer: "Nintendo EAD", publisher: "Nintendo", year: 1991, players: 2))
    }

    @Test func fallsBackToOtherReleasesOfTheSameRegionFirst() {
        // No "(Japan) (Rev 2)" entry: the Japanese release's year wins over the American one.
        let info = index().info(for: game("Super Mario World (Japan) (Rev 2).sfc"))
        #expect(info?.year == 1990)
        #expect(info?.genre == "Platform")
        // An untagged file still finds the game.
        #expect(index().info(for: game("super mario world.sfc"))?.developer == "Nintendo EAD")
    }

    @Test func unknownGamesHaveNoInfo() {
        #expect(index().info(for: game("Chrono Trigger (USA).sfc")) == nil)
    }

    @Test func survivesTheDiskCache() throws {
        let original = index()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MetadataIndex.self, from: data)
        #expect(decoded == original)
        #expect(decoded.info(for: game("Super Mario World (Japan) (Rev 2).sfc"))?.year == 1990)
    }

    @Test func buildsDatabaseURLs() {
        let url = Metadata.datURL(folder: "genre", database: "Nintendo - Super Nintendo Entertainment System")
        #expect(url?.absoluteString
            == "https://raw.githubusercontent.com/libretro/libretro-database/master/metadat/genre/Nintendo%20-%20Super%20Nintendo%20Entertainment%20System.dat")
    }
}

@Suite struct WikipediaMatchingTests {
    @Test func writesTitlesTheWayWikipediaDoes() {
        #expect(Wikipedia.searchTitle("Legend of Zelda, The - A Link to the Past") == "The Legend of Zelda: A Link to the Past")
        #expect(Wikipedia.searchTitle("Sonic The Hedgehog") == "Sonic The Hedgehog")
    }

    @Test func prefersExactGameArticles() {
        let pages = [
            Wikipedia.SearchPage(key: "Crash_Bandicoot", title: "Crash Bandicoot", description: "Video game franchise"),
            Wikipedia.SearchPage(key: "Crash_Bandicoot_(character)", title: "Crash Bandicoot (character)", description: "Fictional character"),
            Wikipedia.SearchPage(key: "Crash_Bandicoot_(video_game)", title: "Crash Bandicoot (video game)", description: "1996 video game"),
            Wikipedia.SearchPage(key: "Crash_Bandicoot_2", title: "Crash Bandicoot 2: Cortex Strikes Back", description: "1997 video game"),
            Wikipedia.SearchPage(key: "Crash_Team", title: "Crash Team Racing", description: "1999 video game"),
        ]
        let ranked = Wikipedia.rank(pages, for: "Crash Bandicoot").map(\.key)
        #expect(Array(ranked.prefix(2)) == ["Crash_Bandicoot_(video_game)", "Crash_Bandicoot"])
        #expect(ranked.contains("Crash_Bandicoot_2"))
        #expect(!ranked.contains("Crash_Team"))
    }

    @Test func normalizesPunctuationAndNotes() {
        #expect(Wikipedia.normalized("Sonic the Hedgehog (1991 video game)") == Wikipedia.normalized("Sonic The Hedgehog"))
        #expect(Wikipedia.normalized("Pokémon: Red & Blue") == "pokemon red and blue")
    }
}

@Suite @MainActor struct CollectionsTests {
    @Test func createsRenamesAndDeletes() {
        let folder = TemporaryFolder()
        let file = folder.url.appendingPathComponent("collections.json")
        let mario = game("Super Mario World (USA).sfc")
        let chrono = game("Chrono Trigger (USA).sfc")

        let collections = Collections(file: file)
        let couch = collections.create(named: "  Couch Co-op ", adding: [mario])
        #expect(couch.name == "Couch Co-op")
        collections.add([mario, chrono], to: couch.id)
        #expect(collections.collection(couch.id)?.gameIDs == [mario.id, chrono.id])
        collections.toggle(mario, in: couch.id)
        #expect(!collections.contains(mario, in: couch.id))
        collections.rename(couch.id, to: "Party")
        collections.rename(couch.id, to: "   ")
        #expect(collections.collection(couch.id)?.name == "Party")

        // Saved to disk and read back.
        let reloaded = Collections(file: file)
        #expect(reloaded.all == collections.all)
        // Games no longer in the library drop out of the page.
        #expect(reloaded.games(in: couch.id, from: [mario]).isEmpty)
        #expect(reloaded.games(in: couch.id, from: [mario, chrono]) == [chrono])

        reloaded.delete(couch.id)
        #expect(Collections(file: file).all.isEmpty)
    }
}

@Suite struct GameSortTests {
    private let mario = game("Super Mario World (USA).sfc")
    private let chrono = game("Chrono Trigger (USA).sfc")
    private let sonic = game("Sonic The Hedgehog (USA, Europe).md", "megadrive")

    private var facts: GameFacts {
        let records = [mario.id: GameRecord(lastPlayed: Date(timeIntervalSince1970: 100), playTime: 600),
                       chrono.id: GameRecord(lastPlayed: Date(timeIntervalSince1970: 200), playTime: 60)]
        let infos = [mario.id: GameInfo(genre: "Platform", year: 1990, players: 2),
                     chrono.id: GameInfo(genre: "Role-Playing (RPG)", year: 1995, players: 1),
                     sonic.id: GameInfo(genre: "Platform", year: 1991, players: 1)]
        let added = [sonic.id: Date(timeIntervalSince1970: 300), mario.id: Date(timeIntervalSince1970: 50)]
        return GameFacts(record: { records[$0.id] ?? GameRecord() }, info: { infos[$0.id] }, added: { added[$0.id] })
    }

    @Test func sortsEachWay() {
        let games = [mario, sonic, chrono]
        #expect(facts.arrange(games, by: .name) == [chrono, sonic, mario])
        #expect(facts.arrange(games, by: .recentlyPlayed) == [chrono, mario, sonic])
        #expect(facts.arrange(games, by: .mostPlayed) == [mario, chrono, sonic])
        #expect(facts.arrange(games, by: .recentlyAdded) == [sonic, mario, chrono])
        #expect(facts.arrange(games, by: .releaseYear) == [chrono, sonic, mario])
    }

    @Test func filtersByGenreDecadeAndPlayers() {
        let games = [mario, sonic, chrono]
        #expect(facts.arrange(games, by: .name, filter: GameFilter(genre: "Platform")) == [sonic, mario])
        #expect(facts.arrange(games, by: .name, filter: GameFilter(decade: 1990)) == [chrono, sonic, mario])
        #expect(facts.arrange(games, by: .name, filter: GameFilter(players: 2)) == [mario])
        #expect(facts.arrange(games, by: .name, filter: GameFilter(players: 1)) == [chrono, sonic])
        #expect(facts.arrange(games, by: .name, filter: GameFilter(genre: "Platform", players: 1)) == [sonic])
    }

    @Test func offersOnlyKnownChoices() {
        let choices = facts.choices(for: [mario, sonic, chrono])
        #expect(choices.genres == ["Platform", "Role-Playing (RPG)"])
        #expect(choices.decades == [1990])
        #expect(choices.players == [1, 2])
    }
}
