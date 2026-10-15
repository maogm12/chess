import Foundation
import Combine

struct BoardPiece: Equatable, Identifiable {
    let id: Int
    let kind: Character
    let isWhite: Bool
    var name: String {
        switch kind.lowercased() {
        case "p": return "pawn"
        case "n": return "knight"
        case "b": return "bishop"
        case "r": return "rook"
        case "q": return "queen"
        default: return "king"
        }
    }
}

enum MoveRating: String, Codable { case good = "Good", ok = "OK", bad = "Bad" }

enum PuzzleError: LocalizedError {
    case engineUnavailable
    case invalidPosition(String)

    var errorDescription: String? {
        switch self {
        case .engineUnavailable:
            return "The chess engine is still loading. Try again in a moment."
        case .invalidPosition(let reason):
            return reason
        }
    }
}

struct PracticeSettings: Codable, Equatable {
    var playWhite = true
    var skill = 5
    var thinkSeconds = 1.0
    var showLegalMoves = true
    var coordinates = true
    var haptics = true
    var boardTheme = "Slate"
    // Optional storage keeps libraries saved before this setting compatible.
    var rateMoves: Bool?
    var timerMinutes: Int?
    var practiceMinutes: Int {
        get { timerMinutes ?? 10 }
        set { timerMinutes = newValue }
    }
    var moveRatingsEnabled: Bool {
        get { rateMoves ?? false }
        set { rateMoves = newValue }
    }
    static let strengthPresets: [(name: String, skill: Int)] = [
        ("Beginner", 2), ("Casual", 6), ("Club", 11), ("Expert", 16), ("Full strength", 20)
    ]
    static func estimatedElo(for skill: Int) -> Int {
        // Arasan options.h: Options::getRating; ArasanBridge maps skill to skill * 5.
        // Engine estimate only, not a measured human rating for this device/time control.
        1000 + min(20, max(0, skill)) * 5 * (3450 - 1000) / 100
    }
    var strengthDescription: String {
        "\(difficulty) · ≈\(Self.estimatedElo(for: skill)) Elo"
    }
    var difficulty: String {
        GameSettings(defaults: self).difficulty
    }
}

struct GameSettings: Codable, Equatable {
    var skill: Int
    var thinkSeconds: Double
    var rateMoves: Bool
    var practiceMinutes: Int

    init(defaults: PracticeSettings) {
        skill = defaults.skill
        thinkSeconds = defaults.thinkSeconds
        rateMoves = defaults.moveRatingsEnabled
        practiceMinutes = defaults.practiceMinutes
    }

    var difficulty: String {
        switch skill {
        case 0...3: return "Beginner"
        case 4...8: return "Casual"
        case 9...13: return "Club"
        case 14...18: return "Expert"
        default: return "Full strength"
        }
    }
}

struct GameBranch: Codable, Identifiable, Equatable {
    var id: UUID
    var parentID: UUID?
    var forkPly: Int
    var date = Date()
    var moves: [String]
    var notation: [String]
    var ratings: [MoveRating?]?
    var practiceSeconds: TimeInterval?
    var result: String
    var reason: String

    init(record: SavedGame, id: UUID, parentID: UUID?, forkPly: Int) {
        self.id = id
        self.parentID = parentID
        self.forkPly = forkPly
        moves = record.moves
        notation = record.notation
        ratings = record.ratings
        practiceSeconds = record.practiceSeconds
        result = record.result
        reason = record.reason
    }
}

struct BranchPoint: Equatable {
    let ply: Int
    let options: [UUID]
    let selectedIndex: Int
}

struct SavedGame: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    var playerWhite: Bool
    var isPuzzle = false
    var baseFEN = GameViewModel.startFEN
    var moves: [String] = []
    var notation: [String] = []
    var ratings: [MoveRating?]?
    var practiceSeconds: TimeInterval?
    var result = "*"
    var reason = ""
    var branches: [GameBranch] = []
    var selectedBranchID: UUID?
    var configuration: GameSettings?
    var title: String { isSavedPractice ? "Puzzle" : "Play with bot" }
    var outcome: String { result == "*" ? "In progress" : reason + " · " + result }
    var defaultWhiteAtBottom: Bool {
        playerWhite && (!isSavedPractice || ChessPosition.whiteToMove(in: baseFEN))
    }

    init(playerWhite: Bool, isPuzzle: Bool = false) {
        self.playerWhite = playerWhite
        self.isPuzzle = isPuzzle
    }

    private enum CodingKeys: String, CodingKey {
        case id, date, playerWhite, isPuzzle, baseFEN, moves, notation, ratings, practiceSeconds, result, reason
        case branches, selectedBranchID, configuration
    }
    private enum LegacyKeys: String, CodingKey { case mode }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        date = try values.decode(Date.self, forKey: .date)
        playerWhite = try values.decode(Bool.self, forKey: .playerWhite)
        baseFEN = try values.decodeIfPresent(String.self, forKey: .baseFEN) ?? GameViewModel.startFEN
        moves = try values.decodeIfPresent([String].self, forKey: .moves) ?? []
        notation = try values.decodeIfPresent([String].self, forKey: .notation) ?? []
        ratings = try values.decodeIfPresent([MoveRating?].self, forKey: .ratings)
        practiceSeconds = try values.decodeIfPresent(TimeInterval.self, forKey: .practiceSeconds)
        result = try values.decodeIfPresent(String.self, forKey: .result) ?? "*"
        reason = try values.decodeIfPresent(String.self, forKey: .reason) ?? ""
        branches = try values.decodeIfPresent([GameBranch].self, forKey: .branches) ?? []
        selectedBranchID = try values.decodeIfPresent(UUID.self, forKey: .selectedBranchID)
        configuration = try values.decodeIfPresent(GameSettings.self, forKey: .configuration)
        // Old libraries used the manual-play mode to identify puzzles.
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        isPuzzle = try values.decodeIfPresent(Bool.self, forKey: .isPuzzle)
            ?? (legacy.decodeIfPresent(String.self, forKey: .mode) == "board")
    }

    var lastPlayerMoveIndex: Int? {
        let startsWhite = ChessPosition.whiteToMove(in: baseFEN)
        return moves.indices.last { (startsWhite == $0.isMultiple(of: 2)) == playerWhite }
    }

    func playerMoved(at ply: Int) -> Bool {
        guard ply > 0, ply <= moves.count else { return false }
        let startsWhite = ChessPosition.whiteToMove(in: baseFEN)
        return (startsWhite == (ply - 1).isMultiple(of: 2)) == playerWhite
    }

    var branchID: UUID { selectedBranchID ?? id }
    var branchCount: Int { max(1, branches.count) }
    var branchName: String { name(of: branchID) }

    func name(of branchID: UUID) -> String {
        guard let index = branches.firstIndex(where: { $0.id == branchID }), index > 0 else { return "Main line" }
        return "Branch \(index)"
    }

    func depth(of branchID: UUID) -> Int {
        var depth = 0
        var current = branches.first { $0.id == branchID }
        var visited = Set<UUID>()
        while let branch = current, let parent = branch.parentID, visited.insert(branch.id).inserted {
            depth += 1
            current = branches.first { $0.id == parent }
        }
        return depth
    }

    mutating func syncSelectedBranch() {
        guard let index = branches.firstIndex(where: { $0.id == branchID }) else { return }
        let old = branches[index]
        var updated = GameBranch(record: self, id: old.id, parentID: old.parentID, forkPly: old.forkPly)
        updated.date = old.date
        branches[index] = updated
    }

    mutating func fork(at ply: Int, seconds: TimeInterval) {
        syncSelectedBranch()
        if branches.isEmpty {
            branches = [GameBranch(record: self, id: id, parentID: nil, forkPly: 0)]
        }
        let ply = max(0, min(moves.count, ply))
        var parent = branchID
        // Forking before an existing fork attaches to its ancestor, never rejoins another line.
        while let branch = branches.first(where: { $0.id == parent }),
              let ancestor = branch.parentID, branch.forkPly >= ply {
            parent = ancestor
        }
        moves = Array(moves.prefix(ply))
        notation = Array(notation.prefix(ply))
        ratings = ratings.map { Array($0.prefix(ply)) }
        practiceSeconds = seconds
        result = "*"
        reason = ""
        let newID = UUID()
        branches.append(GameBranch(record: self, id: newID, parentID: parent, forkPly: ply))
        selectedBranchID = newID
    }

    mutating func selectBranch(_ branchID: UUID) {
        syncSelectedBranch()
        guard let branch = branches.first(where: { $0.id == branchID }) else { return }
        selectedBranchID = branchID
        moves = branch.moves
        notation = branch.notation
        ratings = branch.ratings
        practiceSeconds = branch.practiceSeconds
        result = branch.result
        reason = branch.reason
    }

    var branchPoints: [BranchPoint] {
        var choices: [Int: [UUID]] = [:]
        for branch in branches {
            guard let parent = branch.parentID, branch.forkPly <= moves.count,
                  Array(branch.moves.prefix(branch.forkPly)) == Array(moves.prefix(branch.forkPly)) else { continue }
            var options = choices[branch.forkPly] ?? []
            for option in [parent, branch.id] where !options.contains(option) { options.append(option) }
            choices[branch.forkPly] = options
        }
        return choices.keys.sorted().map { ply in
            let options = choices[ply] ?? []
            var selected = branchID
            var visited = Set<UUID>()
            while !options.contains(selected), visited.insert(selected).inserted,
                  let parent = branches.first(where: { $0.id == selected })?.parentID { selected = parent }
            return BranchPoint(ply: ply, options: options, selectedIndex: options.firstIndex(of: selected) ?? 0)
        }
    }
}

struct LocalLibrary: Codable {
    var settings = PracticeSettings()
    var games: [SavedGame] = []
    var activeID: UUID?
}

@MainActor
final class GameViewModel: ObservableObject {
    nonisolated static let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    @Published var settings = PracticeSettings() { didSet { if loaded { persist() } } }
    @Published private(set) var games: [SavedGame] = []
    @Published private(set) var active: SavedGame?
    @Published private(set) var snapshot: PositionSnapshot?
    @Published private(set) var board: [BoardPiece?] = Array(repeating: nil, count: 64)
    @Published private(set) var ready = false
    @Published private(set) var busy = false
    @Published private(set) var isThinking = false
    @Published private(set) var isHinting = false
    @Published private(set) var isRating = false
    @Published private(set) var reviewGame: SavedGame?
    @Published private(set) var reviewPly = 0
    @Published private(set) var selectedHistoricalPly: Int?
    @Published private(set) var hint: LegalMove?
    @Published var selectedSquare: Int?
    @Published var promotions: [LegalMove] = []
    @Published private(set) var pendingPromotion: LegalMove?
    @Published var errorMessage: String?
    @Published var flipped = false
    @Published private(set) var timerStartedAt: Date?

    private let now: () -> Date
    private var practiceVisible = false
    private var engine: ArasanEngine?
    private var generation = 0
    private var loaded = false
    private var suspended = false
    private var saveURL: URL?
    var record: SavedGame? { reviewGame ?? active }
    var gameSettings: GameSettings { record?.configuration ?? GameSettings(defaults: settings) }
    var moves: [String] { snapshot?.notation ?? [] }
    var reviewing: Bool { reviewGame != nil }
    var gameOver: Bool { !reviewing && active?.result != "*" && active != nil }
    var whiteToMove: Bool { snapshot?.whiteToMove ?? true }
    var userTurn: Bool { whiteToMove == active?.playerWhite }
    var inputAllowed: Bool { ready && !busy && !isThinking && !isHinting && !isRating && !reviewing && !gameOver && userTurn }
    var whiteAtBottom: Bool { (record?.defaultWhiteAtBottom ?? settings.playWhite) != flipped }
    var cursorPly: Int { reviewing ? reviewPly : (active?.moves.count ?? 0) }
    var timelineNotation: [String] { record?.notation ?? [] }
    var canContinue: Bool { ready && !busy && reviewing && snapshot?.result == "*" }
    var canRedoSelectedMove: Bool {
        ready && !busy && reviewing && selectedHistoricalPly == reviewPly &&
            record?.playerMoved(at: reviewPly) == true
    }
    func capturedPieces(byWhite: Bool) -> [BoardPiece] {
        (snapshot?.captured ?? []).enumerated().compactMap { index, symbol in
            guard let kind = symbol.first, kind.isUppercase != byWhite else { return nil }
            return BoardPiece(id: index, kind: kind, isWhite: kind.isUppercase)
        }
    }
    var status: String {
        if !ready { return "Preparing board…" }
        if busy { return "Loading position…" }
        if reviewing { return "" }
        if isRating { return "Rating move…" }
        if gameOver { return (active?.reason ?? "Game over") + " · " + (active?.result ?? "") }
        if isHinting { return "Finding a hint…" }
        if isThinking { return "Bot is thinking…" }
        let side = whiteToMove ? "White" : "Black"
        return (snapshot?.inCheck == true ? "Check · " : "") + side + " to move"
    }
    var lastMoveSquares: Set<Int> {
        let line = reviewing ? Array((reviewGame?.moves ?? []).prefix(reviewPly)) : (active?.moves ?? [])
        guard let move = line.last else { return [] }
        return [squareIndex(String(move.prefix(2))), squareIndex(String(move.dropFirst(2).prefix(2)))]
    }
    var lastMoveUCI: String? {
        let line = reviewing ? Array((reviewGame?.moves ?? []).prefix(reviewPly)) : (active?.moves ?? [])
        return line.last
    }
    var legalTargets: Set<Int> {
        guard let selectedSquare, settings.showLegalMoves else { return [] }
        return Set((snapshot?.legal ?? []).filter { $0.from == selectedSquare }.map(\.to))
    }
    var canUndo: Bool {
        guard let active else { return false }
        return ready && !busy && !reviewing && active.lastPlayerMoveIndex != nil
    }

    static func libraryURL(in applicationSupport: URL) throws -> URL {
        let directory = applicationSupport.appendingPathComponent("ForkChess", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var localDirectory = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try localDirectory.setResourceValues(values)
        let library = directory.appendingPathComponent("library.json")
        let legacy = applicationSupport.appendingPathComponent("QuietChess", isDirectory: true)
            .appendingPathComponent("library.json")
        // Copy within this sandbox once, preserving the original and any newer library.
        if !FileManager.default.fileExists(atPath: library.path),
           FileManager.default.fileExists(atPath: legacy.path) {
            try Data(contentsOf: legacy).write(to: library, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        return library
    }

    init(storageURL: URL? = nil, now: @escaping () -> Date = Date.init) {
        self.now = now
        do {
            if let storageURL { saveURL = storageURL }
            else {
                let applicationSupport = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                saveURL = try Self.libraryURL(in: applicationSupport)
            }
            if let saveURL, FileManager.default.fileExists(atPath: saveURL.path) {
                let library = try JSONDecoder().decode(LocalLibrary.self, from: Data(contentsOf: saveURL))
                settings = library.settings
                // Snapshot legacy defaults once, so later global changes cannot alter old games.
                games = library.games.map { record in
                    var record = record
                    if record.configuration == nil { record.configuration = GameSettings(defaults: library.settings) }
                    return record
                }
                active = games.first { $0.id == library.activeID }
            }
        } catch { errorMessage = "Could not read saved games: " + error.localizedDescription }
        loaded = true
        Task {
            let resources = Bundle.main.resourcePath ?? ""
            engine = await Task.detached(priority: .userInitiated) { ArasanEngine(resources: resources) }.value
            await refresh()
            ready = snapshot != nil
        }
    }

    func squareLabel(_ index: Int) -> String { String(UnicodeScalar(97 + index % 8)!) + String(index / 8 + 1) }

    func newGame() {
        pauseTimer()
        invalidate()
        reviewGame = nil
        flipped = false
        active = SavedGame(playerWhite: settings.playWhite)
        active?.configuration = GameSettings(defaults: settings)
        active?.practiceSeconds = TimeInterval(settings.practiceMinutes * 60)
        startTimer()
        persist()
        Task { await refresh(); await replyIfNeeded() }
    }

    func resume() {
        invalidate()
        reviewGame = nil
        startTimer()
        Task { await refresh(); await replyIfNeeded() }
    }

    /// Saves a hand-built position as a puzzle and opens it against the bot.
    /// The engine checks the position, so an illegal setup is rejected before anything is stored.
    @discardableResult
    func addPuzzle(fen: String, playerWhite: Bool) async throws -> SavedGame {
        guard let engine else { throw PuzzleError.engineUnavailable }
        // Check the setup before the engine sees it: Arasan asserts instead of reporting an
        // error for positions it considers impossible.
        if let issue = ChessPosition.issue(in: ChessPosition.squares(from: fen), whiteToMove: ChessPosition.whiteToMove(in: fen)) {
            throw PuzzleError.invalidPosition(issue)
        }
        _ = try await engine.snapshot(fen: fen, moves: [])
        pauseTimer()
        invalidate()
        reviewGame = nil
        flipped = false
        var puzzle = SavedGame(playerWhite: playerWhite, isPuzzle: true)
        puzzle.baseFEN = fen
        puzzle.configuration = GameSettings(defaults: settings)
        puzzle.practiceSeconds = TimeInterval(settings.practiceMinutes * 60)
        active = puzzle
        startTimer()
        persist()
        await refresh()
        await replyIfNeeded()
        if let active, active.id == puzzle.id { return active }
        return puzzle
    }

    /// Opens a saved puzzle for play, keeping any moves it already has.
    func openPuzzle(_ record: SavedGame) {
        pauseTimer()
        invalidate()
        reviewGame = nil
        flipped = false
        var puzzle = games.first { $0.id == record.id && !$0.branches.isEmpty } ?? record
        prepareGameSettings(for: &puzzle)
        if puzzle.practiceSeconds == nil {
            puzzle.practiceSeconds = TimeInterval((puzzle.configuration?.practiceMinutes ?? 10) * 60)
        }
        active = puzzle
        startTimer()
        persist()
        Task { await refresh(); await replyIfNeeded() }
    }

    func handleTap(_ index: Int) {
        guard inputAllowed else { return }
        hint = nil
        if selectedSquare == index { selectedSquare = nil; return }
        if let selectedSquare {
            let candidates = (snapshot?.legal ?? []).filter { $0.from == selectedSquare && $0.to == index }
            if candidates.count > 1 { promotions = candidates; return }
            if let move = candidates.first { play(move); return }
        }
        if board[index]?.isWhite == whiteToMove { selectedSquare = index }
        else { selectedSquare = nil }
    }

    func play(_ move: LegalMove) {
        guard inputAllowed, snapshot?.legal.contains(move) == true,
              let active, let engine else { return }
        // Closing the picker must not undo the pawn preview while the serial
        // engine is still accepting the selected promotion.
        pendingPromotion = move.promotion == nil ? nil : move
        promotions = []
        selectedSquare = nil
        hint = nil
        let token = generation
        busy = true
        Task {
            do {
                let position = try await engine.snapshot(fen: active.baseFEN, moves: active.moves + [move.uci])
                guard token == generation else { return }
                self.active?.moves.append(move.uci)
                accept(position)
                busy = false
                await rateMove(in: active, candidate: move.uci, token: token)
                guard token == generation else { return }
                await replyIfNeeded()
            } catch { fail(error, token: token) }
        }
    }

    func requestHint() {
        guard inputAllowed, let active, let engine else { return }
        selectedSquare = nil
        hint = nil
        isHinting = true
        let token = generation
        Task {
            do {
                let move = try await engine.search(fen: active.baseFEN, moves: active.moves, skill: 20, milliseconds: 1200)
                guard token == generation else { return }
                hint = snapshot?.legal.first { $0.uci == move }
                isHinting = false
            } catch { fail(error, token: token) }
        }
    }

    func undo() {
        guard canUndo, var active, let playerMove = active.lastPlayerMoveIndex else { return }
        pauseTimer()
        invalidate()
        active.practiceSeconds = self.active?.practiceSeconds
        active.fork(at: playerMove, seconds: active.practiceSeconds ?? 600)
        self.active = active
        persist()
        startTimer()
        Task { await refresh() }
    }

    func resign() {
        guard active != nil, !gameOver, !reviewing else { return }
        pauseTimer()
        invalidate()
        active?.result = active?.playerWhite == true ? "0-1" : "1-0"
        active?.reason = "Resigned"
        persist()
    }

    func pause() {
        pauseTimer()
        invalidate()
        persist()
    }

    func setSuspended(_ value: Bool, gameVisible: Bool) {
        suspended = value
        if value { pause() }
        else if gameVisible && !reviewing {
            startTimer()
            Task { await replyIfNeeded() }
        }
    }

    func review(_ game: SavedGame) {
        pauseTimer()
        invalidate()
        var record = games.first { $0.id == game.id && !$0.branches.isEmpty } ?? game
        prepareGameSettings(for: &record)
        record.syncSelectedBranch()
        reviewGame = record
        reviewPly = record.moves.count
        flipped = false
        busy = true
        Task { await refresh() }
    }

    func seek(_ ply: Int) {
        guard ready, let record else { return }
        pauseTimer()
        persist()
        invalidate()
        var line = record
        line.syncSelectedBranch()
        reviewGame = line
        reviewPly = max(0, min(line.moves.count, ply))
        selectedHistoricalPly = reviewPly > 0 ? reviewPly : nil
        busy = true
        Task { await refresh() }
    }

    func redoSelectedMove() {
        guard canRedoSelectedMove, var next = reviewGame else { return }
        let positionBeforeMove = reviewPly - 1
        invalidate()
        next.fork(at: positionBeforeMove, seconds: TimeInterval(gameSettings.practiceMinutes * 60))
        active = next
        reviewGame = nil
        startTimer()
        persist()
        busy = true
        Task { await refresh(); await replyIfNeeded() }
    }

    func practiceFromHere() {
        guard canContinue, var next = reviewGame else { return }
        invalidate()
        if reviewPly < next.moves.count || next.result != "*" {
            next.fork(at: reviewPly, seconds: TimeInterval(gameSettings.practiceMinutes * 60))
        }
        active = next
        reviewGame = nil
        startTimer()
        persist()
        busy = true
        Task { await refresh(); await replyIfNeeded() }
    }

    func returnToLatest() {
        guard !busy, let reviewGame else { return }
        pauseTimer()
        active = reviewGame
        persist()
        resume()
    }

    func selectBranch(_ id: UUID, at ply: Int? = nil) {
        guard ready, var line = record, line.branches.contains(where: { $0.id == id }) else { return }
        pauseTimer()
        persist()
        invalidate()
        let cursor = ply ?? cursorPly
        line.selectBranch(id)
        reviewGame = line
        reviewPly = max(0, min(line.moves.count, cursor))
        busy = true
        Task { await refresh() }
    }

    func switchBranch(direction: Int, at ply: Int? = nil) {
        guard let line = record else { return }
        let cursor = ply ?? cursorPly
        guard let point = line.branchPoints.last(where: { $0.ply <= cursor }) else { return }
        let next = point.selectedIndex + direction
        guard point.options.indices.contains(next) else { return }
        selectBranch(point.options[next], at: cursorPly)
    }

    func deleteGame(_ id: UUID) {
        if active?.id == id { pauseTimer(); invalidate(); active = nil }
        if reviewGame?.id == id { reviewGame = nil }
        games.removeAll { $0.id == id }
        persist()
    }

    private func prepareGameSettings(for record: inout SavedGame) {
        record.configuration = games.first { $0.id == record.id }?.configuration
            ?? record.configuration ?? GameSettings(defaults: settings)
    }

    func updateGameSettings(_ configuration: GameSettings) {
        guard var line = record, configuration != gameSettings else { return }
        let resetTimer = configuration.practiceMinutes != gameSettings.practiceMinutes
        if resetTimer && !reviewing {
            pauseTimer()
            line = active ?? line
        }
        line.configuration = configuration
        if resetTimer { line.practiceSeconds = TimeInterval(configuration.practiceMinutes * 60) }
        line.syncSelectedBranch()
        if reviewing { reviewGame = line }
        if active?.id == line.id { active = line }
        if let index = games.firstIndex(where: { $0.id == line.id }) { games[index] = line }
        else { games.insert(line, at: 0) }
        persist()
        if !reviewing { startTimer() }
    }

    func practiceTimeRemaining(at date: Date? = nil) -> TimeInterval {
        let remaining = active?.practiceSeconds ?? 600
        let elapsed = timerStartedAt.map { max(0, (date ?? now()).timeIntervalSince($0)) } ?? 0
        return max(0, remaining - elapsed)
    }

    func setPracticeVisible(_ visible: Bool) {
        practiceVisible = visible
        if visible { startTimer() }
        else { pauseTimer(); persist() }
    }

    private func startTimer() {
        guard practiceVisible, !suspended, !reviewing, !gameOver,
              active != nil, timerStartedAt == nil, practiceTimeRemaining() > 0 else { return }
        timerStartedAt = now()
    }

    private func pauseTimer() {
        guard timerStartedAt != nil else { return }
        active?.practiceSeconds = practiceTimeRemaining()
        timerStartedAt = nil
    }

    func pgn(for record: SavedGame) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy.MM.dd"
        let date = formatter.string(from: record.date)
        let white = record.playerWhite ? "Player" : "Bot"
        let black = record.playerWhite ? "Bot" : "Player"
        var output = "[Event \"ForkChess practice\"]\n[Date \"\(date)\"]\n[White \"\(white)\"]\n[Black \"\(black)\"]\n[Result \"\(record.result)\"]\n"
        if record.baseFEN != Self.startFEN { output += "[SetUp \"1\"]\n[FEN \"\(record.baseFEN)\"]\n" }
        output += "\n"
        for (i, move) in record.notation.enumerated() {
            if i.isMultiple(of: 2) { output += "\(i / 2 + 1). " }
            output += move + " "
        }
        return output + record.result
    }

    private func invalidate() {
        generation += 1
        busy = false
        isThinking = false
        isHinting = false
        isRating = false
        selectedSquare = nil
        promotions = []
        pendingPromotion = nil
        hint = nil
        selectedHistoricalPly = nil
    }

    private func refresh() async {
        guard let engine else { return }
        let token = generation
        busy = true
        let record = self.record
        let moves = reviewing ? Array((record?.moves ?? []).prefix(reviewPly)) : (record?.moves ?? [])
        do {
            let position = try await engine.snapshot(fen: record?.baseFEN ?? Self.startFEN, moves: moves)
            guard token == generation else { return }
            accept(position)
            busy = false
        } catch { fail(error, token: token) }
    }

    private func replyIfNeeded() async {
        guard ready, !suspended, !reviewing, !busy, !isThinking, !isRating, !gameOver,
              let active, !userTurn, let engine else { return }
        let token = generation
        isThinking = true
        do {
            let configuration = active.configuration ?? GameSettings(defaults: settings)
            let move = try await engine.search(fen: active.baseFEN, moves: active.moves, skill: configuration.skill, milliseconds: Int(configuration.thinkSeconds * 1000))
            guard token == generation else { return }
            guard snapshot?.legal.contains(where: { $0.uci == move }) == true else {
                throw ChessError.engine("The bot could not find a legal reply. Undo or return home to retry.")
            }
            let position = try await engine.snapshot(fen: active.baseFEN, moves: active.moves + [move])
            guard token == generation else { return }
            self.active?.moves.append(move)
            accept(position)
            isThinking = false
            await rateMove(in: active, candidate: move, token: token)
        } catch { fail(error, token: token) }
    }

    private func rateMove(in before: SavedGame, candidate: String, token: Int) async {
        guard before.configuration?.rateMoves == true, let engine, token == generation else { return }
        isRating = true
        do {
            let rating = try await engine.rate(fen: before.baseFEN, moves: before.moves, candidate: candidate)
            guard token == generation, active?.id == before.id else { return }
            var ratings = active?.ratings ?? []
            while ratings.count < before.moves.count + 1 { ratings.append(nil) }
            ratings[before.moves.count] = rating
            active?.ratings = ratings
            persist()
        } catch {
            guard token == generation else { return }
            errorMessage = "This move could not be rated. You can continue playing."
        }
        isRating = false
    }

    private func accept(_ position: PositionSnapshot) {
        snapshot = position
        board = ChessPosition.squares(from: position.fen).enumerated().map { index, kind in
            guard kind != ChessPosition.empty else { return nil }
            return BoardPiece(id: position.pieceIDs[index], kind: kind, isWhite: kind.isUppercase)
        }
        pendingPromotion = nil
        if !reviewing {
            active?.notation = position.notation
            if active?.reason != "Resigned" && active?.reason != "Practice complete" {
                active?.result = position.result
                active?.reason = position.reason
            }
            if gameOver { pauseTimer() }
            persist()
        }
    }

    private func fail(_ error: Error, token: Int) {
        guard token == generation else { return }
        pendingPromotion = nil
        busy = false
        isThinking = false
        isHinting = false
        isRating = false
        errorMessage = error.localizedDescription
    }

    private func persist() {
        guard loaded, let saveURL else { return }
        if active?.branches.isEmpty == false { active?.syncSelectedBranch() }
        if var active {
            // Save the current remaining time without resetting the running
            // anchor. No per-second disk writes or accumulated tick drift.
            active.practiceSeconds = practiceTimeRemaining()
            active.syncSelectedBranch()
            if let index = games.firstIndex(where: { $0.id == active.id }) { games[index] = active }
            else { games.insert(active, at: 0) }
        }
        do {
            let library = LocalLibrary(settings: settings, games: games, activeID: active?.id)
            try JSONEncoder().encode(library).write(to: saveURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch { errorMessage = "Could not save on this device: " + error.localizedDescription }
    }
}
