import Foundation

/// FEN helpers shared by gameplay, the puzzle editor, thumbnails, and position validation.
///
/// Positions are held as 64 characters in board order: index 0 is a1 and index 63 is h8, the same
/// order the engine bridge uses. `" "` means an empty square, uppercase pieces are white.
enum ChessPosition {
    static let empty: Character = " "

    static func whiteToMove(in fen: String) -> Bool {
        fen.split(separator: " ").dropFirst().first != "b"
    }

    static func squares(from fen: String) -> [Character] {
        var squares = [Character](repeating: empty, count: 64)
        let placement = fen.split(separator: " ").first ?? ""
        for (row, text) in placement.split(separator: "/").enumerated() where row < 8 {
            var file = 0
            for character in text {
                if let skip = character.wholeNumberValue {
                    file += skip
                    continue
                }
                if file < 8 { squares[(7 - row) * 8 + file] = character }
                file += 1
            }
        }
        return squares
    }

    static func fen(from squares: [Character], whiteToMove: Bool) -> String {
        var rows: [String] = []
        for rank in stride(from: 7, through: 0, by: -1) {
            var row = ""
            var gap = 0
            for file in 0..<8 {
                let square = squares[rank * 8 + file]
                if square == empty { gap += 1; continue }
                if gap > 0 { row += String(gap); gap = 0 }
                row.append(square)
            }
            if gap > 0 { row += String(gap) }
            rows.append(row)
        }
        return rows.joined(separator: "/") + " \(whiteToMove ? "w" : "b") - - 0 1"
    }

    static func piece(_ square: Character) -> (kind: Character, isWhite: Bool)? {
        guard square != empty, square.isLetter else { return nil }
        return (Character(square.lowercased()), square.isUppercase)
    }

    static func count(_ squares: [Character]) -> Int {
        squares.filter { $0 != empty }.count
    }

    static func issue(in squares: [Character], whiteToMove: Bool) -> String? {
        if let issue = setupIssue(in: squares, whiteToMove: whiteToMove) { return issue }
        guard squares.filter({ $0 == "K" }).count == 1, squares.filter({ $0 == "k" }).count == 1 else {
            return "Each side needs exactly one king."
        }
        return nil
    }

    /// Missing kings are allowed while building; all other checks apply to the proposed placement.
    static func canPlace(_ piece: Character, at index: Int, in squares: [Character], whiteToMove: Bool) -> Bool {
        guard squares.count == 64, squares.indices.contains(index), "KQRBNPkqrbnp".contains(piece) else { return false }
        var next = squares
        next[index] = piece
        return setupIssue(in: next, whiteToMove: whiteToMove) == nil
    }

    private static func setupIssue(in squares: [Character], whiteToMove: Bool) -> String? {
        guard squares.count == 64 else { return "A board needs 64 squares." }
        if squares.filter({ $0 == "K" }).count > 1 || squares.filter({ $0 == "k" }).count > 1 {
            return "Each side can have only one king."
        }
        for (white, pawn) in [(true, "P"), (false, "p")] {
            if squares.filter({ $0 == Character(pawn) }).count > 8 {
                return "A side cannot have more than eight pawns."
            }
            let pieces = squares.filter { $0.isUppercase == white && $0.isLetter }.count
            if pieces > 16 { return "A side cannot have more than sixteen pieces." }
        }
        for (index, square) in squares.enumerated() where square == "P" || square == "p" {
            let rank = index / 8 + 1
            if rank == 1 || rank == 8 { return "Pawns cannot stand on the first or last rank." }
        }
        if let white = squares.firstIndex(of: "K"), let black = squares.firstIndex(of: "k"),
           abs(white / 8 - black / 8) <= 1, abs(white % 8 - black % 8) <= 1 {
            return "The two kings cannot stand next to each other."
        }
        // The side that just moved must not be in check, or it would have left its king en prise.
        let defending: Character = whiteToMove ? "k" : "K"
        if let king = squares.firstIndex(of: defending), isAttacked(king, by: whiteToMove, in: squares) {
            return "The side that just moved would be in check, which cannot happen in a game."
        }
        return nil
    }

    /// True when `square` is attacked by any piece of the given color.
    static func isAttacked(_ square: Int, by white: Bool, in squares: [Character]) -> Bool {
        let file = square % 8
        let rank = square / 8
        /// nil means off the board, `empty` means an empty square.
        func at(file: Int, rank: Int) -> Character? {
            guard (0..<8).contains(file), (0..<8).contains(rank) else { return nil }
            return squares[rank * 8 + file]
        }
        // Pawns attack diagonally forward, so a white pawn that attacks `square` sits below it.
        let pawn: Character = white ? "P" : "p"
        let pawnRank = white ? rank - 1 : rank + 1
        if at(file: file - 1, rank: pawnRank) == pawn || at(file: file + 1, rank: pawnRank) == pawn { return true }
        let knight: Character = white ? "N" : "n"
        for (dx, dy) in [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)]
        where at(file: file + dx, rank: rank + dy) == knight { return true }
        let king: Character = white ? "K" : "k"
        for (dx, dy) in [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]
        where at(file: file + dx, rank: rank + dy) == king { return true }
        let rook: Character = white ? "R" : "r"
        let bishop: Character = white ? "B" : "b"
        let queen: Character = white ? "Q" : "q"
        let rays: [(Int, Int, Character)] = [(1, 0, rook), (-1, 0, rook), (0, 1, rook), (0, -1, rook),
                                             (1, 1, bishop), (1, -1, bishop), (-1, 1, bishop), (-1, -1, bishop)]
        for (dx, dy, slider) in rays {
            var step = 1
            while at(file: file + dx * step, rank: rank + dy * step) == empty {
                step += 1
            }
            if let found = at(file: file + dx * step, rank: rank + dy * step),
               found == slider || found == queen { return true }
        }
        return false
    }
}
