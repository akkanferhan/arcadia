import Foundation
import Testing
@testable import Arcadia

private func game(_ title: String, _ system: String = "snes") -> Game {
    Game(url: URL(fileURLWithPath: "/g/\(system)/\(title) (USA).rom"), systemID: system)
}

private let mario = game("Super Mario World")
private let zelda = game("Zelda")
private let metroid = game("Metroid Fusion", "gba")
private let crash = game("Crash Bandicoot", "ps1")
private let library = [crash, metroid, mario, zelda]

@Suite struct TVShelfTests {
    @Test func ordersContinueFavoritesThenConsoles() {
        let shelves = TVShelf.make(games: library, recentlyPlayed: [zelda], favorites: [metroid])
        #expect(shelves.map(\.kind) == [.continuePlaying, .favorites, .system("ps1"), .system("snes"), .system("gba")]
                    .sorted { order($0) < order($1) })
        #expect(shelves[0].games == [zelda])
        #expect(shelves[1].games == [metroid])
        #expect(shelves.first { $0.kind == .system("snes") }?.games == [mario, zelda])
    }

    @Test func skipsEmptyShelves() {
        let shelves = TVShelf.make(games: [mario], recentlyPlayed: [], favorites: [])
        #expect(shelves.map(\.kind) == [.system("snes")])
        #expect(TVShelf.make(games: [], recentlyPlayed: [], favorites: []).isEmpty)
    }

    @Test func searchShowsOnlyMatches() {
        let shelves = TVShelf.make(games: library, recentlyPlayed: [zelda], favorites: [], query: "mar")
        #expect(shelves.map(\.kind) == [.results])
        #expect(shelves[0].games == [mario])
        #expect(TVShelf.make(games: library, recentlyPlayed: [], favorites: [], query: "xyz").isEmpty)
        #expect(TVShelf.make(games: library, recentlyPlayed: [], favorites: [], query: "  ").count == 3)
    }

    /// Catalog order of the consoles, after the two fixed shelves.
    private func order(_ kind: TVShelf.Kind) -> Int {
        switch kind {
        case .continuePlaying: -2
        case .favorites: -1
        case .results: 1000
        case .system(let id): GameSystem.all.firstIndex { $0.id == id }!
        }
    }
}

@Suite struct TVFocusTests {
    private var shelves: [TVShelf] {
        [TVShelf(kind: .continuePlaying, games: [zelda, metroid, crash]),
         TVShelf(kind: .system("snes"), games: [mario, zelda])]
    }

    @Test func movesWithinAndAcrossShelves() {
        var focus = TVFocus(shelves: shelves)
        #expect(focus.game == zelda)
        let r1 = focus.move(.left)
        #expect(!r1)
        let r2 = focus.move(.up)
        #expect(!r2)
        let r3 = focus.move(.right)
        #expect(r3)
        let r4 = focus.move(.right)
        #expect(r4)
        #expect(focus.game == crash)
        let r5 = focus.move(.right)
        #expect(!r5)
        let r6 = focus.move(.down)
        #expect(r6)
        #expect(focus.game == mario)
        let r7 = focus.move(.down)
        #expect(!r7)
    }

    @Test func everyShelfRemembersItsPosition() {
        var focus = TVFocus(shelves: shelves)
        focus.move(.right)
        focus.move(.down)
        focus.move(.right)
        #expect(focus.game == zelda)
        focus.move(.up)
        #expect(focus.game == metroid)
        focus.move(.down)
        #expect(focus.game == zelda)
    }

    @Test func updateKeepsTheFocusedGame() {
        var focus = TVFocus(shelves: shelves)
        focus.move(.down)
        focus.move(.right)
        #expect(focus.game == zelda)
        // A new favorite adds a shelf above and Zelda moves within its shelf.
        focus.update([TVShelf(kind: .continuePlaying, games: [zelda, metroid, crash]),
                      TVShelf(kind: .favorites, games: [crash]),
                      TVShelf(kind: .system("snes"), games: [game("Aladdin"), mario, zelda])])
        #expect(focus.row == 2)
        #expect(focus.game == zelda)
    }

    @Test func updateClampsWhenTheShelfGoesAway() {
        var focus = TVFocus(shelves: [TVShelf(kind: .favorites, games: [mario]),
                                      TVShelf(kind: .system("snes"), games: [mario, zelda])])
        focus.move(.down)
        focus.update([TVShelf(kind: .favorites, games: [mario])])
        #expect(focus.row == 0)
        #expect(focus.game == mario)
        focus.update([])
        #expect(focus.game == nil)
        let r8 = focus.move(.right)
        #expect(!r8)
    }

    @Test func clickFocusesDirectly() {
        var focus = TVFocus(shelves: shelves)
        focus.focus(row: 0, column: 2)
        #expect(focus.game == crash)
        focus.focus(row: 5, column: 0)
        #expect(focus.game == crash)
    }
}

@Suite struct TVNavigatorTests {
    private func navigator() -> TVNavigator {
        var navigator = TVNavigator()
        navigator.focus.update([TVShelf(kind: .continuePlaying, games: [zelda, metroid]),
                                TVShelf(kind: .system("snes"), games: [mario, zelda])])
        return navigator
    }

    @Test func buttonsMapToEffects() {
        var navigator = navigator()
        let r9 = navigator.handle(.select)
        #expect(r9 == .play(zelda))
        let r10 = navigator.handle(.favorite)
        #expect(r10 == .toggleFavorite(zelda))
        let r11 = navigator.handle(.options)
        #expect(r11 == .options(zelda))
        let r12 = navigator.handle(.move(.left))
        #expect(r12 == .bump)
        let r13 = navigator.handle(.move(.right))
        #expect(r13 == TVEffect.none)
        let r14 = navigator.handle(.select)
        #expect(r14 == .play(metroid))
    }

    @Test func backGoesToTheTopThenExits() {
        var navigator = navigator()
        _ = navigator.handle(.move(.down))
        let r15 = navigator.handle(.back)
        #expect(r15 == TVEffect.none)
        #expect(navigator.focus.row == 0)
        let r16 = navigator.handle(.back)
        #expect(r16 == .exit)
    }

    @Test func searchingWithTheOnScreenKeyboard() {
        var navigator = navigator()
        let r17 = navigator.handle(.search)
        #expect(r17 == TVEffect.none)
        #expect(navigator.isSearching)
        // A, then right to B.
        _ = navigator.handle(.select)
        _ = navigator.handle(.move(.right))
        _ = navigator.handle(.select)
        #expect(navigator.query == "AB")
        // Buttons that act on games do nothing while typing.
        let r18 = navigator.handle(.favorite)
        #expect(r18 == TVEffect.none)
        let r19 = navigator.handle(.deleteBackward)
        #expect(r19 == TVEffect.none)
        #expect(navigator.query == "A")
        // Down from the last row of keys goes to the results.
        for _ in 0..<3 { _ = navigator.handle(.move(.down)) }
        #expect(!navigator.isSearching)
        #expect(navigator.query == "A")
        // Up from the results reopens the keyboard; B closes it, then clears the search, then exits.
        _ = navigator.handle(.move(.up))
        #expect(navigator.isSearching)
        _ = navigator.handle(.back)
        #expect(!navigator.isSearching)
        _ = navigator.handle(.back)
        #expect(navigator.query.isEmpty)
        let r20 = navigator.handle(.back)
        #expect(r20 == .exit)
    }

    @Test func typingOnAHardwareKeyboardStartsASearch() {
        var navigator = navigator()
        _ = navigator.handle(.type("z"))
        #expect(navigator.isSearching)
        #expect(navigator.query == "z")
        // Return closes the keyboard and keeps the search.
        _ = navigator.handle(.search)
        #expect(!navigator.isSearching)
        #expect(navigator.query == "z")
    }

    @Test func keyboardKeysDoTheirJob() {
        var navigator = navigator()
        _ = navigator.handle(.search)
        // Space does nothing before the first letter.
        _ = navigator.handle(.move(.down))
        _ = navigator.handle(.move(.down))
        for _ in 0..<10 { _ = navigator.handle(.move(.right)) }
        #expect(navigator.keyboard?.key == .space)
        _ = navigator.handle(.select)
        #expect(navigator.query.isEmpty)
        _ = navigator.handle(.move(.right))
        #expect(navigator.keyboard?.key == .delete)
        _ = navigator.handle(.move(.right))
        #expect(navigator.keyboard?.key == .done)
        let r21 = navigator.handle(.move(.right))
        #expect(r21 == .bump)
        _ = navigator.handle(.select)
        #expect(!navigator.isSearching)
    }
}

@Suite struct TVKeyboardTests {
    @Test func movesAcrossRowsOfDifferentLengths() {
        var keyboard = TVKeyboard()
        #expect(keyboard.key == .character("A"))
        let r22 = keyboard.move(.up)
        #expect(!r22)
        let r23 = keyboard.move(.left)
        #expect(!r23)
        for _ in 0..<12 { keyboard.move(.right) }
        #expect(keyboard.key == .character("M"))
        keyboard.move(.down)
        #expect(keyboard.key == .character("Z"))
        keyboard.move(.down)
        #expect(keyboard.key == .done)
        let r24 = keyboard.move(.down)
        #expect(!r24)
    }
}

@Suite struct TVInputTests {
    @Test func stickDirectionsUseADeadZone() {
        #expect(TVDirection.resolve(x: 0.2, y: 0.1) == nil)
        #expect(TVDirection.resolve(x: 0.9, y: 0.3) == .right)
        #expect(TVDirection.resolve(x: -0.6, y: 0) == .left)
        #expect(TVDirection.resolve(x: 0.1, y: 0.8) == .up)
        #expect(TVDirection.resolve(x: 0, y: -1) == .down)
    }

    @Test func aHeldDirectionReleasesLater() {
        // 0.4 alone isn't a press, but it keeps a held direction going.
        #expect(TVDirection.resolve(x: 0.4, y: 0) == nil)
        #expect(TVDirection.resolve(x: 0.4, y: 0, held: .right) == .right)
        #expect(TVDirection.resolve(x: 0.2, y: 0, held: .right) == nil)
        // A firm push the other way wins over the held direction.
        #expect(TVDirection.resolve(x: -0.9, y: 0, held: .right) == .left)
    }

    @Test func keysMapToButtons() {
        #expect(TVKeyMap.command(keyCode: 123, characters: nil, searching: false) == .move(.left))
        #expect(TVKeyMap.command(keyCode: 126, characters: nil, searching: true) == .move(.up))
        #expect(TVKeyMap.command(keyCode: 36, characters: "\r", searching: false) == .select)
        #expect(TVKeyMap.command(keyCode: 36, characters: "\r", searching: true) == .search)
        #expect(TVKeyMap.command(keyCode: 53, characters: nil, searching: false) == .back)
        #expect(TVKeyMap.command(keyCode: 3, characters: "f", searching: false) == .favorite)
        #expect(TVKeyMap.command(keyCode: 3, characters: "f", searching: true) == .type("f"))
        #expect(TVKeyMap.command(keyCode: 44, characters: "/", searching: false) == .search)
        #expect(TVKeyMap.command(keyCode: 49, characters: " ", searching: false) == .options)
        #expect(TVKeyMap.command(keyCode: 49, characters: " ", searching: true) == .type(" "))
        #expect(TVKeyMap.command(keyCode: 51, characters: nil, searching: true) == .deleteBackward)
        #expect(TVKeyMap.command(keyCode: 0, characters: "a", searching: false) == nil)
    }
}
