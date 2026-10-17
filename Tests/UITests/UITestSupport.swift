import XCTest
import UIKit

// Deliberately use the on-disk JSON contract, without linking the app or calling its models.
enum LibraryFixture {
    static let start = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    static let opening = ["e2e4", "e7e5", "g1f3", "b8c6"]
    static let openingSAN = ["e4", "e5", "Nf3", "Nc6"]

    static func settings(_ overrides: [String: Any] = [:]) -> [String: Any] {
        var values: [String: Any] = [
            "playWhite": true, "skill": 2, "thinkSeconds": 0.4,
            "showLegalMoves": true, "coordinates": true, "haptics": false,
            "boardTheme": "Slate", "rateMoves": false, "timerMinutes": 10
        ]
        values.merge(overrides) { _, next in next }
        return values
    }

    static func game(fen: String = start, white: Bool = true, puzzle: Bool = true,
                     moves: [String] = [], notation: [String] = [],
                     seconds: Double = 600, result: String = "*", reason: String = "",
                     overrides: [String: Any] = [:]) -> [String: Any] {
        var values: [String: Any] = [
            "id": UUID().uuidString, "date": 800_000_000.0,
            "playerWhite": white, "isPuzzle": puzzle, "baseFEN": fen,
            "moves": moves, "notation": notation, "practiceSeconds": seconds,
            "result": result, "reason": reason
        ]
        values.merge(overrides) { _, next in next }
        return values
    }

    static func tree() -> [String: Any] {
        var record = game(moves: opening, notation: openingSAN)
        let main = record["id"] as! String
        let child = UUID().uuidString
        let nested = UUID().uuidString
        func branch(_ id: String, parent: String?, ply: Int, moves: [String],
                    notation: [String], seconds: Double) -> [String: Any] {
            var branch: [String: Any] = [
                "id": id, "forkPly": ply, "date": 800_000_000.0, "moves": moves,
                "notation": notation, "practiceSeconds": seconds, "result": "*", "reason": ""
            ]
            if let parent { branch["parentID"] = parent }
            return branch
        }
        record["branches"] = [
            branch(main, parent: nil, ply: 0, moves: opening, notation: openingSAN, seconds: 420),
            branch(child, parent: main, ply: 2, moves: ["e2e4", "e7e5", "f1c4", "g8f6"],
                   notation: ["e4", "e5", "Bc4", "Nf6"], seconds: 300),
            branch(nested, parent: child, ply: 4,
                   moves: ["e2e4", "e7e5", "f1c4", "g8f6", "d2d3", "b8c6"],
                   notation: ["e4", "e5", "Bc4", "Nf6", "d3", "Nc6"], seconds: 180)
        ]
        record["selectedBranchID"] = main
        record["practiceSeconds"] = 420
        return record
    }
}

@MainActor
class ChessUITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        if let app, (testRun?.totalFailureCount ?? 0) > 0 {
            capture("Failure")
            let description = app.debugDescription
            print("UI failure hierarchy:\n\(description)")
            let hierarchy = XCTAttachment(string: description)
            hierarchy.name = "Accessibility hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        app?.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func launch(games: [[String: Any]] = [], settings: [String: Any] = [:],
                appearance: String? = nil) throws {
        app?.terminate()
        app = XCUIApplication()
        var library: [String: Any] = ["settings": LibraryFixture.settings(settings), "games": games]
        if let id = games.first?["id"] { library["activeID"] = id }
        let json = try JSONSerialization.data(withJSONObject: library, options: [.sortedKeys])
        app.launchEnvironment = [
            "FORKCHESS_UI_TEST_ID": UUID().uuidString,
            "FORKCHESS_UI_TEST_LIBRARY": String(decoding: json, as: UTF8.self)
        ]
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if let appearance { app.launchArguments += ["-AppleInterfaceStyle", appearance] }
        app.launch()
        app.launchEnvironment.removeValue(forKey: "FORKCHESS_UI_TEST_LIBRARY")
        waitEnabled(app.buttons["Start new game"])
    }

    func relaunch() {
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "FORKCHESS_UI_TEST_LIBRARY")
        app.launch()
        waitEnabled(app.buttons["Start new game"])
    }

    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    func wait(_ condition: @escaping () -> Bool, _ message: String = "UI state",
              timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed,
                       "Timed out waiting for \(message)", file: file, line: line)
    }

    func waitEnabled(_ control: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        wait({ control.exists && control.isEnabled && control.isHittable },
             "\(control) enabled", file: file, line: line)
    }

    func tap(_ control: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        waitEnabled(control, file: file, line: line)
        control.tap()
    }

    func square(_ coordinate: String) -> XCUIElement { app.buttons["square-\(coordinate)"] }
    func move(_ ply: Int) -> XCUIElement { app.buttons["move-ply-\(ply)"] }
    var timeline: XCUIElement { app.tables["move-timeline"] }

    func assertPiece(_ coordinate: String, _ piece: String, file: StaticString = #filePath, line: UInt = #line) {
        wait({ self.square(coordinate).label == "\(piece) \(coordinate)" },
             "\(piece) on \(coordinate)", file: file, line: line)
    }

    func assertValue(_ control: XCUIElement, _ value: String, file: StaticString = #filePath, line: UInt = #line) {
        wait({ control.exists && (control.value as? String) == value },
             "value \(value)", file: file, line: line)
    }

    func start(white: Bool = true) {
        tap(app.buttons[white ? "Play White" : "Play Black"])
        tap(app.buttons["Start new game"])
        waitEnabled(app.buttons["Hint"])
    }

    func play(_ from: String, _ to: String, replyPly: Int? = nil) {
        waitEnabled(app.buttons["Hint"])
        tap(square(from))
        assertValue(square(from), "Selected")
        tap(square(to))
        if let replyPly {
            wait({ self.move(replyPly).exists }, "bot reply \(replyPly)")
            waitEnabled(app.buttons["Hint"])
        }
    }

    func openPuzzle() {
        tap(app.buttons["Puzzle"])
        tap(app.collectionViews.cells.element(boundBy: 1))
        wait({ self.square("a1").exists }, "puzzle board")
    }

    func openHistory() {
        tap(app.buttons["open-game-history"])
        wait({ self.app.navigationBars["History"].exists }, "History page")
    }

    func openSettings(game: Bool = false) {
        tap(app.buttons[game ? "game-settings" : "Settings"])
        wait({ self.app.navigationBars[game ? "Game settings" : "Settings"].exists }, "settings sheet")
    }

    func done() {
        tap(app.buttons["settings-done"])
        wait({ !self.app.buttons["settings-done"].exists }, "settings dismissed")
    }

    func back(to title: String) {
        let navigationBack = app.navigationBars.buttons[title]
        let toolbarBack = app.toolbars.buttons["BackButton"]
        // UIKit can move navigation actions into an adaptive side toolbar.
        wait({ navigationBack.exists || toolbarBack.exists }, "back control for \(title)")
        tap(navigationBack.exists ? navigationBack : toolbarBack)
        if title == "Home" {
            waitEnabled(app.buttons["Start new game"])
        } else {
            wait({ self.app.navigationBars[title].exists }, "returned to \(title)")
        }
    }

    func cancelActionSheet(titled title: String) {
        wait({ self.app.staticTexts[title].exists }, "action sheet \(title)")
        let cancel = app.buttons["Cancel"]
        if cancel.exists { tap(cancel) }
        else {
            // Adaptive popovers omit Cancel on iPad and some iPhone layouts.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.2)).tap()
        }
        wait({ !self.app.staticTexts[title].exists }, "action sheet dismissed")
    }

    func reveal(_ control: XCUIElement, in scroll: XCUIElement? = nil,
                file: StaticString = #filePath, line: UInt = #line) {
        let scroll = scroll ?? app.tables["settings-list"]
        for upward in [true, false] {
            for _ in 0..<6 {
                if control.exists && control.isHittable { return }
                if upward { scroll.swipeUp(velocity: .fast) }
                else { scroll.swipeDown(velocity: .fast) }
            }
        }
        if control.exists && control.isHittable { return }
        XCTFail("Could not reveal \(control)", file: file, line: line)
    }

    func choose(_ picker: String, option: String) {
        let control = app.buttons[picker]
        reveal(control)
        tap(control)
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", option)).firstMatch)
    }

    func setSwitch(_ name: String, on: Bool) {
        let control = app.switches[name]
        reveal(control)
        let expected = on ? "1" : "0"
        if (control.value as? String) != expected { tap(control) }
        assertValue(control, expected)
    }

    func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func shareAndCopy(from control: XCUIElement) -> String {
        tap(control)
        let copyButton = app.buttons["Copy"]
        let copyCell = app.cells.matching(NSPredicate(format: "label == 'Copy'")).firstMatch
        wait({ copyButton.exists || copyCell.exists }, "system share sheet")
        let preview = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "[Event \"")).firstMatch
        wait({ preview.exists }, "system PGN preview")
        let pgn = preview.label
        capture("Share PGN")
        // Background UI runners cannot read another app's clipboard. Validate
        // the system preview text, then confirm Copy writes to the pasteboard.
        let changes = UIPasteboard.general.changeCount
        tap(copyButton.exists ? copyButton : copyCell)
        wait({ UIPasteboard.general.changeCount > changes }, "Copy updates the pasteboard")
        wait({ !copyButton.exists && !copyCell.exists }, "share sheet dismissed")
        return pgn
    }

    func place(_ piece: String, at coordinate: String) {
        tap(element("setup-square-\(coordinate)"))
        tap(app.buttons[piece])
        wait({ !self.app.buttons["Eraser"].exists }, "piece picker dismissal")
    }

    func timerSeconds() -> Int {
        let text = app.staticTexts["Practice time remaining"].value as? String ?? ""
        let numbers = text.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        return numbers.count == 2 ? numbers[0] * 60 + numbers[1] : -1
    }
}
