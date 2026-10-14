import XCTest
import UIKit
import Combine
@testable import LocalChess

private final class TimelineTestPan: UIPanGestureRecognizer {
    var phase: UIGestureRecognizer.State = .possible
    var point: CGPoint = .zero
    var travel: CGPoint = .zero
    override var state: UIGestureRecognizer.State {
        get { phase }
        set { phase = newValue }
    }
    override func location(in view: UIView?) -> CGPoint { point }
    override func translation(in view: UIView?) -> CGPoint { travel }
}

@MainActor
final class GameTests: XCTestCase {
    func waitUntil(_ label: String, _ condition: @escaping () -> Bool) async throws {
        for _ in 0..<250 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 40_000_000)
        }
        XCTFail("Timed out: " + label)
        throw ChessError.engine("Timeout: " + label)
    }
    func makeGame(now: @escaping () -> Date = Date.init) async throws -> (GameViewModel, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("library.json")
        let model = GameViewModel(storageURL: url, now: now)
        try await waitUntil("engine ready") { model.ready }
        XCTAssertNil(model.errorMessage)
        model.settings.thinkSeconds = 0.4
        return (model, url)
    }
    func settle(_ game: GameViewModel) async throws {
        // Yield once because new-game/review starts an asynchronous task.
        try await Task.sleep(nanoseconds: 80_000_000)
        try await waitUntil("idle") { !game.busy && !game.isThinking && !game.isHinting && !game.isRating }
        XCTAssertNil(game.errorMessage)
    }
    func play(_ uci: String, in game: GameViewModel) async throws {
        let move = try XCTUnwrap(game.snapshot?.legal.first { $0.uci == uci })
        game.play(move)
        try await settle(game)
    }

    func testWhiteGameHintUndoAndResign() async throws {
        let (game, _) = try await makeGame()
        game.newGame()
        try await settle(game)
        XCTAssertTrue(game.inputAllowed)
        game.handleTap(squareIndex("e2"))
        XCTAssertEqual(game.legalTargets, Set([squareIndex("e3"), squareIndex("e4")]))
        try await play("e2e4", in: game)
        XCTAssertEqual(game.active?.moves.count, 2)
        XCTAssertEqual(game.moves.first, "e4")
        game.requestHint()
        try await settle(game)
        XCTAssertNotNil(game.hint)
        XCTAssertTrue(game.snapshot!.legal.contains(game.hint!))
        XCTAssertEqual(game.active?.moves.count, 2)
        game.undo()
        try await settle(game)
        XCTAssertEqual(game.active?.moves, [])
        game.resign()
        XCTAssertTrue(game.gameOver)
        XCTAssertFalse(game.inputAllowed)
        XCTAssertEqual(game.active?.result, "0-1")
    }

    func testBlackGameAndUndo() async throws {
        let (game, _) = try await makeGame()
        game.settings.playWhite = false
        game.newGame()
        try await settle(game)
        XCTAssertEqual(game.active?.moves.count, 1)
        XCTAssertFalse(game.whiteAtBottom)
        XCTAssertFalse(game.whiteToMove)
        let move = try XCTUnwrap(game.snapshot?.legal.first)
        game.play(move)
        try await settle(game)
        XCTAssertEqual(game.active?.moves.count, 3)
        game.undo()
        try await settle(game)
        XCTAssertEqual(game.active?.moves.count, 1)
        XCTAssertTrue(game.inputAllowed)
    }

    func testCompleteGameHistoryReplayPGNAndPersistence() async throws {
        let (game, url) = try await makeGame()
        game.settings.boardTheme = "Forest"
        game.settings.coordinates = false
        game.settings.skill = 13
        game.newGame()
        try await settle(game)
        var completed = try XCTUnwrap(game.active)
        completed.moves = ["f2f3", "e7e5", "g2g4", "d8h4"]
        game.openPuzzle(completed)
        try await settle(game)
        XCTAssertTrue(game.gameOver)
        XCTAssertEqual(game.active?.reason, "Checkmate")
        XCTAssertEqual(game.moves.last, "Qh4#")
        let record = try XCTUnwrap(game.active)
        XCTAssertTrue(game.pgn(for: record).contains("1. f3 e5 2. g4 Qh4# 0-1"))
        let restored = GameViewModel(storageURL: url)
        try await waitUntil("restored") { restored.ready }
        XCTAssertEqual(restored.settings.boardTheme, "Forest")
        XCTAssertEqual(restored.settings.skill, 13)
        XCTAssertFalse(restored.settings.coordinates)
        XCTAssertEqual(restored.active, record)
        XCTAssertTrue(restored.gameOver)
        restored.review(record)
        try await settle(restored)
        restored.seek(2)
        try await settle(restored)
        XCTAssertEqual(restored.moves, ["f3","e5"])
        XCTAssertFalse(restored.inputAllowed)
        restored.practiceFromHere()
        try await settle(restored)
        XCTAssertTrue(restored.inputAllowed)
        XCTAssertEqual(restored.active?.id, record.id, "A continuation stays in the same game tree")
        XCTAssertEqual(restored.active?.branchCount, 2)
        XCTAssertEqual(restored.active?.moves.count, 2)
        XCTAssertEqual(restored.games.count, 1)
        restored.play(try XCTUnwrap(restored.snapshot?.legal.first))
        try await settle(restored)
        XCTAssertEqual(restored.active?.moves.count, 4, "Continuing a review also uses the bot")
        restored.deleteGame(record.id)
        XCTAssertEqual(restored.games.count, 0)
        let disk = try JSONDecoder().decode(LocalLibrary.self, from: Data(contentsOf: url))
        XCTAssertEqual(disk.games.count, 0)
    }

    func testNewGameDiscardsOldSearchAndResumeWorks() async throws {
        let (game, _) = try await makeGame()
        game.newGame()
        try await settle(game)
        let e4 = try XCTUnwrap(game.snapshot?.legal.first { $0.uci == "e2e4" })
        game.play(e4)
        try await waitUntil("searching") { game.isThinking }
        game.newGame()
        try await settle(game)
        XCTAssertEqual(game.active?.moves.count, 0)
        XCTAssertTrue(game.whiteToMove)
        game.play(try XCTUnwrap(game.snapshot?.legal.first { $0.uci == "d2d4" }))
        try await waitUntil("searching") { game.isThinking }
        game.pause()
        try await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertEqual(game.active?.moves.count, 1)
        game.resume()
        try await settle(game)
        XCTAssertEqual(game.active?.moves.count, 2)
        XCTAssertTrue(game.inputAllowed)
    }

    func testPromotionAllChoicesAndStalemate() async throws {
        let (game, _) = try await makeGame()
        var record = SavedGame(playerWhite: true, isPuzzle: true)
        record.baseFEN = "7k/P7/8/8/8/8/8/7K w - - 0 1"
        game.review(record)
        try await settle(game)
        game.practiceFromHere()
        try await settle(game)
        game.handleTap(squareIndex("a7"))
        game.handleTap(squareIndex("a8"))
        XCTAssertEqual(Set(game.promotions.compactMap(\.promotion)), Set(["q","r","b","n"]))
        game.play(try XCTUnwrap(game.promotions.first { $0.promotion == "n" }))
        try await settle(game)
        XCTAssertEqual(game.board[squareIndex("a8")]?.name, "knight")
        XCTAssertEqual(game.active?.reason, "Insufficient material")
        record.baseFEN = "7k/5K2/6Q1/8/8/8/8/8 b - - 0 1"
        game.review(record)
        try await settle(game)
        XCTAssertFalse(game.canContinue, "A naturally finished position cannot be continued")
        game.practiceFromHere()
        try await settle(game)
        XCTAssertEqual(game.snapshot?.reason, "Stalemate")
        XCTAssertTrue(game.reviewing)
        XCTAssertFalse(game.inputAllowed)
    }

    func testPromotionPopoverPreviewsDestinationAndRestoresOnCancel() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = try XCTUnwrap(scene.windows.first)
        let original = window.rootViewController
        defer { window.rootViewController = original }
        for isWhite in [true, false] {
            let (game, _) = try await makeGame()
            var record = SavedGame(playerWhite: isWhite, isPuzzle: true)
            record.baseFEN = isWhite ? "1r5k/P7/8/8/8/8/8/7K w - - 0 1" :
                "7k/8/8/8/8/8/p7/1R5K b - - 0 1"
            game.openPuzzle(record)
            try await settle(game)
            let screen = GameViewController(game: game)
            window.rootViewController = ChessNavigationController(rootViewController: screen)
            window.makeKeyAndVisible()
            window.layoutIfNeeded()
            screen.updateView()
            screen.view.layoutIfNeeded()
            let board = try XCTUnwrap(descendants(of: screen.view).first { $0 is ChessBoardView } as? ChessBoardView)
            let fromIndex = squareIndex(isWhite ? "a7" : "a2")
            let toIndex = squareIndex(isWhite ? "b8" : "b1")
            let from = try XCTUnwrap(board.promotionAnchor(at: fromIndex) as? UIControl)
            let to = try XCTUnwrap(board.promotionAnchor(at: toIndex) as? UIControl)
            let pawn = try XCTUnwrap(game.board[fromIndex])
            func beginPromotion() async throws -> PromotionPickerViewController {
                from.sendActions(for: .touchUpInside)
                to.sendActions(for: .touchUpInside)
                screen.updateView()
                try await waitUntil("promotion popover") { screen.presentedViewController is PromotionPickerViewController }
                try await Task.sleep(nanoseconds: 350_000_000)
                return try XCTUnwrap(screen.presentedViewController as? PromotionPickerViewController)
            }
            let picker = try await beginPromotion()
            let popover = try XCTUnwrap(picker.popoverPresentationController)
            XCTAssertTrue(popover.sourceView === to, "The arrow points at the destination in both perspectives")
            XCTAssertEqual(popover.sourceRect, to.bounds)
            XCTAssertEqual(screen.adaptivePresentationStyle(for: popover), .none)
            XCTAssertTrue(to.accessibilityLabel?.contains("pawn") == true)
            XCTAssertTrue(from.accessibilityLabel?.contains("Empty") == true)
            XCTAssertFalse(to.isUserInteractionEnabled)
            let glyph = try XCTUnwrap(descendants(of: board).compactMap { $0 as? ChessPieceView }
                .first { $0.piece?.id == pawn.id })
            XCTAssertEqual(glyph.frame.midX, to.frame.midX, accuracy: 0.1)
            XCTAssertEqual(glyph.frame.midY, to.frame.midY, accuracy: 0.1)
            XCTAssertEqual(game.board[fromIndex], pawn, "Preview does not alter engine state")
            XCTAssertEqual(game.board[toIndex]?.name, "rook")
            XCTAssertTrue(game.active?.moves.isEmpty == true)
            let choices = descendants(of: picker.view).compactMap { $0 as? UIButton }
                .filter { $0.accessibilityIdentifier?.hasPrefix("promote-") == true }
            XCTAssertEqual(choices.count, 4)
            for button in choices {
                let artwork = try XCTUnwrap(button.subviews.first { $0 is ChessPieceArtworkView } as? ChessPieceArtworkView)
                XCTAssertEqual(artwork.isWhite, isWhite)
                XCTAssertNil(button.title(for: .normal), "Choices display piece artwork")
                let frame = button.convert(button.bounds, to: picker.view)
                let safe = picker.view.safeAreaLayoutGuide.layoutFrame
                XCTAssertGreaterThanOrEqual(frame.minY, safe.minY, "The icon must clear the popover arrow")
                XCTAssertLessThanOrEqual(frame.maxY, safe.maxY)
                XCTAssertEqual(frame.midY, safe.midY, accuracy: 0.1, "Icons are centered in the popover body")
            }
            writeReviewImage(UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }, named: isWhite ? "WhitePromotionPopover" : "BlackPromotionPopover")
            XCTAssertNil(descendants(of: picker.view).first { $0.accessibilityIdentifier == "cancel-promotion" },
                         "Outside dismissal is the only cancellation control")
            // Programmatic dismissals don't invoke UIKit's outside-tap callback.
            // Exercise that delegate callback explicitly, then finish dismissal.
            screen.popoverPresentationControllerDidDismissPopover(popover)
            picker.dismiss(animated: false)
            try await waitUntil("promotion cancelled") { screen.presentedViewController == nil }
            screen.updateView()
            XCTAssertTrue(game.promotions.isEmpty)
            XCTAssertEqual(glyph.frame.midX, from.frame.midX, accuracy: 0.1)
            XCTAssertEqual(glyph.frame.midY, from.frame.midY, accuracy: 0.1)
            XCTAssertTrue(to.accessibilityLabel?.contains("rook") == true)
            XCTAssertTrue(game.active?.moves.isEmpty == true)
            game.flipped.toggle()
            screen.updateView()
            board.layoutIfNeeded()
            let secondPicker = try await beginPromotion()
            let secondPopover = try XCTUnwrap(secondPicker.popoverPresentationController)
            XCTAssertEqual(secondPopover.arrowDirection, .down, "Flipping exercises the bottom arrow")
            let safe = secondPicker.view.safeAreaLayoutGuide.layoutFrame
            for button in descendants(of: secondPicker.view).compactMap({ $0 as? UIButton }) {
                let frame = button.convert(button.bounds, to: secondPicker.view)
                XCTAssertGreaterThanOrEqual(frame.minY, safe.minY)
                XCTAssertLessThanOrEqual(frame.maxY, safe.maxY, "Choices must clear the bottom arrow")
                XCTAssertEqual(frame.midY, safe.midY, accuracy: 0.1)
            }
            writeReviewImage(UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }, named: isWhite ? "WhitePromotionBottomArrow" : "BlackPromotionBottomArrow")
            let knight = try XCTUnwrap(descendants(of: secondPicker.view).first {
                $0.accessibilityIdentifier == "promote-n"
            } as? UIButton)
            knight.sendActions(for: .touchUpInside)
            // Check before yielding to the engine: selecting a piece must not
            // undo the preview while its move is awaiting acceptance.
            screen.updateView()
            screen.view.layoutIfNeeded()
            XCTAssertTrue(game.busy)
            XCTAssertEqual(game.pendingPromotion?.promotion, "n")
            XCTAssertEqual(game.board[fromIndex], pawn)
            XCTAssertTrue(from.accessibilityLabel?.contains("Empty") == true)
            XCTAssertTrue(to.accessibilityLabel?.contains("pawn") == true)
            XCTAssertEqual(glyph.frame.midX, to.frame.midX, accuracy: 0.1)
            XCTAssertEqual(glyph.frame.midY, to.frame.midY, accuracy: 0.1)
            writeReviewImage(UIGraphicsImageRenderer(bounds: window.bounds).image { context in
                window.layer.render(in: context.cgContext)
            }, named: isWhite ? "WhitePromotionPending" : "BlackPromotionPending")
            try await settle(game)
            try await waitUntil("promotion selection dismissed") { screen.presentedViewController == nil }
            XCTAssertEqual(game.board[toIndex]?.name, "knight")
            XCTAssertNil(game.pendingPromotion)
            XCTAssertEqual(game.active?.moves.count, 1)
            XCTAssertEqual(game.active?.reason, "Insufficient material")
        }
    }

    func testPromotionPickerLayoutClearsEitherArrow() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = try XCTUnwrap(scene.windows.first)
        let original = window.rootViewController
        defer { window.rootViewController = original }
        let (game, _) = try await makeGame()
        var record = SavedGame(playerWhite: true, isPuzzle: true)
        record.baseFEN = "1r5k/P7/8/8/8/8/8/7K w - - 0 1"
        game.openPuzzle(record)
        try await settle(game)
        let moves = try XCTUnwrap(game.snapshot).legal.filter { $0.promotion != nil }
        for isWhite in [true, false] {
            for direction in [UIPopoverArrowDirection.up, .down] {
                let host = UIViewController()
                window.rootViewController = host
                window.makeKeyAndVisible()
                let anchor = UIView(frame: CGRect(x: window.bounds.midX - 24,
                                                  y: window.bounds.midY - 24, width: 48, height: 48))
                host.view.addSubview(anchor)
                let picker = PromotionPickerViewController(moves: moves, isWhite: isWhite)
                picker.modalPresentationStyle = .popover
                let popover = try XCTUnwrap(picker.popoverPresentationController)
                popover.sourceView = anchor
                popover.sourceRect = anchor.bounds
                popover.permittedArrowDirections = direction
                let delegate = GameViewController(game: game)
                popover.delegate = delegate
                host.present(picker, animated: false)
                try await Task.sleep(nanoseconds: 150_000_000)
                picker.view.layoutIfNeeded()
                XCTAssertEqual(popover.arrowDirection, direction)
                let safe = picker.view.safeAreaLayoutGuide.layoutFrame
                let buttons = descendants(of: picker.view).compactMap { $0 as? UIButton }
                XCTAssertEqual(buttons.count, 4)
                for button in buttons {
                    let frame = button.convert(button.bounds, to: picker.view)
                    XCTAssertGreaterThanOrEqual(frame.minY, safe.minY)
                    XCTAssertLessThanOrEqual(frame.maxY, safe.maxY)
                    XCTAssertEqual(frame.midY, safe.midY, accuracy: 0.1)
                    XCTAssertGreaterThanOrEqual(frame.height, 44, "Choice targets remain tappable")
                }
                picker.dismiss(animated: false)
            }
        }
    }

    func testPendingPromotionIsInvalidatedByNewGame() async throws {
        let (game, _) = try await makeGame()
        var record = SavedGame(playerWhite: true, isPuzzle: true)
        record.baseFEN = "1r5k/P7/8/8/8/8/8/7K w - - 0 1"
        game.openPuzzle(record)
        try await settle(game)
        game.handleTap(squareIndex("a7"))
        game.handleTap(squareIndex("b8"))
        game.play(try XCTUnwrap(game.promotions.first { $0.promotion == "n" }))
        XCTAssertNotNil(game.pendingPromotion)
        game.newGame()
        XCTAssertNil(game.pendingPromotion)
        try await settle(game)
        XCTAssertEqual(game.active?.baseFEN, GameViewModel.startFEN)
        XCTAssertTrue(game.active?.moves.isEmpty == true)
        XCTAssertEqual(game.board[squareIndex("a7")]?.name, "pawn")
        XCTAssertFalse(game.board[squareIndex("a7")]?.isWhite ?? true)
    }

    func testPhoneWindowAndRenderScreens() async throws {
        let (game, _) = try await makeGame()
        game.settings.moveRatingsEnabled = true
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = try XCTUnwrap(scene.windows.first)
        XCTAssertGreaterThan(window.bounds.height / window.bounds.width, 1.8, "iPhone must not use the old 3:2 compatibility viewport")
        game.newGame()
        try await settle(game)
        try await play("e2e4", in: game)
        game.requestHint()
        try await settle(game)
        XCTAssertNotNil(game.hint)
        let original = window.rootViewController
        defer { window.rootViewController = original }
        for (name, controller) in [
            ("Home", HomeViewController(game: game)),
            ("Game", GameViewController(game: game)),
            ("Settings", SettingsViewController(game: game)),
            ("History", HistoryViewController(game: game) { _ in }),
            ("Puzzle", PuzzleViewController(game: game)),
            ("PuzzleEditor", PuzzleEditorViewController(game: game) { _ in })
        ] {
            window.rootViewController = ChessNavigationController(rootViewController: controller)
            window.makeKeyAndVisible()
            window.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 500_000_000)
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            writeReviewImage(image, named: name)
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertNotNil(Bundle.main.url(forResource: "LICENSE-Arasan", withExtension: "txt"))
    }

    func testPieceArtworkRendersEveryPiece() throws {
        let kinds = Array("kqrbnp")
        let side: CGFloat = 96
        let sheetSize = CGSize(width: side * CGFloat(kinds.count), height: side * 2)
        let sheet = UIGraphicsImageRenderer(size: sheetSize).image { context in
            QuietChessTheme.background.setFill()
            context.fill(CGRect(origin: .zero, size: sheetSize))
            for (row, isWhite) in [true, false].enumerated() {
                for (column, kind) in kinds.enumerated() {
                    let frame = CGRect(x: CGFloat(column) * side, y: CGFloat(row) * side, width: side, height: side)
                    let artwork = ChessPieceArtworkView(frame: frame)
                    artwork.kind = kind
                    artwork.isWhite = isWhite
                    context.cgContext.saveGState()
                    context.cgContext.translateBy(x: frame.minX, y: frame.minY)
                    artwork.draw(CGRect(origin: .zero, size: frame.size))
                    context.cgContext.restoreGState()
                }
            }
        }
        writeReviewImage(sheet, named: "Pieces")
        let sheetAttachment = XCTAttachment(image: sheet)
        sheetAttachment.name = "Pieces"
        sheetAttachment.lifetime = .keepAlways
        add(sheetAttachment)
        for isWhite in [true, false] {
            for kind in kinds {
                let frame = CGRect(x: 0, y: 0, width: side, height: side)
                let artwork = ChessPieceArtworkView(frame: frame)
                artwork.kind = kind
                artwork.isWhite = isWhite
                let rendered = UIGraphicsImageRenderer(size: frame.size).image { context in
                    QuietChessTheme.background.setFill()
                    context.fill(frame)
                    artwork.draw(frame)
                }
                XCTAssertGreaterThan(inkPixels(in: rendered), 400,
                                     "\(isWhite ? "white" : "black") \(kind) should render visible geometry")
            }
        }
    }

    private func inkPixels(in image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return stride(from: 0, to: pixels.count, by: 4).reduce(into: 0) { count, index in
            if pixels[index] < 200 || pixels[index + 1] < 200 || pixels[index + 2] < 200 { count += 1 }
        }
    }

    private func writeReviewImage(_ image: UIImage, named name: String) {
        guard let data = image.pngData() else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).png")
        try? data.write(to: url)
        print("REVIEW IMAGE \(url.path)")
    }

    func testUIKitHomeSelectionAndBoardInput() async throws {
        let (game, _) = try await makeGame()
        let home = HomeViewController(game: game)
        home.loadViewIfNeeded()
        let black = try XCTUnwrap(descendants(of: home.view).first { $0.accessibilityLabel == "Play Black" } as? UIControl)
        black.sendActions(for: .touchUpInside)
        XCTAssertFalse(game.settings.playWhite)
        let white = try XCTUnwrap(descendants(of: home.view).first { $0.accessibilityLabel == "Play White" } as? UIControl)
        white.sendActions(for: .touchUpInside)
        XCTAssertTrue(game.settings.playWhite)

        game.newGame()
        try await settle(game)
        let board = ChessBoardView(game: game)
        board.frame = CGRect(x: 0, y: 0, width: 360, height: 360)
        board.update(animated: false)
        board.layoutIfNeeded()
        let e2 = try XCTUnwrap(descendants(of: board).first { $0.accessibilityIdentifier == "square-e2" } as? UIButton)
        let e4 = try XCTUnwrap(descendants(of: board).first { $0.accessibilityIdentifier == "square-e4" } as? UIButton)
        XCTAssertTrue(e2.isUserInteractionEnabled)
        e2.sendActions(for: .touchUpInside)
        board.update(animated: false)
        XCTAssertEqual(e4.accessibilityValue, "Legal destination")
        writeReviewImage(UIGraphicsImageRenderer(bounds: board.bounds).image { _ in
            board.drawHierarchy(in: board.bounds, afterScreenUpdates: true)
        }, named: "BoardSelection")
        e4.sendActions(for: .touchUpInside)
        try await settle(game)
        XCTAssertEqual(game.active?.moves.first, "e2e4")
        XCTAssertEqual(game.active?.moves.count, 2, "The bot replies to the board tap")
        game.flipped = true
        board.update(animated: false)
        board.layoutIfNeeded()
        XCTAssertGreaterThan(e4.frame.midY, e2.frame.midY)
        game.review(try XCTUnwrap(game.active))
        try await settle(game)
        board.update(animated: false)
        XCTAssertFalse(e2.isUserInteractionEnabled)
    }

    func testBlackPerspectiveCoordinatesAndPuzzleSetup() async throws {
        let (game, _) = try await makeGame()
        let fen = "4k3/8/8/8/8/8/8/K3R3 b - - 0 1"
        let puzzle = try await game.addPuzzle(fen: fen, playerWhite: false)
        try await settle(game)
        XCTAssertFalse(game.whiteAtBottom)
        XCTAssertFalse(game.whiteToMove)
        let board = ChessBoardView(game: game)
        board.frame = CGRect(x: 0, y: 0, width: 400, height: 400)
        board.update(animated: false)
        board.layoutIfNeeded()
        func square(_ name: String) throws -> UIControl {
            try XCTUnwrap(descendants(of: board).first { $0.accessibilityIdentifier == "square-\(name)" } as? UIControl)
        }
        let a1 = try square("a1")
        let h1 = try square("h1")
        let a8 = try square("a8")
        XCTAssertGreaterThan(a1.frame.midX, h1.frame.midX)
        XCTAssertLessThan(a1.frame.midY, a8.frame.midY)
        let ranks = descendants(of: board).compactMap { $0 as? UILabel }
            .filter { $0.accessibilityIdentifier?.hasPrefix("rank-") == true }
        let files = descendants(of: board).compactMap { $0 as? UILabel }
            .filter { $0.accessibilityIdentifier?.hasPrefix("file-") == true }
        XCTAssertEqual(ranks.map(\.text), (1...8).map { String($0) })
        XCTAssertEqual(files.map(\.text), Array("hgfedcba").map { String($0) })
        XCTAssertTrue(ranks.allSatisfy { $0.frame.minX >= a1.frame.minX }, "Ranks belong inside the rightmost column")
        XCTAssertTrue(files.allSatisfy { $0.frame.maxY <= h1.frame.maxY }, "Files belong inside the top row")
        let king = try XCTUnwrap(descendants(of: board).compactMap { $0 as? ChessPieceView }
            .first { $0.piece?.kind == "k" })
        XCTAssertLessThan(king.frame.width, try square("e8").frame.width, "Art is inset without shrinking square hit areas")
        writeReviewImage(UIGraphicsImageRenderer(bounds: board.bounds).image { _ in
            board.drawHierarchy(in: board.bounds, afterScreenUpdates: true)
        }, named: "BlackBoard")
        try square("e8").sendActions(for: .touchUpInside)
        try square("d8").sendActions(for: .touchUpInside)
        try await settle(game)
        XCTAssertEqual(game.active?.moves.first, "e8d8", "Rotated squares keep their logical move identities")
        XCTAssertEqual(game.active?.moves.count, 2, "White is played by the bot")
        XCTAssertFalse(game.whiteToMove)
        XCTAssertFalse(game.whiteAtBottom, "Perspective must stay fixed when the turn changes")
        game.flipped = true
        board.update(animated: false)
        board.layoutIfNeeded()
        XCTAssertTrue(game.whiteAtBottom)
        XCTAssertTrue(ranks.allSatisfy { $0.frame.maxX <= a1.frame.maxX })
        XCTAssertTrue(files.allSatisfy { $0.frame.minY >= a1.frame.minY })
        XCTAssertEqual(files.map(\.text), Array("abcdefgh").map { String($0) })
        writeReviewImage(UIGraphicsImageRenderer(bounds: board.bounds).image { _ in
            board.drawHierarchy(in: board.bounds, afterScreenUpdates: true)
        }, named: "WhiteBoard")
        game.settings.coordinates = false
        board.update(animated: false)
        board.layoutIfNeeded()
        XCTAssertTrue((ranks + files).allSatisfy(\.isHidden))

        let setup = SetupBoardView()
        setup.frame = board.frame
        setup.layoutIfNeeded()
        XCTAssertTrue(setup.place(.piece("K"), at: 0))
        XCTAssertTrue(setup.place(.piece("R"), at: 4))
        setup.whiteToMove = false
        XCTAssertTrue(setup.place(.piece("k"), at: 60))
        setup.layoutIfNeeded()
        let setupSquares = descendants(of: setup).compactMap { $0 as? SetupSquare }
        XCTAssertGreaterThan(setupSquares[0].frame.midX, setupSquares[7].frame.midX)
        XCTAssertLessThan(setupSquares[0].frame.midY, setupSquares[56].frame.midY)
        XCTAssertTrue(setupSquares[0].hints.contains { $0.text == "1" && $0.corner == .topTrailing })
        XCTAssertTrue(setupSquares[0].hints.contains { $0.text == "a" && $0.corner == .topLeading })
        var tapped: Int?
        setup.onSelect = { index, _ in tapped = index }
        setupSquares[60].sendActions(for: .touchUpInside)
        XCTAssertEqual(tapped, 60)
        XCTAssertEqual(ChessPosition.fen(from: setup.placement, whiteToMove: false), fen)
        writeReviewImage(UIGraphicsImageRenderer(bounds: setup.bounds).image { _ in
            setup.drawHierarchy(in: setup.bounds, afterScreenUpdates: true)
        }, named: "BlackSetup")

        let colors = ChessBoardPalette.colors(for: "Slate")
        let whitePreview = PuzzleThumbnail.image(fen: puzzle.baseFEN, side: 240, colors: colors, whiteAtBottom: true)
        let blackPreview = PuzzleThumbnail.image(fen: puzzle.baseFEN, side: 240, colors: colors, whiteAtBottom: false)
        XCTAssertNotEqual(whitePreview.pngData(), blackPreview.pngData(), "Thumbnail caching includes perspective")
        writeReviewImage(blackPreview, named: "BlackPuzzlePreview")
    }

    func testUIKitSettingsControlsAndHistoryListing() async throws {
        let (game, _) = try await makeGame()
        let settings = SettingsViewController(game: game)
        settings.loadViewIfNeeded()
        let table = try XCTUnwrap(descendants(of: settings.view).first { $0 is UITableView } as? UITableView)
        let ratingCell = settings.tableView(table, cellForRowAt: IndexPath(row: 0, section: 3))
        let ratingSwitch = try XCTUnwrap(ratingCell.accessoryView as? UISwitch)
        ratingSwitch.isOn = true
        ratingSwitch.sendActions(for: .valueChanged)
        XCTAssertTrue(game.settings.moveRatingsEnabled)
        let coordinatesCell = settings.tableView(table, cellForRowAt: IndexPath(row: 2, section: 4))
        let coordinatesSwitch = try XCTUnwrap(coordinatesCell.accessoryView as? UISwitch)
        coordinatesSwitch.isOn = false
        coordinatesSwitch.sendActions(for: .valueChanged)
        XCTAssertFalse(game.settings.coordinates)
        game.newGame()
        try await settle(game)
        _ = try await game.addPuzzle(fen: "4k3/8/8/8/8/8/8/R3K3 w - - 0 1", playerWhite: true)
        try await settle(game)
        var opened: SavedGame?
        let library = HistoryViewController(game: game) { opened = $0 }
        library.loadViewIfNeeded()
        let libraryTable = try XCTUnwrap(descendants(of: library.view).first { $0 is UITableView } as? UITableView)
        // History keeps every saved game, newest first, puzzles included.
        let listing = game.games.sorted { $0.date > $1.date }
        XCTAssertEqual(library.tableView(libraryTable, numberOfRowsInSection: 0), 2)
        let row = try XCTUnwrap(listing.firstIndex { $0.isPuzzle })
        library.tableView(libraryTable, didSelectRowAt: IndexPath(row: row, section: 0))
        XCTAssertTrue(opened?.isPuzzle == true)
    }

    private func descendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    func testPuzzleSetupValidationAndPlay() async throws {
        let (game, _) = try await makeGame()

        // The setup board reports exactly what a hand-built position looks like.
        let board = SetupBoardView()
        board.frame = CGRect(x: 0, y: 0, width: 320, height: 320)
        board.layoutIfNeeded()
        let squares = descendants(of: board).compactMap { $0 as? UIControl }
        XCTAssertEqual(squares.count, 64, "Every square must be tappable")
        XCTAssertEqual(ChessPosition.count(board.placement), 0, "The board starts empty")
        XCTAssertNotNil(ChessPosition.issue(in: board.placement, whiteToMove: true), "An empty board is not playable")

        var selected: Int?
        board.onSelect = { index, _ in selected = index }
        squares[0].sendActions(for: .touchUpInside)
        XCTAssertEqual(selected, 0)
        XCTAssertEqual(ChessPosition.count(board.placement), 0, "Tapping a square opens a picker without placing a piece")
        XCTAssertTrue(board.place(.piece("R"), at: 0))
        XCTAssertTrue(board.place(.piece("K"), at: 4))
        XCTAssertTrue(board.place(.piece("k"), at: 60))
        XCTAssertNil(ChessPosition.issue(in: board.placement, whiteToMove: true))
        XCTAssertEqual(ChessPosition.fen(from: board.placement, whiteToMove: true), "4k3/8/8/8/8/8/8/R3K3 w - - 0 1")

        XCTAssertTrue(board.place(.eraser, at: 0))
        XCTAssertEqual(squares[0].accessibilityLabel, "a1, Empty square")
        XCTAssertTrue(board.place(.piece("R"), at: 0))

        let fen = ChessPosition.fen(from: board.placement, whiteToMove: true)
        let puzzle = try await game.addPuzzle(fen: fen, playerWhite: true)
        try await settle(game)
        XCTAssertTrue(puzzle.isPuzzle)
        XCTAssertEqual(puzzle.baseFEN, fen)
        XCTAssertTrue(puzzle.playerWhite)
        XCTAssertEqual(game.record?.id, puzzle.id, "Saving a puzzle opens it")
        XCTAssertTrue(game.whiteToMove)
        XCTAssertTrue(game.inputAllowed, "A puzzle is played, not replayed")

        // Every saved puzzle shows up as a tile, with the add tile in front.
        let library = PuzzleViewController(game: game)
        library.loadViewIfNeeded()
        library.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        library.view.layoutIfNeeded()
        let grid = try XCTUnwrap(descendants(of: library.view).first { $0 is UICollectionView } as? UICollectionView)
        XCTAssertEqual(library.collectionView(grid, numberOfItemsInSection: 0), 2)
        let tile = try XCTUnwrap(library.collectionView(grid, cellForItemAt: IndexPath(item: 1, section: 0)) as? PuzzleTile)
        XCTAssertTrue(tile.accessibilityLabel?.hasPrefix("You play White") == true, "Tiles name the side you play")

        // Reopening a saved puzzle resumes it instead of starting a fresh board.
        game.newGame()
        try await settle(game)
        game.openPuzzle(puzzle)
        try await settle(game)
        XCTAssertEqual(game.record?.id, puzzle.id)
        XCTAssertTrue(game.whiteToMove)
    }

    func testPuzzleTileOpensEditorAndSquarePopover() async throws {
        let (game, _) = try await makeGame()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = try XCTUnwrap(scene.windows.first)
        let original = window.rootViewController
        defer { window.rootViewController = original }
        let library = PuzzleViewController(game: game)
        let navigation = ChessNavigationController(rootViewController: library)
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 300_000_000)
        let grid = try XCTUnwrap(descendants(of: library.view).first { $0 is UICollectionView } as? UICollectionView)
        XCTAssertTrue(grid.delegate === library, "Tile taps must be routed through the collection delegate")
        grid.delegate?.collectionView?(grid, didSelectItemAt: IndexPath(item: 0, section: 0))
        try await waitUntil("editor opened") { navigation.topViewController is PuzzleEditorViewController }
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertNil(library.presentedViewController, "Adding a puzzle uses a navigation page")
        let editor = try XCTUnwrap(navigation.topViewController as? PuzzleEditorViewController)
        XCTAssertTrue(navigation.viewControllers.first === library)
        let board = try XCTUnwrap(descendants(of: editor.view).first { $0 is SetupBoardView } as? SetupBoardView)
        let squares = descendants(of: board).compactMap { $0 as? SetupSquare }
        let side = try XCTUnwrap(descendants(of: editor.view).first { $0 is UISegmentedControl } as? UISegmentedControl)
        side.selectedSegmentIndex = 0
        side.sendActions(for: .valueChanged)

        func openPicker(at index: Int) async throws -> PuzzlePiecePickerViewController {
            squares[index].sendActions(for: .touchUpInside)
            try await waitUntil("piece picker presented") { editor.presentedViewController?.viewIfLoaded?.window != nil }
            try await Task.sleep(nanoseconds: 300_000_000)
            return try XCTUnwrap(editor.presentedViewController as? PuzzlePiecePickerViewController)
        }
        func option(_ label: String, in picker: PuzzlePiecePickerViewController) throws -> UIControl {
            try XCTUnwrap(descendants(of: picker.palette).compactMap { $0 as? UIControl }.first { $0.accessibilityLabel == label })
        }
        func choose(_ label: String, in picker: PuzzlePiecePickerViewController) async throws {
            let cell = try option(label, in: picker)
            XCTAssertTrue(cell.isEnabled)
            cell.sendActions(for: .touchUpInside)
            try await waitUntil("piece picker dismissed") { editor.presentedViewController == nil }
        }

        let picker = try await openPicker(at: 60)
        XCTAssertEqual(editor.presentedViewController?.presentationController?.presentationStyle, .popover,
                       "The picker remains an anchored bubble on iPhone")
        XCTAssertFalse(try option("White pawn", in: picker).isEnabled)
        XCTAssertFalse(try option("Black pawn", in: picker).isEnabled)
        XCTAssertTrue(try option("Eraser", in: picker).isEnabled)
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        writeReviewImage(image, named: "PuzzlePiecePopover")
        try await choose("Black king", in: picker)
        XCTAssertEqual(board.placement[60], "k")

        let adjacent = try await openPicker(at: 52)
        XCTAssertFalse(try option("White king", in: adjacent).isEnabled, "Kings cannot be adjacent")
        XCTAssertFalse(try option("Black king", in: adjacent).isEnabled, "A second black king is disabled")
        try await choose("Eraser", in: adjacent)
        let whiteKing = try await openPicker(at: 0)
        try await choose("White king", in: whiteKing)
        XCTAssertTrue(editor.navigationItem.rightBarButtonItem?.isEnabled == true)

        let checkingPiece = try await openPicker(at: 4)
        XCTAssertFalse(try option("White rook", in: checkingPiece).isEnabled,
                       "Black cannot already be in check while White is to move")
        // Disabled actions must never mutate the board, even if fired programmatically.
        try option("White rook", in: checkingPiece).sendActions(for: .touchUpInside)
        XCTAssertEqual(board.placement[4], ChessPosition.empty)
        try await choose("Eraser", in: checkingPiece)

        side.selectedSegmentIndex = 1
        side.sendActions(for: .valueChanged)
        let blackToMove = try await openPicker(at: 4)
        XCTAssertTrue(try option("White rook", in: blackToMove).isEnabled, "The side to move may start in check")
        try await choose("White rook", in: blackToMove)
        let replacement = try await openPicker(at: 60)
        XCTAssertTrue(try option("Black king", in: replacement).isEnabled, "The existing king can stay on its square")
        try await choose("Eraser", in: replacement)
        XCTAssertEqual(board.placement[60], ChessPosition.empty)
        XCTAssertFalse(editor.navigationItem.rightBarButtonItem?.isEnabled == true)

        let restoredKing = try await openPicker(at: 60)
        try await choose("Black king", in: restoredKing)
        let save = try XCTUnwrap(editor.navigationItem.rightBarButtonItem)
        let saveAction = try XCTUnwrap(save.action)
        XCTAssertTrue(UIApplication.shared.sendAction(saveAction, to: save.target, from: save, for: nil))
        try await waitUntil("saved puzzle opens game") { navigation.topViewController is GameViewController }
        try await settle(game)
        XCTAssertTrue(game.inputAllowed)
        XCTAssertEqual(game.active?.baseFEN, "4k3/8/8/8/8/8/8/K3R3 b - - 0 1")
        XCTAssertEqual(navigation.viewControllers.count, 2, "Saving replaces the editor with the playable board")
        XCTAssertTrue(navigation.viewControllers.first === library)
        navigation.popViewController(animated: false)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(navigation.topViewController === library)
        XCTAssertEqual(library.collectionView(grid, numberOfItemsInSection: 0), 2)
    }

    func testPuzzleEntriesOpenPlayableBoard() async throws {
        let (game, _) = try await makeGame()
        let puzzle = try await game.addPuzzle(fen: "KQ6/8/8/8/8/8/8/6Bk b - - 0 1", playerWhite: false)
        try await settle(game)
        game.review(puzzle)
        try await settle(game)
        XCTAssertTrue(game.reviewing)

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = try XCTUnwrap(scene.windows.first)
        let original = window.rootViewController
        defer { window.rootViewController = original }
        let home = HomeViewController(game: game)
        let navigation = ChessNavigationController(rootViewController: home)
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 300_000_000)
        let puzzleButton = try XCTUnwrap(descendants(of: home.view).compactMap { $0 as? UIButton }
            .first { $0.accessibilityLabel == "Puzzle" })
        puzzleButton.sendActions(for: .touchUpInside)
        try await waitUntil("puzzle library opened") { navigation.topViewController is PuzzleViewController }
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertNil(home.presentedViewController, "The puzzle library is a full navigation page")
        XCTAssertFalse(navigation.isNavigationBarHidden)
        let library = try XCTUnwrap(navigation.topViewController as? PuzzleViewController)
        XCTAssertEqual(navigation.viewControllers.count, 2)
        try await waitUntil("puzzle page transition completed") { navigation.transitionCoordinator == nil }
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        writeReviewImage(image, named: "PuzzlePage")
        let grid = try XCTUnwrap(descendants(of: library.view).first { $0 is UICollectionView } as? UICollectionView)
        grid.delegate?.collectionView?(grid, didSelectItemAt: IndexPath(item: 1, section: 0))
        try await waitUntil("puzzle tile opens game") { navigation.topViewController is GameViewController }
        try await settle(game)
        XCTAssertEqual(game.record?.id, puzzle.id)
        XCTAssertFalse(game.reviewing)
        XCTAssertTrue(game.inputAllowed)
        XCTAssertFalse(game.whiteAtBottom)
        let screen = try XCTUnwrap(navigation.topViewController as? GameViewController)
        let from = try XCTUnwrap(descendants(of: screen.view).first { $0.accessibilityIdentifier == "square-h1" } as? UIControl)
        let to = try XCTUnwrap(descendants(of: screen.view).first { $0.accessibilityIdentifier == "square-g1" } as? UIControl)
        from.sendActions(for: .touchUpInside)
        to.sendActions(for: .touchUpInside)
        try await settle(game)
        XCTAssertEqual(game.active?.moves.first, "h1g1", "A puzzle opened from a tile must accept moves")
        XCTAssertEqual(game.active?.moves.count, 2, "The bot replies in puzzles")
        let resumedMoves = game.active?.moves

        navigation.popViewController(animated: false)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(navigation.topViewController === library, "Returning from play opens the puzzle library")
        grid.delegate?.collectionView?(grid, didSelectItemAt: IndexPath(item: 0, section: 0))
        try await waitUntil("editor opened from library") { navigation.topViewController is PuzzleEditorViewController }
        try await Task.sleep(nanoseconds: 300_000_000)
        navigation.popViewController(animated: false)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(navigation.topViewController === library)
        XCTAssertEqual(game.games.count, 1, "Leaving an unsaved editor creates no puzzle")

        navigation.popToRootViewController(animated: false)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(navigation.isNavigationBarHidden, "Returning home restores its header")
        XCTAssertFalse(descendants(of: home.view).contains { $0 is UITableView },
                       "Saved games live on the history page, not in an inline home list")
        let historyButton = try XCTUnwrap(descendants(of: home.view).first {
            $0.accessibilityIdentifier == "open-game-history"
        } as? UIButton)
        XCTAssertEqual(historyButton.accessibilityValue, "1 game")
        historyButton.sendActions(for: .touchUpInside)
        try await waitUntil("history page opened") { navigation.topViewController is HistoryViewController }
        try await waitUntil("history transition completed") { navigation.transitionCoordinator == nil }
        let historyPage = try XCTUnwrap(navigation.topViewController as? HistoryViewController)
        XCTAssertNil(home.presentedViewController)
        XCTAssertNil(historyPage.navigationItem.rightBarButtonItem, "A navigation page uses Back, not Done")
        XCTAssertFalse(navigation.isNavigationBarHidden)
        writeReviewImage(UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }, named: "HistoryPage")
        let history = try XCTUnwrap(descendants(of: historyPage.view).first { $0 is UITableView } as? UITableView)
        XCTAssertEqual(historyPage.tableView(history, numberOfRowsInSection: 0), 1)
        historyPage.tableView(history, didSelectRowAt: IndexPath(row: 0, section: 0))
        try await waitUntil("history puzzle entry opens game") { navigation.topViewController is GameViewController }
        try await settle(game)
        XCTAssertFalse(game.reviewing, "A puzzle on the history page should open for play")
        XCTAssertTrue(game.inputAllowed)
        XCTAssertEqual(game.active?.moves, resumedMoves, "An unfinished puzzle resumes its moves")
        navigation.popViewController(animated: false)
        XCTAssertTrue(navigation.topViewController === historyPage, "Returning from play restores history")
        navigation.popViewController(animated: false)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(navigation.topViewController === home)
        XCTAssertTrue(navigation.isNavigationBarHidden)
    }

    func testPuzzleSetupRejectsIllegalPositions() async throws {
        let (game, _) = try await makeGame()

        var twoKings = [Character](repeating: ChessPosition.empty, count: 64)
        twoKings[0] = "K"
        twoKings[63] = "k"
        XCTAssertNil(ChessPosition.issue(in: twoKings, whiteToMove: true))

        var pawnOnLastRank = twoKings
        pawnOnLastRank[5] = "P"
        XCTAssertNotNil(ChessPosition.issue(in: pawnOnLastRank, whiteToMove: true))

        XCTAssertNotNil(ChessPosition.issue(in: [Character](repeating: ChessPosition.empty, count: 64), whiteToMove: true),
                        "A position without kings cannot be saved")
        XCTAssertFalse(ChessPosition.canPlace("K", at: 62, in: twoKings, whiteToMove: true))
        XCTAssertTrue(ChessPosition.canPlace("K", at: 0, in: twoKings, whiteToMove: true),
                      "Replacing the target square must not count its king twice")
        XCTAssertFalse(ChessPosition.canPlace("p", at: 7, in: twoKings, whiteToMove: true))
        var eightPawns = twoKings
        for index in 8..<16 { eightPawns[index] = "P" }
        XCTAssertFalse(ChessPosition.canPlace("P", at: 16, in: eightPawns, whiteToMove: true))
        XCTAssertTrue(ChessPosition.canPlace("P", at: 8, in: eightPawns, whiteToMove: true))
        var fullSide = eightPawns
        for index in 16..<23 { fullSide[index] = "N" }
        XCTAssertFalse(ChessPosition.canPlace("Q", at: 24, in: fullSide, whiteToMove: true))
        XCTAssertTrue(ChessPosition.canPlace("Q", at: 16, in: fullSide, whiteToMove: true))

        // White to move while Black is in check cannot happen, so the engine must reject it.
        var impossible = [Character](repeating: ChessPosition.empty, count: 64)
        impossible[0] = "K"     // a1
        impossible[4] = "R"     // e1
        impossible[60] = "k"    // e8: attacked by the rook while White is to move
        do {
            _ = try await game.addPuzzle(fen: ChessPosition.fen(from: impossible, whiteToMove: true), playerWhite: true)
            XCTFail("A position where the side that just moved is in check must be rejected")
        } catch {
            XCTAssertTrue(error is PuzzleError)
        }
        XCTAssertFalse(game.games.contains { $0.baseFEN.hasPrefix("4k3/8/8/8/8/8/8/K3R3") },
                       "A rejected puzzle must not reach the library")
    }

    func testOnlyBotControlsRemain() async throws {
        let (game, _) = try await makeGame()
        let settings = SettingsViewController(game: game)
        settings.loadViewIfNeeded()
        let table = try XCTUnwrap(descendants(of: settings.view).first { $0 is UITableView } as? UITableView)
        XCTAssertEqual(settings.tableView(table, numberOfRowsInSection: 0), 1)
        let side = settings.tableView(table, cellForRowAt: IndexPath(row: 0, section: 0))
        XCTAssertEqual(side.textLabel?.text, "Play as")
        _ = try await game.addPuzzle(fen: "4k3/8/8/8/8/8/8/R3K3 w - - 0 1", playerWhite: true)
        let screen = GameViewController(game: game)
        screen.loadViewIfNeeded()
        let menu = try XCTUnwrap(screen.navigationItem.rightBarButtonItems?.first?.menu)
        func titles(_ element: UIMenuElement) -> [String] {
            [element.title] + ((element as? UIMenu)?.children.flatMap(titles) ?? [])
        }
        XCTAssertFalse(titles(menu).contains("Mode"))
        XCTAssertFalse(titles(menu).contains("Practice both sides"))
        XCTAssertTrue(titles(menu).contains("Bot strength"))
        let buttons = descendants(of: screen.view).compactMap { $0 as? UIButton }
        XCTAssertTrue(buttons.contains { $0.configuration?.title == "Resign" })
        XCTAssertFalse(buttons.contains { $0.configuration?.title == "Finish" })
    }

    func testBlackStartingPuzzlesReplyAndUndoToPlayerDecision() async throws {
        let (game, _) = try await makeGame()
        let fen = "4k3/8/8/8/8/8/8/K3R3 b - - 0 1"
        _ = try await game.addPuzzle(fen: fen, playerWhite: false)
        XCTAssertTrue(game.inputAllowed)
        try await play("e8d8", in: game)
        XCTAssertEqual(game.active?.moves.count, 2)
        XCTAssertFalse(game.whiteToMove)
        game.undo()
        try await settle(game)
        XCTAssertEqual(game.active?.moves, [])
        XCTAssertFalse(game.whiteToMove)
        XCTAssertTrue(game.inputAllowed)

        // A White player must wait for the bot's Black opening, with a fixed Black perspective.
        let puzzle = try await game.addPuzzle(fen: fen, playerWhite: true)
        XCTAssertEqual(puzzle.moves.count, 1, "Saving must return the bot's updated record")
        XCTAssertTrue(game.whiteToMove)
        XCTAssertFalse(game.whiteAtBottom)
        XCTAssertFalse(game.canUndo, "The bot's opening alone has no player decision to undo")
        let opening = try XCTUnwrap(game.active?.moves)
        game.play(try XCTUnwrap(game.snapshot?.legal.first))
        try await settle(game)
        XCTAssertEqual(game.active?.moves.count, 3)
        game.undo()
        try await settle(game)
        XCTAssertEqual(game.active?.moves, opening)
        XCTAssertTrue(game.inputAllowed)
        XCTAssertFalse(game.canUndo)
        game.newGame()
        try await settle(game)
        game.openPuzzle(puzzle)
        try await settle(game)
        XCTAssertEqual(game.active?.moves, opening, "Reopening must preserve the bot's opening")
        XCTAssertTrue(game.inputAllowed)
    }

    func testLegacyManualSavesBecomeBotPuzzlesWithoutLosingHistory() async throws {
        let (_, url) = try await makeGame()
        var unfinished = SavedGame(playerWhite: true, isPuzzle: true)
        unfinished.moves = ["e2e4"]
        unfinished.notation = ["e4"]
        unfinished.ratings = [.good]
        unfinished.practiceSeconds = 321
        var finished = SavedGame(playerWhite: false, isPuzzle: true)
        finished.result = "1/2-1/2"
        finished.reason = "Practice complete"
        let normal = SavedGame(playerWhite: true)
        let library = LocalLibrary(games: [unfinished, finished, normal], activeID: unfinished.id)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(library)) as? [String: Any])
        var settings = try XCTUnwrap(json["settings"] as? [String: Any])
        settings["mode"] = "board"
        json["settings"] = settings
        var records = try XCTUnwrap(json["games"] as? [[String: Any]])
        for index in records.indices {
            records[index].removeValue(forKey: "isPuzzle")
            records[index].removeValue(forKey: "branches")
            records[index].removeValue(forKey: "selectedBranchID")
            records[index]["mode"] = index < 2 ? "board" : "engine"
        }
        json["games"] = records
        try JSONSerialization.data(withJSONObject: json).write(to: url)

        let restored = GameViewModel(storageURL: url)
        try await waitUntil("legacy library ready") { restored.ready }
        XCTAssertEqual(restored.games.count, 3)
        XCTAssertEqual(restored.active?.branchCount, 1, "Pre-tree saves load as one main line")
        XCTAssertEqual(restored.games.filter(\.isSavedPractice).count, 2)
        XCTAssertEqual(restored.active?.id, unfinished.id)
        XCTAssertEqual(restored.active?.practiceSeconds, 321)
        XCTAssertFalse(restored.inputAllowed, "The human cannot play the bot's side in an old manual save")
        restored.play(try XCTUnwrap(restored.snapshot?.legal.first))
        XCTAssertEqual(restored.active?.moves, ["e2e4"])
        restored.resume()
        try await settle(restored)
        XCTAssertEqual(restored.active?.moves.count, 2)
        XCTAssertEqual(restored.active?.moves.first, "e2e4")
        XCTAssertEqual(restored.active?.ratings?.first, .good)
        XCTAssertTrue(restored.inputAllowed)
        XCTAssertTrue(restored.pgn(for: try XCTUnwrap(restored.active)).contains("[Black \"Bot\"]"))
        XCTAssertEqual(restored.games.first { $0.id == finished.id }, finished)
        restored.openPuzzle(finished)
        try await settle(restored)
        XCTAssertTrue(restored.gameOver, "Finished legacy games retain their stored outcome")
        XCTAssertEqual(restored.active?.reason, "Practice complete")
        restored.newGame()
        try await settle(restored)
        XCTAssertFalse(restored.active?.isPuzzle == true, "An old default cannot create a manual game")

        let stored = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertNil((stored["settings"] as? [String: Any])?["mode"])
        XCTAssertTrue((stored["games"] as? [[String: Any]])?.allSatisfy { $0["mode"] == nil } == true)
    }

    func testBranchesPersistAndReviewingDuringSearchCannotChangeHistory() async throws {
        let (game, url) = try await makeGame()
        game.newGame()
        try await settle(game)
        let rootID = try XCTUnwrap(game.active?.id)
        game.play(try XCTUnwrap(game.snapshot?.legal.first { $0.uci == "e2e4" }))
        try await waitUntil("bot search before seeking") { game.isThinking }
        game.seek(0)
        XCTAssertTrue(game.busy, "Continuing must wait for the requested historical snapshot")
        XCTAssertFalse(game.canContinue)
        try await settle(game)
        XCTAssertTrue(game.reviewing)
        XCTAssertEqual(game.reviewGame?.moves, ["e2e4"], "An obsolete search cannot append to the saved route")
        XCTAssertEqual(game.moves, [])
        game.practiceFromHere()
        try await settle(game)
        let branchID = try XCTUnwrap(game.active?.branchID)
        XCTAssertNotEqual(branchID, rootID)
        XCTAssertEqual(game.games.count, 1)
        try await play("d2d4", in: game)
        let branchMoves = try XCTUnwrap(game.active?.moves)
        XCTAssertEqual(branchMoves.count, 2)
        XCTAssertEqual(game.active?.branches.first { $0.id == rootID }?.moves, ["e2e4"])
        XCTAssertEqual(game.active?.branches.last?.parentID, rootID)
        XCTAssertEqual(game.active?.branchPoints.map(\.ply), [0])
        game.pause()

        let restored = GameViewModel(storageURL: url)
        try await waitUntil("tree restored") { restored.ready }
        XCTAssertEqual(restored.active?.id, rootID)
        XCTAssertEqual(restored.active?.branchID, branchID)
        XCTAssertEqual(restored.active?.branchCount, 2)
        XCTAssertEqual(restored.active?.moves, branchMoves)
        restored.selectBranch(rootID, at: 1)
        try await settle(restored)
        XCTAssertEqual(restored.reviewGame?.moves, ["e2e4"])
        XCTAssertEqual(restored.board[squareIndex("e4")]?.kind, "P")
        XCTAssertTrue(restored.canContinue)
        restored.practiceFromHere()
        try await settle(restored)
        XCTAssertTrue(restored.active?.playerWhite == true, "Continuing on Black's turn keeps the chosen human side")
        XCTAssertEqual(restored.active?.moves.count, 2, "The bot resumes an unfinished tip")
        XCTAssertTrue(restored.inputAllowed)
        XCTAssertEqual(restored.active?.branchCount, 2, "Resuming an unfinished tip does not create a duplicate branch")
        let resumedMain = try XCTUnwrap(restored.active?.moves)
        XCTAssertEqual(restored.active?.branches.first { $0.id == rootID }?.moves, resumedMain)
        restored.selectBranch(branchID, at: 1)
        try await settle(restored)
        restored.practiceFromHere()
        try await settle(restored)
        XCTAssertEqual(restored.active?.branchCount, 3, "Continuing in the middle of the bot's turn creates a fork")
        XCTAssertEqual(restored.active?.moves.first, "d2d4")
        XCTAssertEqual(restored.active?.moves.count, 2)
        XCTAssertTrue(restored.inputAllowed)
        XCTAssertEqual(restored.active?.branches.first { $0.id == branchID }?.moves, branchMoves)
        XCTAssertEqual(restored.active?.branches.first { $0.id == rootID }?.moves, resumedMain)
        XCTAssertEqual(restored.games.count, 1)
    }

    func testNestedForksAndAncestorForksFormATreeWithoutMerging() throws {
        var record = SavedGame(playerWhite: true)
        record.moves = ["e2e4", "e7e5", "g1f3", "b8c6"]
        record.notation = ["e4", "e5", "Nf3", "Nc6"]
        record.ratings = [.good, .ok, .good, .good]
        record.result = "0-1"
        record.reason = "Resigned"
        let root = record.id
        record.fork(at: 2, seconds: 600)
        let child = record.branchID
        XCTAssertEqual(record.branches.first?.result, "0-1")
        XCTAssertEqual(record.ratings, [.good, .ok])
        record.moves += ["f1c4", "g8f6", "d2d3", "f8c5"]
        record.notation += ["Bc4", "Nf6", "d3", "Bc5"]
        record.fork(at: 4, seconds: 600)
        let nested = record.branchID
        XCTAssertEqual(record.branches.last?.parentID, child)
        XCTAssertEqual(record.branchPoints.map(\.ply), [2, 4])
        XCTAssertEqual(record.branchPoints.map(\.selectedIndex), [1, 1])
        record.fork(at: 1, seconds: 600)
        XCTAssertEqual(record.branches.last?.parentID, root, "Earlier forks attach to the shared ancestor")
        XCTAssertEqual(record.depth(of: nested), 2)
        record.selectBranch(child)
        XCTAssertEqual(record.moves, ["e2e4", "e7e5", "f1c4", "g8f6", "d2d3", "f8c5"])
        record.selectBranch(root)
        XCTAssertEqual(record.reason, "Resigned")
        record.fork(at: 2, seconds: 600)
        record.moves += ["g1f3", "b8c6"]
        record.notation += ["Nf3", "Nc6"]
        record.syncSelectedBranch()
        XCTAssertNotEqual(record.branchID, root, "Identical positions and even identical moves never merge histories")
        XCTAssertEqual(Set(record.branches.map(\.id)).count, record.branchCount)
        for branch in record.branches {
            if let parentID = branch.parentID {
                let parent = try XCTUnwrap(record.branches.first { $0.id == parentID })
                XCTAssertEqual(Array(parent.moves.prefix(branch.forkPly)), Array(branch.moves.prefix(branch.forkPly)))
                XCTAssertLessThan(record.depth(of: branch.id), record.branchCount)
            }
        }
        let restored = try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(restored, record)
    }

    func testNestedBranchSwipeAndUndoPreserveOriginalLines() async throws {
        let (game, _) = try await makeGame()
        var main = SavedGame(playerWhite: true)
        main.moves = ["e2e4", "e7e5", "g1f3", "b8c6"]
        game.openPuzzle(main)
        try await settle(game)
        game.seek(2)
        try await settle(game)
        game.practiceFromHere()
        try await settle(game)
        try await play("f1c4", in: game)
        let child = try XCTUnwrap(game.active?.branchID)
        let childFork = try XCTUnwrap(game.active?.moves)
        game.play(try XCTUnwrap(game.snapshot?.legal.first))
        try await settle(game)
        let childMoves = try XCTUnwrap(game.active?.moves)
        game.seek(4)
        try await settle(game)
        game.practiceFromHere()
        try await settle(game)
        let nested = try XCTUnwrap(game.active?.branchID)
        XCTAssertEqual(game.active?.branches.last?.parentID, child)
        game.play(try XCTUnwrap(game.snapshot?.legal.first))
        try await settle(game)
        XCTAssertEqual(game.active?.branchPoints.map(\.ply), [2, 4])
        game.switchBranch(direction: -1, at: 4)
        try await settle(game)
        XCTAssertEqual(game.reviewGame?.branchID, child)
        XCTAssertEqual(game.reviewGame?.moves, childMoves)
        game.switchBranch(direction: 1, at: 4)
        try await settle(game)
        XCTAssertEqual(game.reviewGame?.branchID, nested)
        game.switchBranch(direction: -1, at: 2)
        try await settle(game)
        XCTAssertEqual(game.reviewGame?.branchID, main.id)
        XCTAssertEqual(game.reviewGame?.moves, main.moves)
        game.selectBranch(child)
        try await settle(game)
        game.returnToLatest()
        try await settle(game)
        XCTAssertEqual(game.active?.moves, childMoves)
        game.undo()
        try await settle(game)
        XCTAssertEqual(game.active?.moves, childFork)
        XCTAssertEqual(game.active?.branches.first { $0.id == child }?.moves, childMoves, "Undo preserves the abandoned continuation")
        XCTAssertEqual(game.games.count, 1)
    }

    func testUIKitMoveSelectionRedoAndBranchPages() async throws {
        let (game, _) = try await makeGame()
        var record = SavedGame(playerWhite: true)
        record.moves = ["e2e4", "e7e5", "g1f3", "b8c6"]
        game.openPuzzle(record)
        try await settle(game)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = try XCTUnwrap(scene.windows.first)
        let original = window.rootViewController
        defer { window.rootViewController = original }
        let screen = GameViewController(game: game)
        window.rootViewController = ChessNavigationController(rootViewController: screen)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        try await settle(game)
        screen.updateView()
        screen.view.layoutIfNeeded()
        let board = try XCTUnwrap(descendants(of: screen.view).first { $0 is ChessBoardView } as? ChessBoardView)
        XCTAssertEqual(board.frame.width, screen.view.bounds.width, accuracy: 0.5, "History controls retain the edge-to-edge portrait board")
        func button(_ id: String) throws -> UIButton {
            try XCTUnwrap(descendants(of: screen.view).first { $0.accessibilityIdentifier == id } as? UIButton)
        }
        let move = try button("move-ply-3")
        move.sendActions(for: .touchUpInside)
        try await settle(game)
        XCTAssertEqual(game.cursorPly, 3)
        XCTAssertTrue(game.reviewing)
        screen.updateView()
        XCTAssertFalse(descendants(of: screen.view).contains { $0.accessibilityIdentifier == "continue-here" })
        XCTAssertFalse(descendants(of: screen.view).contains { $0.accessibilityLabel == "First move" || $0.accessibilityLabel == "Previous move" })
        let redo = try button("redo-ply-3")
        XCTAssertFalse(redo.isHidden)
        XCTAssertEqual(redo.configuration?.title, "重走")
        redo.sendActions(for: .touchUpInside)
        try await settle(game)
        XCTAssertFalse(game.reviewing)
        XCTAssertEqual(game.active?.moves.count, 2)
        try await play("f1c4", in: game)
        let newBranch = try XCTUnwrap(game.active?.branchID)
        screen.updateView()
        screen.view.layoutIfNeeded()
        let marker = try button("move-ply-2")
        XCTAssertNotNil(marker.configuration?.image)
        XCTAssertTrue(marker.accessibilityLabel?.contains("branch point") == true)
        let table = try XCTUnwrap(descendants(of: screen.view).first { $0.accessibilityIdentifier == "move-timeline" } as? UITableView)
        XCTAssertTrue(table.gestureRecognizers?.contains { $0 is UIPanGestureRecognizer && $0.delegate === screen } == true,
                      "Horizontal paging has its own gesture delegate instead of competing with vertical scroll")
        func pager() throws -> UIPageControl {
            try XCTUnwrap(descendants(of: screen.view).first { $0.accessibilityIdentifier == "fork-pager-2" } as? UIPageControl)
        }
        let mainPage = try pager()
        XCTAssertEqual(mainPage.numberOfPages, 2)
        mainPage.currentPage = 0
        mainPage.sendActions(for: .valueChanged)
        try await settle(game)
        XCTAssertEqual(game.record?.branchID, record.id)
        XCTAssertEqual(game.record?.moves, record.moves)
        screen.updateView()
        screen.view.layoutIfNeeded()
        let branchPage = try pager()
        branchPage.currentPage = 1
        branchPage.sendActions(for: .valueChanged)
        try await settle(game)
        XCTAssertEqual(game.record?.branchID, newBranch)
        screen.updateView()
        screen.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        writeReviewImage(image, named: "BranchTimeline")
        let attachment = XCTAttachment(image: image)
        attachment.name = "BranchTimeline"
        attachment.lifetime = .keepAlways
        add(attachment)
        try button("return-to-latest").sendActions(for: .touchUpInside)
        try await settle(game)
        XCTAssertFalse(game.reviewing)
        XCTAssertEqual(game.active?.branchID, newBranch)
    }

    func testBranchPagingKeepsSharedRowsAndScrollPosition() async throws {
        let (game, _) = try await makeGame()
        game.settings.moveRatingsEnabled = true
        var record = SavedGame(playerWhite: true)
        record.moves = ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "f8c5", "d2d3", "g8f6",
                        "b1c3", "d7d6", "c1g5", "h7h6", "g5h4", "c8e6", "c4e6", "f7e6"]
        record.notation = ["e4", "e5", "Nf3", "Nc6", "Bc4", "Bc5", "d3", "Nf6",
                           "Nc3", "d6", "Bg5", "h6", "Bh4", "Be6", "Bxe6", "fxe6"]
        record.ratings = Array(repeating: .good, count: record.moves.count)
        let root = record.id
        record.fork(at: 5, seconds: 600)
        record.moves += ["g8f6", "d2d3", "f8c5", "b1c3", "d7d6"]
        record.notation += ["Nf6", "d3", "Bc5", "Nc3", "d6"]
        record.ratings = Array(repeating: .good, count: record.moves.count)
        record.syncSelectedBranch()
        let child = record.branchID
        record.fork(at: 8, seconds: 600)
        record.moves += ["b1d2", "d7d6"]
        record.notation += ["Nd2", "d6"]
        record.ratings = Array(repeating: .good, count: record.moves.count)
        record.syncSelectedBranch()
        let nested = record.branchID
        record.selectBranch(child)
        game.review(record)
        try await settle(game)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = try XCTUnwrap(scene.windows.first)
        let original = window.rootViewController
        defer { window.rootViewController = original }
        let screen = GameViewController(game: game)
        window.rootViewController = ChessNavigationController(rootViewController: screen)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 300_000_000)
        screen.updateView()
        screen.view.layoutIfNeeded()
        let table = try XCTUnwrap(descendants(of: screen.view).first {
            $0.accessibilityIdentifier == "move-timeline"
        } as? UITableView)
        table.setContentOffset(CGPoint(x: 0, y: 70), animated: false)
        table.layoutIfNeeded()
        let sharedIndex = IndexPath(row: 2, section: 0)
        let shared = try XCTUnwrap(table.cellForRow(at: sharedIndex))
        let sharedFrame = shared.convert(shared.bounds, to: window)
        let fork = try XCTUnwrap(table.cellForRow(at: IndexPath(row: 3, section: 0)))
        let forkFrame = fork.convert(fork.bounds, to: window)
        let offset = table.contentOffset
        let continuation = try XCTUnwrap(table.cellForRow(at: IndexPath(row: 4, section: 0)))
        let drag = TimelineTestPan()
        drag.point = CGPoint(x: table.bounds.midX, y: table.rectForRow(at: IndexPath(row: 4, section: 0)).midY)
        drag.phase = .began
        screen.perform(NSSelectorFromString("pannedHistory:"), with: drag)
        drag.phase = .changed
        drag.travel = CGPoint(x: 40, y: 0)
        screen.perform(NSSelectorFromString("pannedHistory:"), with: drag)
        XCTAssertEqual(continuation.transform.tx, 40, accuracy: 0.5,
                       "The continuation follows a horizontal drag")
        XCTAssertEqual(shared.transform, .identity)
        XCTAssertEqual(fork.transform, .identity)
        writeReviewImage(UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }, named: "PartialBranchDrag")
        drag.phase = .cancelled
        screen.perform(NSSelectorFromString("pannedHistory:"), with: drag)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(continuation.transform, .identity, "A cancelled drag restores the continuation")
        screen.pageBranch(direction: -1, at: 5)
        screen.updateView()
        XCTAssertEqual(game.record?.branchID, root)
        XCTAssertTrue(table.cellForRow(at: sharedIndex) === shared,
                      "The shared white move before a mid-turn fork is not recreated")
        XCTAssertTrue(table.cellForRow(at: IndexPath(row: 3, section: 0)) === fork,
                      "The branch pager stays in place while its continuation pages")
        XCTAssertNil(table.layer.animation(forKey: "branch-page"), "Never animate the whole table")
        XCTAssertEqual(shared.transform, .identity)
        XCTAssertEqual(fork.transform, .identity)
        XCTAssertEqual(table.contentOffset.y, offset.y, accuracy: 0.5)
        try await settle(game)
        screen.view.layoutIfNeeded()
        XCTAssertEqual(shared.convert(shared.bounds, to: window).minY, sharedFrame.minY, accuracy: 0.5)
        XCTAssertEqual(fork.convert(fork.bounds, to: window).minY, forkFrame.minY, accuracy: 0.5)
        // Switching back to a shorter line must not jump to the selected move or
        // pull the shared history upward when the table's content becomes shorter.
        screen.pageBranch(direction: 1, at: 5)
        screen.updateView()
        try await settle(game)
        XCTAssertEqual(game.record?.branchID, child)
        XCTAssertTrue(table.cellForRow(at: sharedIndex) === shared)
        XCTAssertEqual(table.contentOffset.y, offset.y, accuracy: 0.5)
        XCTAssertEqual(shared.convert(shared.bounds, to: window).minY, sharedFrame.minY, accuracy: 0.5)
        screen.pageBranch(direction: 1, at: 8)
        screen.updateView()
        try await settle(game)
        XCTAssertEqual(game.record?.branchID, nested)
        XCTAssertTrue(table.cellForRow(at: sharedIndex) === shared, "Nested paging preserves ancestor rows")
        XCTAssertEqual(table.contentOffset.y, offset.y, accuracy: 0.5)
        screen.pageBranch(direction: -1, at: 8)
        try await settle(game)
        XCTAssertEqual(game.record?.branchID, child)
        screen.pageBranch(direction: -1, at: 5)
        try await settle(game)
        XCTAssertEqual(game.record?.branchID, root)
        screen.pageBranch(direction: -1, at: 5)
        XCTAssertEqual(game.record?.branchID, root, "Paging beyond the first branch changes nothing")
        table.setContentOffset(CGPoint(x: 0, y: max(0, table.contentSize.height - table.bounds.height)), animated: false)
        let bottomOffset = table.contentOffset.y
        screen.pageBranch(direction: 1, at: 5)
        screen.updateView()
        try await settle(game)
        XCTAssertEqual(game.record?.branchID, child)
        XCTAssertEqual(table.contentOffset.y, bottomOffset, accuracy: 0.5,
                       "A shorter continuation preserves even a scroll position near the old bottom")
        XCTAssertGreaterThan(table.contentInset.bottom, 0)
        writeReviewImage(UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }, named: "ShortBranchAfterPaging")
    }

    func testRedoSelectedMoveOnlyAllowsHumanAndRewindsBeforeIt() async throws {
        let (game, _) = try await makeGame()
        var record = SavedGame(playerWhite: true)
        record.moves = ["e2e4", "e7e5", "g1f3", "b8c6"]
        record.ratings = [.good, .ok, .good, .good]
        game.openPuzzle(record)
        try await settle(game)
        game.review(try XCTUnwrap(game.active))
        try await settle(game)
        XCTAssertFalse(game.canRedoSelectedMove, "Opening review does not select a move for redo")
        game.seek(2)
        try await settle(game)
        XCTAssertFalse(game.canRedoSelectedMove, "The human cannot redo the bot's move")
        game.redoSelectedMove()
        XCTAssertTrue(game.reviewing)
        game.seek(3)
        XCTAssertFalse(game.canRedoSelectedMove, "Redo waits for the historical position to finish loading")
        try await settle(game)
        XCTAssertTrue(game.canRedoSelectedMove)
        game.redoSelectedMove()
        try await settle(game)
        XCTAssertEqual(game.active?.id, record.id)
        XCTAssertEqual(game.active?.moves, ["e2e4", "e7e5"], "Redo removes the selected move, rather than continuing after it")
        XCTAssertEqual(game.active?.ratings, [.good, .ok])
        XCTAssertTrue(game.inputAllowed)
        XCTAssertEqual(game.active?.branches.first?.moves, record.moves)
        try await play("f1c4", in: game)
        XCTAssertEqual(game.active?.moves.prefix(3), ["e2e4", "e7e5", "f1c4"])
        XCTAssertEqual(game.active?.branches.first?.moves, record.moves)
        XCTAssertEqual(game.games.count, 1)

        var black = SavedGame(playerWhite: false)
        black.moves = record.moves
        game.review(black)
        try await settle(game)
        game.seek(1)
        try await settle(game)
        XCTAssertFalse(game.canRedoSelectedMove)
        game.seek(2)
        try await settle(game)
        XCTAssertTrue(game.canRedoSelectedMove)
        game.redoSelectedMove()
        try await settle(game)
        XCTAssertEqual(game.active?.moves, ["e2e4"])
        XCTAssertFalse(game.whiteToMove)
        XCTAssertTrue(game.inputAllowed)

        var blackStart = SavedGame(playerWhite: false, isPuzzle: true)
        blackStart.baseFEN = "4k3/8/8/8/8/8/8/K3R3 b - - 0 1"
        blackStart.moves = ["e8d8", "e1e2"]
        game.review(blackStart)
        try await settle(game)
        game.seek(1)
        try await settle(game)
        XCTAssertTrue(game.canRedoSelectedMove)
        game.redoSelectedMove()
        try await settle(game)
        XCTAssertEqual(game.active?.moves, [])
        XCTAssertTrue(game.inputAllowed)
        XCTAssertFalse(game.whiteAtBottom)
    }

    func testRedoCanReplaceTheHumansCheckmatingMove() async throws {
        let (game, _) = try await makeGame()
        var record = SavedGame(playerWhite: false)
        record.moves = ["f2f3", "e7e5", "g2g4", "d8h4"]
        game.openPuzzle(record)
        try await settle(game)
        game.review(try XCTUnwrap(game.active))
        try await settle(game)
        game.seek(4)
        try await settle(game)
        XCTAssertEqual(game.snapshot?.reason, "Checkmate")
        XCTAssertTrue(game.canRedoSelectedMove)
        game.redoSelectedMove()
        try await settle(game)
        XCTAssertEqual(game.active?.moves.count, 3)
        XCTAssertFalse(game.gameOver)
        XCTAssertTrue(game.inputAllowed)
        XCTAssertEqual(game.active?.branches.first?.reason, "Checkmate")
        XCTAssertEqual(game.active?.branches.first?.result, "0-1")
    }

    func testCheckAndCheckmateMarkersFollowReplayAndOrientation() async throws {
        let (game, _) = try await makeGame()
        var mate = SavedGame(playerWhite: false)
        mate.moves = ["f2f3", "e7e5", "g2g4", "d8h4"]
        game.openPuzzle(mate)
        try await settle(game)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = try XCTUnwrap(scene.windows.first)
        let original = window.rootViewController
        defer { window.rootViewController = original }
        let screen = GameViewController(game: game)
        window.rootViewController = ChessNavigationController(rootViewController: screen)
        window.makeKeyAndVisible()
        func render() {
            screen.updateView()
            window.layoutIfNeeded()
            screen.view.layoutIfNeeded()
        }
        render()
        let board = try XCTUnwrap(descendants(of: screen.view).first { $0 is ChessBoardView } as? ChessBoardView)
        let marker = try XCTUnwrap(descendants(of: board).first { $0.accessibilityIdentifier == "checkmate-marker" })
        func kingSquare(_ coordinate: String) throws -> UIView {
            try XCTUnwrap(descendants(of: board).first { $0.accessibilityIdentifier == "square-\(coordinate)" })
        }
        func assertMarkerOnKing(_ coordinate: String, state: String = "Checkmate", file: StaticString = #filePath, line: UInt = #line) throws {
            let king = try kingSquare(coordinate)
            XCTAssertEqual(king.accessibilityValue, state, file: file, line: line)
            XCTAssertFalse(marker.isHidden, file: file, line: line)
            let kingFrame = king.convert(king.bounds, to: board)
            let markerFrame = marker.convert(marker.bounds, to: board)
            XCTAssertTrue(kingFrame.contains(markerFrame), file: file, line: line)
            XCTAssertLessThan(markerFrame.width, kingFrame.width * 0.5, "End icons stay small and leave the king visible",
                              file: file, line: line)
            XCTAssertGreaterThan(markerFrame.minX, kingFrame.midX, "End icons sit in the upper-right corner",
                                 file: file, line: line)
            XCTAssertLessThan(markerFrame.maxY, kingFrame.midY, file: file, line: line)
        }
        try assertMarkerOnKing("e1")
        XCTAssertFalse(descendants(of: screen.view).contains {
            ($0 as? UILabel)?.text == "Checkmate · 0-1" || ($0 as? UILabel)?.text == "Beginner"
        })
        XCTAssertEqual(board.frame.minY, screen.view.safeAreaLayoutGuide.layoutFrame.minY + 38, accuracy: 0.5,
                       "The removed status row must not leave a gap above the captured tray")
        writeReviewImage(UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }, named: "CheckmateBoard")
        game.flipped.toggle()
        render()
        try assertMarkerOnKing("e1")

        game.seek(3)
        try await settle(game)
        render()
        XCTAssertTrue(marker.isHidden, "Replaying before mate clears its marker")
        XCTAssertEqual(try kingSquare("e1").accessibilityValue, "")

        var check = SavedGame(playerWhite: false, isPuzzle: true)
        check.baseFEN = "4k3/8/8/8/8/8/8/K3R3 b - - 0 1"
        game.openPuzzle(check)
        try await settle(game)
        render()
        XCTAssertTrue(game.snapshot?.inCheck == true)
        XCTAssertFalse(game.gameOver)
        XCTAssertEqual(try kingSquare("e8").accessibilityValue, "Check")
        XCTAssertTrue(marker.isHidden, "A king with legal escapes has no ending marker")
        writeReviewImage(UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }, named: "CheckBoard")

        var blackMate = SavedGame(playerWhite: true)
        blackMate.moves = ["e2e4", "e7e5", "f1c4", "b8c6", "d1h5", "g8f6", "h5f7"]
        game.review(blackMate)
        try await settle(game)
        render()
        try assertMarkerOnKing("e8")

        var stalemate = SavedGame(playerWhite: false, isPuzzle: true)
        stalemate.baseFEN = "7k/5K2/6Q1/8/8/8/8/8 b - - 0 1"
        game.review(stalemate)
        try await settle(game)
        render()
        XCTAssertFalse(try XCTUnwrap(game.snapshot).inCheck)
        XCTAssertEqual(marker.accessibilityIdentifier, "stalemate-marker")
        try assertMarkerOnKing("h8", state: "Stalemate")
        writeReviewImage(UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }, named: "StalemateBoard")
        game.flipped.toggle()
        render()
        try assertMarkerOnKing("h8", state: "Stalemate")
        game.review(check)
        try await settle(game)
        render()
        XCTAssertTrue(marker.isHidden, "Leaving stalemate clears the pause badge")

        game.openPuzzle(SavedGame(playerWhite: true))
        try await settle(game)
        game.handleTap(squareIndex("g1"))
        render()
        XCTAssertEqual(game.selectedSquare, squareIndex("g1"))
        writeReviewImage(UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }, named: "SelectedBoard")
    }

    func testEndingHapticsOnlyFireForNewLiveMoves() async throws {
        let (game, _) = try await makeGame()
        game.settings.moveRatingsEnabled = false
        var record = SavedGame(playerWhite: false)
        record.moves = ["f2f3", "e7e5", "g2g4"]
        game.openPuzzle(record)
        try await settle(game)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = try XCTUnwrap(scene.windows.first)
        let original = window.rootViewController
        defer { window.rootViewController = original }
        var feedback: [UINotificationFeedbackGenerator.FeedbackType] = []
        let screen = GameViewController(game: game, endFeedback: { feedback.append($0) })
        window.rootViewController = ChessNavigationController(rootViewController: screen)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        try await settle(game)
        screen.updateView()
        try await play("d8h4", in: game)
        screen.updateView()
        XCTAssertEqual(game.snapshot?.reason, "Checkmate")
        XCTAssertEqual(feedback, [.success], "A newly played checkmate emits one ending notification")
        screen.updateView()
        game.flipped.toggle()
        screen.updateView()
        game.seek(3)
        try await settle(game)
        screen.updateView()
        game.seek(4)
        try await settle(game)
        screen.updateView()
        game.returnToLatest()
        try await settle(game)
        screen.updateView()
        XCTAssertEqual(feedback, [.success], "Redraw, flipping, replay, and returning to a completed line are silent")

        var stalemate = SavedGame(playerWhite: true, isPuzzle: true)
        stalemate.baseFEN = "7k/5K2/8/6Q1/8/8/8/8 w - - 0 1"
        game.openPuzzle(stalemate)
        try await settle(game)
        screen.updateView()
        try await play("g5g6", in: game)
        screen.updateView()
        XCTAssertEqual(game.snapshot?.reason, "Stalemate")
        XCTAssertEqual(feedback, [.success, .warning], "A newly played stalemate emits its own ending notification")
        screen.updateView()
        game.flipped.toggle()
        screen.updateView()
        XCTAssertEqual(feedback.count, 2)

        game.settings.haptics = false
        var muted = SavedGame(playerWhite: true, isPuzzle: true)
        muted.baseFEN = stalemate.baseFEN
        game.openPuzzle(muted)
        try await settle(game)
        screen.updateView()
        try await play("g5g6", in: game)
        screen.updateView()
        XCTAssertEqual(feedback.count, 2, "The haptics setting also disables ending feedback")
    }

    func testRatingsRecognizeMateAndBlundersForBothColors() async throws {
        let engine = ArasanEngine(resources: Bundle.main.resourcePath!)
        let whiteBlunder = try await engine.rate(fen: GameViewModel.startFEN, moves: ["f2f3", "e7e5"], candidate: "g2g4")
        XCTAssertEqual(whiteBlunder, .bad)
        let mate = try await engine.rate(fen: GameViewModel.startFEN, moves: ["f2f3", "e7e5", "g2g4"], candidate: "d8h4")
        XCTAssertEqual(mate, .good)
        let blackFirst = GameViewModel.startFEN.replacingOccurrences(of: " w ", with: " b ")
        let blackBlunder = try await engine.rate(fen: blackFirst, moves: ["f7f6", "e2e4"], candidate: "g7g5")
        XCTAssertEqual(blackBlunder, .bad)
    }

    func testPieceIdentitiesAndCapturedTraysThroughUndo() async throws {
        let (game, _) = try await makeGame()
        game.newGame()
        try await settle(game)
        let whitePawnID = try XCTUnwrap(game.board[squareIndex("e2")]?.id)
        let blackPawnID = try XCTUnwrap(game.board[squareIndex("d7")]?.id)
        let blackQueenID = try XCTUnwrap(game.board[squareIndex("d8")]?.id)
        var record = try XCTUnwrap(game.active)
        record.moves = ["e2e4", "d7d5", "e4d5", "d8d5"]
        game.openPuzzle(record)
        try await settle(game)
        XCTAssertEqual(game.board[squareIndex("d5")]?.id, blackQueenID)
        XCTAssertEqual(game.capturedPieces(byWhite: true).map(\.kind), ["p"])
        XCTAssertEqual(game.capturedPieces(byWhite: false).map(\.kind), ["P"])
        game.undo()
        try await settle(game)
        XCTAssertEqual(game.board[squareIndex("d8")]?.id, blackQueenID)
        XCTAssertEqual(game.board[squareIndex("e4")]?.id, whitePawnID)
        XCTAssertEqual(game.board[squareIndex("d5")]?.id, blackPawnID)
        XCTAssertTrue(game.capturedPieces(byWhite: true).isEmpty)
        XCTAssertTrue(game.capturedPieces(byWhite: false).isEmpty)
        game.undo()
        try await settle(game)
        XCTAssertEqual(game.board[squareIndex("e2")]?.id, whitePawnID)
        XCTAssertEqual(game.board[squareIndex("d7")]?.id, blackPawnID)
        XCTAssertTrue(game.capturedPieces(byWhite: true).isEmpty)
        let ids = game.board.compactMap { $0?.id }
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testPracticeTimerPauseRestoreExpiryAndNewGame() async throws {
        var date = Date(timeIntervalSince1970: 1000)
        let (game, url) = try await makeGame(now: { date })
        XCTAssertEqual(game.settings.practiceMinutes, 10)
        game.newGame()
        try await settle(game)
        game.setPracticeVisible(true)
        XCTAssertEqual(game.practiceTimeRemaining(), 600)
        date += 65
        XCTAssertEqual(game.practiceTimeRemaining(), 535)
        game.setSuspended(true, gameVisible: true)
        date += 300
        XCTAssertEqual(game.practiceTimeRemaining(), 535)
        let restored = GameViewModel(storageURL: url, now: { date })
        try await waitUntil("timer restored") { restored.ready }
        XCTAssertEqual(restored.practiceTimeRemaining(), 535)
        game.setSuspended(false, gameVisible: true)
        date += 35
        XCTAssertEqual(game.practiceTimeRemaining(), 500)
        game.setPracticeVisible(false)
        date += 60
        XCTAssertEqual(game.practiceTimeRemaining(), 500)
        game.setPracticeVisible(true)
        date += 600
        XCTAssertEqual(game.practiceTimeRemaining(), 0)
        XCTAssertFalse(game.gameOver, "Practice timer must not invent a game result")
        game.settings.practiceMinutes = 15
        game.newGame()
        try await settle(game)
        XCTAssertEqual(game.practiceTimeRemaining(), 900)
        date += 5
        game.resign()
        date += 20
        XCTAssertEqual(game.practiceTimeRemaining(), 895)
    }

    func testRatingPersistenceUndoCancellationAndLegacyLibrary() async throws {
        let (game, url) = try await makeGame()
        game.settings.moveRatingsEnabled = true
        game.newGame()
        try await settle(game)
        try await play("e2e4", in: game)
        XCTAssertEqual(game.active?.ratings?.compactMap { $0 }.count, 2)
        let restored = GameViewModel(storageURL: url)
        try await waitUntil("restored ratings") { restored.ready }
        XCTAssertTrue(restored.settings.moveRatingsEnabled)
        XCTAssertEqual(restored.active?.ratings, game.active?.ratings)
        game.undo()
        try await settle(game)
        XCTAssertEqual(game.active?.ratings?.count, 0)
        // Observe the event instead of polling: a cached rating can finish
        // between polling intervals. Schedule cancellation after the setter.
        let cancelled = expectation(description: "New game during move rating")
        let observer = game.$isRating.filter { $0 }.first().sink { _ in
            Task { @MainActor in
                game.newGame()
                cancelled.fulfill()
            }
        }
        game.play(try XCTUnwrap(game.snapshot?.legal.first { $0.uci == "e2e4" }))
        await fulfillment(of: [cancelled], timeout: 5)
        observer.cancel()
        try await settle(game)
        XCTAssertEqual(game.active?.moves.count, 0)
        XCTAssertNil(game.active?.ratings)
        game.settings.moveRatingsEnabled = false
        try await play("d2d4", in: game)
        XCTAssertNil(game.active?.ratings)
        // Simulate an actual pre-feature library: new keys are absent, not null.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var settings = try XCTUnwrap(json["settings"] as? [String: Any])
        settings.removeValue(forKey: "rateMoves")
        json["settings"] = settings
        let oldData = try JSONSerialization.data(withJSONObject: json)
        let legacy = try JSONDecoder().decode(LocalLibrary.self, from: oldData)
        XCTAssertFalse(legacy.settings.moveRatingsEnabled)
        XCTAssertEqual(legacy.games.count, game.games.count)
    }
}
