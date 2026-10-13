import Foundation

struct LegalMove: Codable, Equatable {
    let uci: String
    let san: String
    var from: Int { squareIndex(String(uci.prefix(2))) }
    var to: Int { squareIndex(String(uci.dropFirst(2).prefix(2))) }
    var promotion: String? { uci.count == 5 ? String(uci.suffix(1)) : nil }
}

func squareIndex(_ square: String) -> Int {
    guard let file = square.first?.asciiValue, let rank = square.last?.wholeNumberValue else { return 0 }
    return (rank - 1) * 8 + Int(file) - 97
}

struct PositionSnapshot: Codable {
    let fen: String
    let notation: [String]
    let legal: [LegalMove]
    let inCheck: Bool
    let result: String
    let reason: String
    let pieceIDs: [Int]
    let captured: [String]
    var whiteToMove: Bool { fen.split(separator: " ").dropFirst().first == "w" }
}

enum ChessError: LocalizedError {
    case engine(String)
    var errorDescription: String? {
        switch self { case .engine(let text): return text }
    }
}

/// Serial actor owns the native handle. Bounded searches run away from the UI.
/// UI request generations prevent a completed old search from changing a new game.
actor ArasanEngine {
    private var handle: UnsafeMutableRawPointer?
    init(resources: String) { handle = resources.withCString { ab_create($0) } }
    deinit { if let handle { ab_destroy(handle) } }

    private func requireHandle() throws -> UnsafeMutableRawPointer {
        guard let handle else { throw ChessError.engine("The chess engine could not be loaded. Reinstall the app.") }
        return handle
    }

    func snapshot(fen: String, moves: [String]) throws -> PositionSnapshot {
        let handle = try requireHandle()
        let text: String? = fen.withCString { fp in
            moves.joined(separator: " ").withCString { mp in
                ab_snapshot(handle, fp, mp).map { String(cString: $0) }
            }
        }
        guard let text, let data = text.data(using: .utf8) else {
            throw ChessError.engine(String(cString: ab_last_error(handle)))
        }
        return try JSONDecoder().decode(PositionSnapshot.self, from: data)
    }

    func search(fen: String, moves: [String], skill: Int, milliseconds: Int) throws -> String {
        let handle = try requireHandle()
        let move: String? = fen.withCString { fp in
            moves.joined(separator: " ").withCString { mp in
                ab_search(handle, fp, mp, Int32(skill), Int32(milliseconds)).map { String(cString: $0) }
            }
        }
        guard let move else { throw ChessError.engine(String(cString: ab_last_error(handle))) }
        return move
    }

    func rate(fen: String, moves: [String], candidate: String) throws -> MoveRating {
        struct Evaluation: Decodable { let score: Int; let bestMove: String }
        let handle = try requireHandle()
        func evaluate(_ candidate: String) throws -> Evaluation {
            let json = fen.withCString { fp in
                moves.joined(separator: " ").withCString { mp in
                    candidate.withCString { cp in ab_evaluate(handle, fp, mp, cp).map { String(cString: $0) } }
                }
            }
            guard let json else { throw ChessError.engine(String(cString: ab_last_error(handle))) }
            return try JSONDecoder().decode(Evaluation.self, from: Data(json.utf8))
        }
        let best = try evaluate("")
        if best.bestMove == candidate { return .good }
        let played = try evaluate(candidate)
        let loss = max(0, best.score - played.score)
        return loss <= 50 ? .good : loss <= 150 ? .ok : .bad
    }
}
