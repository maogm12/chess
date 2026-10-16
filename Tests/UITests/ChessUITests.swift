import XCTest
import UIKit

@MainActor
final class ChessUITests: ChessUITestCase {
    func testHomeEmptyLibraryAndNavigation() throws {
        try launch()
        XCTAssertTrue(app.staticTexts["ForkChess"].exists)
        assertValue(app.buttons["Play White"], "Selected")
        tap(app.buttons["Play Black"])
        assertValue(app.buttons["Play Black"], "Selected")
        assertValue(app.buttons["open-game-history"], "0 games")
        openHistory()
        XCTAssertTrue(app.staticTexts["Your games live here"].exists)
        capture("Empty history")
        tap(app.navigationBars.buttons["Home"])
        tap(app.buttons["Puzzle"])
        XCTAssertEqual(app.collectionViews.cells.count, 1)
        capture("Empty puzzle library")
        tap(app.navigationBars.buttons["Home"])
        capture("Home")
    }

    func testWhiteGameLegalInputHintUndoAndResign() throws {
        try launch()
        start()
        XCTAssertGreaterThan(square("a1").frame.minY, square("a8").frame.minY)
        tap(square("e7"))
        XCTAssertNotEqual(square("e7").value as? String, "Selected")
        tap(square("e2"))
        assertValue(square("e4"), "Legal destination")
        tap(square("e2"))
        assertValue(square("e2"), "")
        tap(square("e2"))
        tap(square("e5")) // Illegal move must leave the board/history unchanged.
        assertPiece("e2", "White pawn")
        XCTAssertFalse(move(1).exists)
        tap(app.buttons["Hint"])
        wait({ self.app.staticTexts["hint-description"].exists }, "hint notation")
        XCTAssertTrue(app.staticTexts["hint-description"].label.hasPrefix("Try "))
        capture("Hint")
        play("e2", "e4", replyPly: 2)
        XCTAssertTrue(move(1).label.hasPrefix("e4,"))
        XCTAssertFalse(app.staticTexts["hint-description"].exists)
        tap(app.buttons["Undo"])
        waitEnabled(app.buttons["Hint"])
        assertPiece("e2", "White pawn")
        XCTAssertFalse(move(1).exists)
        XCTAssertTrue(app.buttons["branch-picker"].exists)
        tap(app.buttons["Resign"])
        tap(app.buttons["Cancel"])
        XCTAssertTrue(app.buttons["Hint"].exists)
        tap(app.buttons["Resign"])
        tap(app.sheets.buttons["Resign"])
        waitEnabled(app.buttons["New Game"])
        capture("Resigned game")
        tap(app.buttons["New Game"])
        waitEnabled(app.buttons["Hint"])
        XCTAssertFalse(move(1).exists)
        XCTAssertFalse(app.buttons["branch-picker"].exists)
        XCTAssertGreaterThan(timerSeconds(), 580)
    }

    func testBlackGameOpeningPerspectiveAndUndo() throws {
        try launch()
        start(white: false)
        XCTAssertTrue(move(1).exists)
        XCTAssertFalse(app.buttons["Undo"].isEnabled, "Bot opening alone cannot be undone")
        XCTAssertGreaterThan(square("a8").frame.minY, square("a1").frame.minY)
        play("e7", "e5", replyPly: 3)
        tap(app.buttons["Undo"])
        waitEnabled(app.buttons["Hint"])
        assertPiece("e7", "Black pawn")
        XCTAssertTrue(move(1).exists)
        XCTAssertFalse(move(2).exists)
        XCTAssertFalse(app.buttons["Undo"].isEnabled)
        capture("Play Black")
    }

    func testHistoryReplayHumanRedoAndRelaunchPersistence() throws {
        try launch()
        start()
        play("e2", "e4", replyPly: 2)
        tap(app.navigationBars.buttons["Home"])
        openHistory()
        XCTAssertEqual(app.tables["saved-games"].cells.count, 1)
        tap(app.tables["saved-games"].cells.firstMatch)
        XCTAssertTrue(app.navigationBars["Review game"].exists)
        tap(move(2))
        XCTAssertFalse(app.buttons["redo-ply-2"].exists)
        tap(move(1))
        let rowFrame = move(2).frame
        waitEnabled(app.buttons["redo-ply-1"])
        XCTAssertEqual(move(2).frame.minY, rowFrame.minY, accuracy: 1)
        capture("Replay and human redo")
        tap(app.buttons["redo-ply-1"])
        waitEnabled(app.buttons["Hint"])
        play("d2", "d4", replyPly: 2)
        tap(app.navigationBars.buttons["History"])
        XCTAssertEqual(app.tables["saved-games"].cells.count, 1, "Branches stay in one saved game")
        relaunch()
        openHistory()
        XCTAssertEqual(app.tables["saved-games"].cells.count, 1)
        tap(app.tables["saved-games"].cells.firstMatch)
        XCTAssertTrue(move(1).label.hasPrefix("d4,"))
        tap(app.buttons["branch-picker"])
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Main line'")).firstMatch)
        wait({ self.move(1).label.hasPrefix("e4,") }, "persisted original continuation")
        tap(app.buttons["return-to-latest"])
        waitEnabled(app.buttons["Hint"])
        capture("Persisted branch")
    }

    func testNestedBranchesSwipePagerAndSelectedLinePGN() throws {
        try launch(games: [LibraryFixture.tree()])
        openPuzzle()
        waitEnabled(app.buttons["Hint"])
        let shared = move(1).frame
        let fork = element("fork-row-2")
        wait({ fork.exists }, "inline fork")
        fork.swipeLeft()
        wait({ self.move(3).label.hasPrefix("Bc4,") }, "swipe to branch")
        XCTAssertEqual(move(1).frame.minY, shared.minY, accuracy: 1)
        XCTAssertTrue(app.navigationBars.buttons["Puzzle"].exists, "Swipe must not navigate back")
        capture("Branch pager")
        let pager = app.pageIndicators["fork-pager-2"]
        pager.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
        wait({ self.move(3).label.hasPrefix("Nf3,") }, "page dot to main line")
        tap(app.buttons["branch-picker"])
        tap(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Branch 2'")).firstMatch)
        wait({ self.move(5).exists }, "nested continuation")
        XCTAssertTrue(move(3).label.hasPrefix("Bc4,"))
        let pgn = shareAndCopy(from: app.buttons["share-game"])
        XCTAssertTrue(pgn.contains("Bc4"))
        XCTAssertTrue(pgn.contains("d3"))
        XCTAssertFalse(pgn.contains("Nf3"))
        tap(app.buttons["return-to-latest"])
        waitEnabled(app.buttons["Hint"])
        XCTAssertTrue(move(6).exists)
    }

    func testEmptyBranchSwipeDoesNotNavigateAway() throws {
        try launch(games: [LibraryFixture.game(moves: LibraryFixture.opening, notation: LibraryFixture.openingSAN)])
        openPuzzle()
        waitEnabled(app.buttons["Hint"])
        tap(move(3))
        tap(app.buttons["redo-ply-3"])
        waitEnabled(app.buttons["Hint"])
        XCTAssertFalse(move(3).exists)
        // Drag through blank continuation space, away from any populated move row.
        let start = timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.85))
        let end = timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.85))
        start.press(forDuration: 0.1, thenDragTo: end)
        wait({ self.move(3).exists }, "empty continuation swipe to original")
        XCTAssertTrue(app.navigationBars.buttons["Puzzle"].exists)
        timeline.swipeUp()
        XCTAssertTrue(app.navigationBars.buttons["Puzzle"].exists)
    }

    func testPuzzleEditorValidationPaletteEraserClearAndSave() throws {
        try launch()
        tap(app.buttons["Puzzle"])
        tap(app.collectionViews.cells.firstMatch)
        XCTAssertTrue(app.navigationBars["New puzzle"].exists)
        XCTAssertFalse(app.navigationBars.buttons["Save"].isEnabled)
        tap(element("setup-square-a8"))
        XCTAssertFalse(app.buttons["White pawn"].isEnabled)
        tap(app.buttons["White king"])
        tap(element("setup-square-b8"))
        XCTAssertFalse(app.buttons["Black king"].isEnabled, "Adjacent kings are disabled")
        XCTAssertFalse(app.buttons["White king"].isEnabled, "Second king is disabled")
        tap(app.buttons["Eraser"])
        tap(app.buttons["Clear board"])
        XCTAssertTrue(element("setup-square-a8").label.contains("Empty square"))
        place("White king", at: "a1")
        XCTAssertFalse(app.navigationBars.buttons["Save"].isEnabled, "Both kings are required")
        place("Black king", at: "h8")
        XCTAssertTrue(app.navigationBars.buttons["Save"].isEnabled)
        place("White rook", at: "b1")
        waitEnabled(app.navigationBars.buttons["Save"])
        place("Eraser", at: "b1")
        XCTAssertTrue(element("setup-square-b1").label.contains("Empty square"))
        place("White rook", at: "b1")
        capture("Puzzle editor")
        tap(app.navigationBars.buttons["Save"])
        waitEnabled(app.buttons["Hint"])
        assertPiece("b1", "White rook")
        XCTAssertTrue(app.navigationBars.buttons["Puzzle"].exists)
        tap(app.navigationBars.buttons["Puzzle"])
        XCTAssertEqual(app.collectionViews.cells.count, 2)
        capture("Saved puzzle library")
        tap(app.collectionViews.cells.element(boundBy: 1))
        waitEnabled(app.buttons["Hint"])
        play("b1", "b2", replyPly: 2)
        tap(app.navigationBars.buttons["Puzzle"])
        tap(app.navigationBars.buttons["Home"])
        openHistory()
        tap(app.tables["saved-games"].cells.firstMatch)
        waitEnabled(app.buttons["Hint"])
        assertPiece("b2", "White rook")
        XCTAssertTrue(app.navigationBars.buttons["History"].exists)
    }

    func testBlackPuzzleEditorFlipsAndNavigationBarAdd() throws {
        try launch()
        tap(app.buttons["Puzzle"])
        tap(app.navigationBars.buttons["Add puzzle"])
        tap(app.segmentedControls.buttons["Black"])
        XCTAssertGreaterThan(element("setup-square-a8").frame.minY, element("setup-square-a1").frame.minY)
        place("Black king", at: "h8")
        place("White king", at: "a1")
        place("Black rook", at: "g8")
        tap(app.navigationBars.buttons["Save"])
        waitEnabled(app.buttons["Hint"])
        XCTAssertGreaterThan(square("a8").frame.minY, square("a1").frame.minY)
        play("g8", "g7", replyPly: 2)
        XCTAssertTrue(move(1).label.hasPrefix("Rg7,"))
        capture("Black puzzle")
    }

    func testPuzzleBotOpeningAndUndoPreservesOpening() throws {
        let record = LibraryFixture.game(fen: "4k3/8/8/8/8/8/8/K3R3 b - - 0 1", white: true)
        try launch(games: [record])
        openPuzzle()
        waitEnabled(app.buttons["Hint"])
        XCTAssertTrue(move(1).exists)
        XCTAssertFalse(app.buttons["Undo"].isEnabled)
        XCTAssertGreaterThan(square("a8").frame.minY, square("a1").frame.minY)
        play("e1", "e2", replyPly: 3)
        tap(app.buttons["Undo"])
        waitEnabled(app.buttons["Hint"])
        XCTAssertTrue(move(1).exists)
        XCTAssertFalse(move(2).exists)
        assertPiece("e1", "White rook")
        relaunch()
        openPuzzle()
        waitEnabled(app.buttons["Hint"])
        XCTAssertTrue(move(1).exists)
        XCTAssertFalse(move(2).exists)
    }

    func testPuzzleContextShareAndDelete() throws {
        try launch(games: [LibraryFixture.game(fen: "7k/8/8/8/8/8/8/KR6 w - - 0 1")])
        tap(app.buttons["Puzzle"])
        app.collectionViews.cells.element(boundBy: 1).press(forDuration: 1)
        let pgn = shareAndCopy(from: app.buttons["Share PGN"])
        XCTAssertTrue(pgn.contains("[FEN \"7k/8/8/8/8/8/8/KR6 w - - 0 1\"]"))
        app.collectionViews.cells.element(boundBy: 1).press(forDuration: 1)
        tap(app.buttons["Delete"])
        wait({ self.app.collectionViews.cells.count == 1 }, "puzzle deleted")
        relaunch()
        tap(app.buttons["Puzzle"])
        XCTAssertEqual(app.collectionViews.cells.count, 1)
    }

    func testHistoryShareDeleteCancelConfirmAndPersistence() throws {
        let record = LibraryFixture.game(puzzle: false, moves: LibraryFixture.opening, notation: LibraryFixture.openingSAN)
        try launch(games: [record])
        openHistory()
        let pgn = shareAndCopy(from: app.buttons["Share PGN"])
        XCTAssertTrue(pgn.hasPrefix("[Event \"ForkChess practice\"]"))
        XCTAssertTrue(pgn.contains("1. e4 e5 2. Nf3 Nc6"))
        app.tables["saved-games"].cells.firstMatch.swipeLeft()
        tap(app.buttons["Delete"])
        tap(app.alerts.buttons["Cancel"])
        XCTAssertEqual(app.tables["saved-games"].cells.count, 1)
        app.tables["saved-games"].cells.firstMatch.swipeLeft()
        tap(app.buttons["Delete"])
        tap(app.alerts.buttons["Delete"])
        wait({ self.app.staticTexts["Your games live here"].exists }, "empty history after deletion")
        relaunch()
        openHistory()
        XCTAssertTrue(app.staticTexts["Your games live here"].exists)
    }

    func testAllGlobalSettingsAndLicensePersist() throws {
        try launch()
        openSettings()
        choose("Play as", option: "Black")
        choose("Practice duration", option: "15 minutes")
        choose("Bot strength", option: "Expert")
        assertValue(app.buttons["Bot strength"], "Expert · ≈2960 Elo")
        let slider = app.sliders["Bot skill level"]
        slider.adjust(toNormalizedSliderPosition: 0.45)
        wait({ (self.app.sliders["Bot skill level"].value as? String) == "9 of 20" }, "exact slider level")
        tap(app.buttons["Bot strength"])
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Club'")).firstMatch.exists)
        // Selecting a preset closes the native menu and checks both control paths.
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Beginner'")).firstMatch)
        choose("Thinking time", option: "Quick")
        for name in ["Rate each move", "Show legal moves", "Show coordinates", "Move haptics"] {
            let control = app.switches[name]
            reveal(control)
            tap(control)
        }
        choose("Board colors", option: "Forest")
        choose("Board colors", option: "Walnut")
        let license = app.staticTexts["Engine license (MIT)"]
        reveal(license)
        XCTAssertTrue(app.staticTexts["No account or internet required"].exists)
        tap(license)
        XCTAssertTrue(app.navigationBars["Arasan · MIT"].exists)
        XCTAssertTrue((app.textViews["engine-license"].value as? String)?.contains("Permission is hereby granted") == true)
        capture("Engine license")
        tap(app.navigationBars.buttons["Settings"])
        done()
        relaunch()
        assertValue(app.buttons["Play Black"], "Selected")
        openSettings()
        assertValue(app.buttons["Practice duration"], "15 minutes")
        assertValue(app.buttons["Bot strength"], "Beginner · ≈1245 Elo")
        reveal(app.switches["Rate each move"])
        assertValue(app.switches["Rate each move"], "1")
        reveal(app.buttons["Board colors"])
        assertValue(app.buttons["Board colors"], "Walnut")
        assertValue(app.switches["Show legal moves"], "0")
        assertValue(app.switches["Show coordinates"], "0")
        assertValue(app.switches["Move haptics"], "1")
        capture("Global settings")
    }

    func testGameSettingsDefaultsAndOtherGamesStayIndependent() throws {
        try launch()
        start()
        openSettings(game: true)
        XCTAssertFalse(app.buttons["Play as"].exists)
        XCTAssertFalse(app.buttons["Board colors"].exists)
        choose("Bot strength", option: "Expert")
        choose("Thinking time", option: "Balanced")
        tap(app.switches["Rate each move"])
        choose("Practice duration", option: "5 minutes")
        capture("Game settings")
        done()
        XCTAssertGreaterThan(timerSeconds(), 285)
        XCTAssertLessThanOrEqual(timerSeconds(), 300)
        tap(app.navigationBars.buttons["Home"])
        openSettings()
        assertValue(app.buttons["Bot strength"], "Beginner · ≈1245 Elo")
        assertValue(app.buttons["Practice duration"], "10 minutes")
        done()
        start()
        openSettings(game: true)
        assertValue(app.buttons["Bot strength"], "Beginner · ≈1245 Elo")
        done()
        tap(app.navigationBars.buttons["Home"])
        openHistory()
        XCTAssertEqual(app.tables["saved-games"].cells.count, 2)
        tap(app.tables["saved-games"].cells.element(boundBy: 1))
        openSettings(game: true)
        assertValue(app.buttons["Bot strength"], "Expert · ≈2960 Elo")
        reveal(app.switches["Rate each move"])
        assertValue(app.switches["Rate each move"], "1")
        done()
        relaunch()
        openHistory()
        tap(app.tables["saved-games"].cells.element(boundBy: 1))
        openSettings(game: true)
        assertValue(app.buttons["Bot strength"], "Expert · ≈2960 Elo")
    }

    func testRatingsAppearAndSurviveReplayRelaunch() throws {
        try launch(settings: ["rateMoves": true])
        start()
        play("e2", "e4", replyPly: 2)
        let ratings = timeline.staticTexts.matching(NSPredicate(format: "label IN {'Good', 'OK', 'Bad'}"))
        wait({ ratings.count == 2 }, "both move ratings")
        capture("Move ratings")
        relaunch()
        openHistory()
        tap(app.tables["saved-games"].cells.firstMatch)
        XCTAssertEqual(ratings.count, 2)
        tap(move(1))
        XCTAssertEqual(ratings.count, 2)
        tap(app.buttons["return-to-latest"])
        waitEnabled(app.buttons["Hint"])
        tap(app.buttons["Undo"])
        waitEnabled(app.buttons["Hint"])
        XCTAssertEqual(ratings.count, 0)
    }

    func testBoardPreferencesApplyToExistingGames() throws {
        try launch(games: [LibraryFixture.game()])
        openSettings()
        choose("Board colors", option: "Forest")
        for name in ["Show legal moves", "Show coordinates"] {
            reveal(app.switches[name])
            tap(app.switches[name])
        }
        done()
        openPuzzle()
        waitEnabled(app.buttons["Hint"])
        tap(square("e2"))
        assertValue(square("e2"), "Selected")
        assertValue(square("e4"), "")
        capture("Forest without coordinates or legal markers")
        tap(square("e4"))
        wait({ self.move(2).exists }, "legal move with markers disabled")
        tap(app.navigationBars.buttons["Puzzle"])
        tap(app.navigationBars.buttons["Home"])
        openSettings()
        choose("Board colors", option: "Walnut")
        reveal(app.switches["Show legal moves"])
        tap(app.switches["Show legal moves"])
        done()
        openPuzzle()
        waitEnabled(app.buttons["Hint"])
        tap(square("d2"))
        assertValue(square("d4"), "Legal destination")
        capture("Walnut with legal markers restored")
    }

    func testGameDurationOnlyResetsSelectedBranch() throws {
        try launch(games: [LibraryFixture.tree()])
        openPuzzle()
        waitEnabled(app.buttons["Hint"])
        XCTAssertGreaterThan(timerSeconds(), 400)
        openSettings(game: true)
        choose("Practice duration", option: "15 minutes")
        done()
        XCTAssertGreaterThan(timerSeconds(), 880)
        tap(app.buttons["branch-picker"])
        tap(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Branch 1'")).firstMatch)
        tap(app.buttons["return-to-latest"])
        waitEnabled(app.buttons["Hint"])
        XCTAssertGreaterThan(timerSeconds(), 280)
        XCTAssertLessThanOrEqual(timerSeconds(), 300)
        tap(app.buttons["branch-picker"])
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Main line'")).firstMatch)
        tap(app.buttons["return-to-latest"])
        waitEnabled(app.buttons["Hint"])
        XCTAssertGreaterThan(timerSeconds(), 860)
        capture("Independent branch timers")
    }

    func testCastlingBothSidesAndUndo() throws {
        for (destination, rookDestination) in [("g1", "f1"), ("c1", "d1")] {
            try launch(games: [LibraryFixture.game(fen: "4k3/8/8/8/8/8/8/R3K2R w KQ - 0 1")])
            openPuzzle()
            play("e1", destination, replyPly: 2)
            assertPiece(destination, "White king")
            assertPiece(rookDestination, "White rook")
            capture("Castling \(destination)")
            tap(app.buttons["Undo"])
            waitEnabled(app.buttons["Hint"])
            assertPiece("e1", "White king")
            assertPiece("a1", "White rook")
            assertPiece("h1", "White rook")
        }
    }

    func testEnPassantCaptureTrayAndUndo() throws {
        try launch(games: [LibraryFixture.game(fen: "7k/8/8/3pP3/8/8/8/7K w - d6 0 2")])
        openPuzzle()
        play("e5", "d6", replyPly: 2)
        assertPiece("d6", "White pawn")
        assertPiece("d5", "Empty")
        assertValue(element("Captured by White"), "pawn")
        capture("En passant")
        tap(app.buttons["Undo"])
        waitEnabled(app.buttons["Hint"])
        assertPiece("e5", "White pawn")
        assertPiece("d5", "Black pawn")
        assertValue(element("Captured by White"), "None")
    }

    func testAllPromotionChoicesForBothColors() throws {
        for white in [true, false] {
            for (kind, name) in [("q", "queen"), ("r", "rook"), ("b", "bishop"), ("n", "knight")] {
                let fen = white ? "7k/P7/8/8/8/8/8/7K w - - 0 1" : "7k/8/8/8/8/8/p7/7K b - - 0 1"
                try launch(games: [LibraryFixture.game(fen: fen, white: white)])
                openPuzzle()
                let destination = white ? "a8" : "a1"
                play(white ? "a7" : "a2", destination)
                XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'promote-'")).count, 4)
                assertValue(square(destination), "Awaiting promotion")
                tap(app.buttons["promote-\(kind)"])
                assertPiece(destination, "\(white ? "White" : "Black") \(name)")
                wait({ self.move(1).exists }, "promotion notation")
                XCTAssertTrue(move(1).label.contains("=\(kind.uppercased())"))
                capture("\(white ? "White" : "Black") promotion \(kind)")
            }
        }
    }

    func testPromotionCaptureOutsideDismissRestoresPositionAndHistory() throws {
        for white in [true, false] {
            let fen = white ? "1r5k/P7/8/8/8/8/8/7K w - - 0 1" : "7k/8/8/8/8/8/p7/1R5K b - - 0 1"
            try launch(games: [LibraryFixture.game(fen: fen, white: white)])
            openPuzzle()
            let source = white ? "a7" : "a2"
            let destination = white ? "b8" : "b1"
            play(source, destination)
            assertValue(square(destination), "Awaiting promotion")
            capture("Pending capture promotion")
            // A real outside tap exercises UIKit's dismissal delegate.
            square(white ? "h1" : "h8").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            wait({ !self.app.buttons["promote-q"].exists }, "outside promotion dismissal")
            assertPiece(source, "\(white ? "White" : "Black") pawn")
            assertPiece(destination, "\(white ? "Black" : "White") rook")
            XCTAssertFalse(move(1).exists)
            play(source, destination)
            tap(app.buttons["promote-q"])
            assertPiece(destination, "\(white ? "White" : "Black") queen")
            relaunch()
            openPuzzle()
            assertPiece(destination, "\(white ? "White" : "Black") queen")
        }
    }

    func testCheckmateReplayRedoAndNewGame() throws {
        let record = LibraryFixture.game(white: false, moves: ["f2f3", "e7e5", "g2g4"],
                                         notation: ["f3", "e5", "g4"])
        try launch(games: [record])
        openPuzzle()
        play("d8", "h4")
        waitEnabled(app.buttons["New Game"])
        assertValue(square("e1"), "Checkmate")
        XCTAssertTrue(move(4).label.contains("Qh4#"))
        capture("Checkmate")
        tap(move(3))
        assertValue(square("e1"), "")
        XCTAssertFalse(app.buttons["redo-ply-3"].exists)
        tap(move(4))
        assertValue(square("e1"), "Checkmate")
        tap(app.buttons["redo-ply-4"])
        waitEnabled(app.buttons["Hint"])
        assertPiece("d8", "Black queen")
        XCTAssertFalse(move(4).exists)
        play("d8", "h4")
        waitEnabled(app.buttons["New Game"])
        tap(app.buttons["New Game"])
        waitEnabled(app.buttons["Hint"])
        XCTAssertFalse(move(1).exists)
    }

    func testCheckMarkerFollowsHistoricalSelection() throws {
        let record = LibraryFixture.game(white: false, moves: ["e2e4", "d7d6", "f1b5"],
                                         notation: ["e4", "d6", "Bb5+"])
        try launch(games: [record])
        openPuzzle()
        waitEnabled(app.buttons["Hint"])
        assertValue(square("e8"), "Check")
        capture("Check")
        tap(move(2))
        assertValue(square("e8"), "")
        tap(move(3))
        assertValue(square("e8"), "Check")
        tap(app.buttons["return-to-latest"])
        waitEnabled(app.buttons["Hint"])
        assertValue(square("e8"), "Check")
    }

    func testStalemateInsufficientMaterialAndFiftyMoveDraw() throws {
        let scenarios: [(String, String?, String?, String, String?)] = [
            ("7k/5K2/8/6Q1/8/8/8/8 w - - 0 1", "g5", "g6", "Stalemate", "h8"),
            ("7k/8/8/8/8/8/8/7K w - - 0 1", nil, nil, "Insufficient material", nil),
            ("7k/8/8/8/8/8/8/KR6 w - - 99 1", "b1", "b2", "50", nil)
        ]
        for (fen, from, to, reason, markedKing) in scenarios {
            try launch(games: [LibraryFixture.game(fen: fen)])
            openPuzzle()
            if let from, let to { play(from, to) }
            waitEnabled(app.buttons["New Game"])
            if let markedKing { assertValue(square(markedKing), "Stalemate") }
            let pgn = shareAndCopy(from: app.buttons["share-game"])
            XCTAssertTrue(pgn.contains("[Result \"1/2-1/2\"]"), reason)
            capture("Draw \(reason)")
        }
    }

    func testThreefoldRepetitionFromSavedLine() throws {
        let moves = ["g1f3", "g8f6", "f3g1", "f6g8", "g1f3", "g8f6", "f3g1", "f6g8"]
        let notation = ["Nf3", "Nf6", "Ng1", "Ng8", "Nf3", "Nf6", "Ng1", "Ng8"]
        try launch(games: [LibraryFixture.game(moves: moves, notation: notation)])
        openPuzzle()
        waitEnabled(app.buttons["New Game"])
        let pgn = shareAndCopy(from: app.buttons["share-game"])
        XCTAssertTrue(pgn.contains("[Result \"1/2-1/2\"]"))
        tap(move(7))
        XCTAssertTrue(app.navigationBars["Review game"].exists)
        capture("Threefold replay")
    }

    func testTimerPausesAwayBackgroundAndRestores() throws {
        try launch(games: [LibraryFixture.game(fen: "7k/8/8/8/8/8/8/KR6 w - - 0 1", seconds: 120)])
        openPuzzle()
        waitEnabled(app.buttons["Hint"])
        let before = timerSeconds()
        XCTAssertGreaterThan(before, 105)
        wait({ self.timerSeconds() < before }, "running countdown")
        let beforeBackground = timerSeconds()
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        // A bounded background interval establishes that the countdown is paused.
        let background = XCTestExpectation(description: "App stays in the background")
        background.isInverted = true
        wait(for: [background], timeout: 8)
        app.activate()
        waitEnabled(app.buttons["Hint"])
        XCTAssertGreaterThan(timerSeconds(), beforeBackground - 6)
        let beforeAway = timerSeconds()
        tap(app.navigationBars.buttons["Puzzle"])
        let away = XCTestExpectation(description: "Practice stays off screen")
        away.isInverted = true
        wait(for: [away], timeout: 8)
        relaunch()
        openPuzzle()
        waitEnabled(app.buttons["Hint"])
        XCTAssertGreaterThan(timerSeconds(), beforeAway - 5)
        XCTAssertLessThanOrEqual(timerSeconds(), before)
        capture("Restored timer")
    }

    func testTimerExpiresWithoutEndingGame() throws {
        try launch(games: [LibraryFixture.game(fen: "7k/8/8/8/8/8/8/KR6 w - - 0 1", seconds: 3)])
        openPuzzle()
        waitEnabled(app.buttons["Hint"])
        wait({ self.timerSeconds() == 0 }, "timer expiry")
        XCTAssertFalse(app.buttons["New Game"].exists, "Timer expiry must not force a result")
        play("b1", "b2", replyPly: 2)
        XCTAssertEqual(timerSeconds(), 0)
        capture("Expired timer still playable")
    }

    func testLeavingDuringSearchCannotMutateAnotherGame() throws {
        try launch(settings: ["thinkSeconds": 2])
        start()
        tap(square("e2"))
        tap(square("e4"))
        wait({ self.move(1).exists }, "human move accepted")
        tap(app.navigationBars.buttons["Home"])
        start()
        waitEnabled(app.buttons["Hint"])
        XCTAssertFalse(move(1).exists)
        tap(app.buttons["Hint"])
        tap(app.navigationBars.buttons["Home"])
        start()
        waitEnabled(app.buttons["Hint"])
        XCTAssertFalse(move(1).exists)
        XCTAssertFalse(app.staticTexts["hint-description"].exists)
        openSettings(game: true) // Keep the new game alive while obsolete searches finish.
        done()
        waitEnabled(app.buttons["Hint"])
        XCTAssertFalse(move(1).exists)
        XCTAssertFalse(app.staticTexts["hint-description"].exists)
        capture("Search invalidation")
    }

    func testLegacyManualLibraryMigrationThroughRealLaunch() throws {
        var record = LibraryFixture.game(white: true, moves: LibraryFixture.opening, notation: LibraryFixture.openingSAN)
        record.removeValue(forKey: "isPuzzle")
        record["mode"] = "board"
        try launch(games: [record])
        openPuzzle()
        waitEnabled(app.buttons["Hint"])
        XCTAssertTrue(move(4).exists)
        assertPiece("f3", "White knight")
        play("f1", "c4", replyPly: 6)
        relaunch()
        openPuzzle()
        waitEnabled(app.buttons["Hint"])
        XCTAssertTrue(move(6).exists)
        assertPiece("c4", "White bishop")
    }

    func testLightAndDarkPagesRemainUsableAfterRotation() throws {
        for appearance in ["Light", "Dark"] {
            try launch(games: [LibraryFixture.tree()], appearance: appearance)
            capture("\(appearance) Home")
            openSettings()
            capture("\(appearance) Settings")
            let license = app.staticTexts["Engine license (MIT)"]
            reveal(license)
            tap(license)
            XCTAssertTrue(app.navigationBars["Arasan · MIT"].exists)
            capture("\(appearance) License")
            tap(app.navigationBars.buttons["Settings"])
            done()
            openHistory()
            capture("\(appearance) History")
            tap(app.navigationBars.buttons["Home"])
            tap(app.buttons["Puzzle"])
            capture("\(appearance) Puzzle library")
            tap(app.navigationBars.buttons["Add puzzle"])
            capture("\(appearance) Puzzle editor")
            tap(element("setup-square-d4"))
            capture("\(appearance) Piece picker")
            tap(app.buttons["Eraser"])
            tap(app.navigationBars.buttons["Puzzle"])
            tap(app.collectionViews.cells.element(boundBy: 1))
            waitEnabled(app.buttons["Hint"])
            capture("\(appearance) Game portrait")
            openSettings(game: true)
            capture("\(appearance) Game settings")
            done()
            XCUIDevice.shared.orientation = .landscapeLeft
            wait({ self.app.frame.width > self.app.frame.height }, "landscape")
            waitEnabled(app.buttons["Hint"])
            XCTAssertTrue(square("a1").isHittable)
            XCTAssertTrue(square("h8").isHittable)
            capture("\(appearance) Game landscape")
            tap(move(1))
            XCTAssertTrue(app.buttons["redo-ply-1"].exists)
            capture("\(appearance) Replay landscape")
            XCUIDevice.shared.orientation = .portrait
            try launch(games: [LibraryFixture.game(fen: "7k/P7/8/8/8/8/8/7K w - - 0 1")],
                       appearance: appearance)
            openPuzzle()
            play("a7", "a8")
            waitEnabled(app.buttons["promote-q"])
            capture("\(appearance) Promotion picker")
        }
    }
}
