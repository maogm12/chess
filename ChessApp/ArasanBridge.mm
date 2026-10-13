#import "ArasanBridge.h"
#import <Foundation/Foundation.h>
#include <algorithm>
#include <array>
#include <condition_variable>
#include <cctype>
#include <deque>
#include <filesystem>
#include <memory>
#include <mutex>
#include <pthread.h>
#include <sstream>
#include <string>
#include <vector>
#include "Vendor/Arasan/src/attacks.h"
#include "Vendor/Arasan/src/bitutil.h"
#include "Vendor/Arasan/src/board.h"
#include "Vendor/Arasan/src/boardio.h"
#include "Vendor/Arasan/src/chess.h"
#include "Vendor/Arasan/src/constant.h"
#include "Vendor/Arasan/src/globals.h"
#include "Vendor/Arasan/src/legal.h"
#include "Vendor/Arasan/src/movegen.h"
#include "Vendor/Arasan/src/notation.h"
#include "Vendor/Arasan/src/scoring.h"
#include "Vendor/Arasan/src/search.h"

namespace {

constexpr char kNetworkFile[] = "arasanv8-20260906.nnue";
constexpr size_t kHashBytes = 32 * 1024 * 1024;
constexpr size_t kWorkerStackBytes = 8 * 1024 * 1024;
// Arasan mate scores live just under Constants::MATE; map them to the
// App's historical +/-100000 convention (centipawn-ish scale).
constexpr int kMateScore = 100000;

std::vector<std::string> aeSplit(const char *input) {
    std::istringstream stream(input ? input : "");
    std::vector<std::string> result;
    for (std::string s; stream >> s;) result.push_back(s);
    return result;
}
NSString *aeStr(const std::string& s) { return [NSString stringWithUTF8String:s.c_str()]; }

char aePieceLetter(Piece p) {
    PieceType t = TypeOfPiece(p);
    if (t < Pawn || t > King) return '?';
    char c = "?PNBRQK"[t];
    if (PieceColor(p) == Black) c = (char)tolower(c);
    return c;
}

std::string aeUCI(const Board& board, Move m) {
    std::string out;
    Notation::image(board, m, Notation::OutputFormat::UCI, out);
    return out;
}
std::string aeSAN(const Board& board, Move m) {
    std::string out;
    Notation::image(board, m, Notation::OutputFormat::SAN, out);
    return out;
}

// Canonical legal moves for the side to move.
std::vector<Move> aeLegalMoves(const Board& board) {
    std::vector<Move> moves;
    RootMoveGenerator gen(board);
    int order = 0;
    Move m = NullMove;
    while ((m = gen.nextMove(order)) != NullMove) moves.push_back(m);
    return moves;
}

int aeToCentipawns(score_t score) {
    const score_t mag = score >= 0 ? score : -score;
    if (mag >= Constants::MATE - 1024) return score > 0 ? kMateScore : -kMateScore;
    return (int)((score * 100) / Scoring::PAWN_VALUE);
}

uint64_t aePerft(Board& board, int depth) {
    if (depth == 0) return 1;
    uint64_t nodes = 0;
    RootMoveGenerator gen(board);
    int order = 0;
    Move m = NullMove;
    BoardState state = board.state;
    while ((m = gen.nextMove(order)) != NullMove) {
        if (depth > 1) {
            board.doMove(m);
            nodes += aePerft(board, depth - 1);
            board.undoMove(m, state);
        } else {
            nodes += 1;
        }
    }
    return nodes;
}

// The search itself runs on a dedicated pthread with an 8MB stack;
// Arasan's engine threads use multi-MB stacks and Swift cooperative
// threads are too small to host ply0_search safely.
struct AeSearchRequest {
    Board board;
    SearchType type = FixedTime;
    int timeMs = 0;
    int plyLimit = Constants::MaxPly;
    int strength = 100;
    MoveSet include;
};

struct AeSearchResult {
    Move best = NullMove;
    score_t score = 0;
    bool hasScore = false;
};

class AeSearchWorker {
public:
    explicit AeSearchWorker(SearchController *controller) : controller_(controller), stop_(false), pending_(false), done_(false) {
        pthread_attr_t attr;
        pthread_attr_init(&attr);
        pthread_attr_setstacksize(&attr, kWorkerStackBytes);
        pthread_create(&thread_, &attr, &AeSearchWorker::entry, this);
        pthread_attr_destroy(&attr);
    }
    ~AeSearchWorker() {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            stop_ = true;
            cond_.notify_one();
        }
        pthread_join(thread_, nullptr);
    }
    AeSearchResult run(AeSearchRequest req) {
        std::unique_lock<std::mutex> lock(mutex_);
        request_ = std::move(req);
        pending_ = true;
        done_ = false;
        cond_.notify_one();
        cond_.wait(lock, [&] { return done_; });
        return result_;
    }
private:
    static void *entry(void *p) {
        auto self = static_cast<AeSearchWorker *>(p);
        self->loop();
        return nullptr;
    }
    void loop() {
        std::unique_lock<std::mutex> lock(mutex_);
        for (;;) {
            cond_.wait(lock, [&] { return pending_ || stop_; });
            if (stop_) return;
            AeSearchRequest req = std::move(request_);
            pending_ = false;
            lock.unlock();
            AeSearchResult res;
            @autoreleasepool {
                globals::options.search.strength = std::clamp(req.strength, 0, 100);
                controller_->updateSearchOptions();
                Statistics stats;
                MoveSet exclude;
                Move best = controller_->findBestMove(req.board, req.type, req.timeMs, 0,
                                                      req.plyLimit, false, false, stats,
                                                      TalkLevel::Silent, exclude, req.include);
                res.best = best;
                res.score = stats.value;
                res.hasScore = !IsNull(best);
            }
            lock.lock();
            result_ = res;
            done_ = true;
            cond_.notify_one();
        }
    }
    SearchController *controller_;
    pthread_t thread_;
    std::mutex mutex_;
    std::condition_variable cond_;
    bool stop_, pending_, done_;
    AeSearchRequest request_;
    AeSearchResult result_;
};

struct ChessHandle {
    std::unique_ptr<SearchController> searcher;
    std::unique_ptr<AeSearchWorker> worker;
    std::string output, error;
};

std::once_flag aeInitialized;
std::string aeLoadedNetwork;
std::mutex aeInitMutex;

bool aeEnsureInitialized(const std::string& networkPath, std::string& error) {
    std::lock_guard<std::mutex> lock(aeInitMutex);
    if (!aeLoadedNetwork.empty() && aeLoadedNetwork == networkPath) return true;
    std::call_once(aeInitialized, [] {
        BitUtils::init();
        Board::init();
        Attacks::init();
        Search::init();
        globals::options.search.ncpus = 1;
        globals::options.search.multipv = 1;
        globals::options.search.strength = 100;
        globals::options.book.book_enabled = false;
        globals::options.book.eco_enabled = false;
    });
    globals::options.search.nnueFile = networkPath;
    if (!globals::loadNetwork(networkPath, false)) {
        error = "The chess engine could not be loaded. Reinstall the app.";
        return false;
    }
    aeLoadedNetwork = networkPath;
    return true;
}

// Arasan's Board does not store the FEN halfmove/fullmove counters, so the
// bridge carries them: the halfmove clock seeds state.moveCount (replay keeps
// it exact), the fullmove number is threaded through for FEN output.
void aeParseFENClock(const char *fen, int& half, int& full, ColorType& side) {
    half = 0;
    full = 1;
    side = White;
    if (!fen) return;
    std::istringstream in(fen);
    std::string piece, stm, castle, ep, h, f;
    if (!(in >> piece)) return;
    if (in >> stm) side = (stm == "b" || stm == "B") ? Black : White;
    if (!(in >> castle)) return;
    if (!(in >> ep)) return;
    if (in >> h) {
        try { half = std::max(0, std::stoi(h)); } catch (...) {}
    }
    if (in >> f) {
        try { full = std::max(1, std::stoi(f)); } catch (...) {}
    }
}

bool aeBuildBoard(const char *fen, const char *moves, Board& board, std::string& error,
                  std::vector<Move>* replayed = nullptr) {
    if (!BoardIO::readFEN(board, fen ? fen : "")) {
        error = "Invalid position.";
        return false;
    }
    int half = 0, full = 1;
    ColorType side = White;
    aeParseFENClock(fen, half, full, side);
    board.state.moveCount = half;
    board.state.movesFromNull = 0;
    for (const auto& uci : aeSplit(moves)) {
        Move parsed = Notation::value(board, board.sideToMove(),
                                      Notation::InputFormat::UCI, uci, false);
        Move match = NullMove;
        if (!IsNull(parsed)) {
            for (Move legal : aeLegalMoves(board)) {
                if (StartSquare(legal) == StartSquare(parsed) &&
                    DestSquare(legal) == DestSquare(parsed) &&
                    PromoteTo(legal) == PromoteTo(parsed)) {
                    match = legal;
                    break;
                }
            }
        }
        if (IsNull(match)) {
            error = "Illegal move: " + uci;
            return false;
        }
        board.doMove(match);
        if (replayed) replayed->push_back(match);
    }
    return true;
}

} // namespace

extern "C" void *ab_create(const char *resources) {
    try {
        const auto directory = std::filesystem::path(resources ? resources : ".");
        const auto network = directory / kNetworkFile;
        if (!std::filesystem::exists(network)) return nullptr;
        std::string error;
        if (!aeEnsureInitialized(network.string(), error)) return nullptr;
        auto h = std::make_unique<ChessHandle>();
        h->searcher = std::make_unique<SearchController>();
        h->searcher->resizeHash(kHashBytes);
        h->worker = std::make_unique<AeSearchWorker>(h->searcher.get());
        return h.release();
    } catch (...) { return nullptr; }
}
extern "C" void ab_destroy(void *handle) {
    auto h = static_cast<ChessHandle *>(handle);
    delete h;
}
extern "C" const char *ab_last_error(void *handle) {
    auto h = static_cast<ChessHandle *>(handle);
    return h ? h->error.c_str() : "The chess engine could not be loaded.";
}
extern "C" const char *ab_snapshot(void *handle, const char *fen, const char *moves) {
    auto h = static_cast<ChessHandle *>(handle);
    if (!h) return nullptr;
    @autoreleasepool {
        Board board;
        if (!aeBuildBoard(fen, moves, board, h->error)) return nullptr;
        // Identity is the piece's starting square, retained through promotion.
        // Replaying the same line reconstructs identities and captures on undo.
        Board walk;
        BoardIO::readFEN(walk, fen ? fen : "");
        std::array<int, 64> identities;
        for (int s = 0; s < 64; ++s) identities[s] = IsEmptyPiece(walk[(Square)s]) ? -1 : s;
        NSMutableArray *captured = [NSMutableArray array];
        NSMutableArray *notation = [NSMutableArray array];
        for (const auto& uci : aeSplit(moves)) {
            Move parsed = Notation::value(walk, walk.sideToMove(),
                                          Notation::InputFormat::UCI, uci, false);
            Move match = NullMove;
            for (Move legal : aeLegalMoves(walk)) {
                if (StartSquare(legal) == StartSquare(parsed) &&
                    DestSquare(legal) == DestSquare(parsed) &&
                    PromoteTo(legal) == PromoteTo(parsed)) {
                    match = legal;
                    break;
                }
            }
            if (IsNull(match)) { h->error = "Illegal move: " + uci; return nullptr; }
            [notation addObject:aeStr(aeSAN(walk, match))];
            const ColorType side = walk.sideToMove();
            const Square from = StartSquare(match), to = DestSquare(match);
            const MoveType type = TypeOfMove(match);
            if (type == KCastle || type == QCastle) {
                const bool kingSide = (type == KCastle);
                Square kingTo, rookTo, rookFrom;
                if (side == White) {
                    kingTo = kingSide ? chess::G1 : chess::C1;
                    rookTo = kingSide ? chess::F1 : chess::D1;
                    rookFrom = kingSide ? chess::H1 : chess::A1;
                } else {
                    kingTo = kingSide ? chess::G8 : chess::C8;
                    rookTo = kingSide ? chess::F8 : chess::D8;
                    rookFrom = kingSide ? chess::H8 : chess::A8;
                }
                const int kingID = identities[from], rookID = identities[rookFrom];
                identities[from] = identities[rookFrom] = -1;
                identities[kingTo] = kingID;
                identities[rookTo] = rookID;
            } else {
                if (Capture(match) != Empty) {
                    const Square capturedSquare = (type == EnPassant)
                        ? (Square)(to - 8 * Direction[side]) : to;
                    const Piece piece = walk[capturedSquare];
                    [captured addObject:aeStr(std::string(1, aePieceLetter(piece)))];
                    identities[capturedSquare] = -1;
                }
                identities[to] = identities[from];
                identities[from] = -1;
            }
            walk.doMove(match);
        }
        NSMutableArray *legal = [NSMutableArray array];
        for (Move m : aeLegalMoves(board)) {
            [legal addObject:@{@"uci": aeStr(aeUCI(board, m)), @"san": aeStr(aeSAN(board, m))}];
        }
        std::string result = "*", reason;
        if (legal.count == 0) {
            if (board.checkStatus() == InCheck) {
                result = board.sideToMove() == White ? "0-1" : "1-0";
                reason = "Checkmate";
            } else { result = "1/2-1/2"; reason = "Stalemate"; }
        } else if (board.materialDraw()) { result = "1/2-1/2"; reason = "Insufficient material"; }
        else if (board.fiftyMoveDraw()) { result = "1/2-1/2"; reason = "50-move rule"; }
        else if (board.repetitionDraw()) { result = "1/2-1/2"; reason = "Threefold repetition"; }
        std::string fenBase;
        BoardIO::writeFEN(board, fenBase, false);
        int half = 0, full = 1;
        ColorType startSide = White;
        aeParseFENClock(fen, half, full, startSide);
        const int plies = (int)aeSplit(moves).size();
        half = board.state.moveCount;
        full += (plies + (startSide == Black ? 1 : 0)) / 2;
        const std::string fenOut = fenBase + " " + std::to_string(half) + " " + std::to_string(full);
        NSMutableArray *pieceIDs = [NSMutableArray arrayWithCapacity:64];
        for (int identity : identities) [pieceIDs addObject:@(identity)];
        NSDictionary *snapshot = @{
            @"fen": aeStr(fenOut), @"notation": notation, @"legal": legal,
            @"inCheck": @(board.checkStatus() == InCheck),
            @"result": aeStr(result), @"reason": aeStr(reason),
            @"pieceIDs": pieceIDs, @"captured": captured
        };
        NSData *data = [NSJSONSerialization dataWithJSONObject:snapshot options:0 error:nil];
        h->output.assign(static_cast<const char *>(data.bytes), data.length);
        h->error.clear();
        return h->output.c_str();
    }
}
extern "C" const char *ab_search(void *handle, const char *fen, const char *moves, int skill, int milliseconds) {
    auto h = static_cast<ChessHandle *>(handle);
    if (!h) return nullptr;
    Board board;
    if (!aeBuildBoard(fen, moves, board, h->error)) return nullptr;
    AeSearchRequest req;
    req.board = board;
    req.type = FixedTime;
    req.timeMs = std::clamp(milliseconds, 100, 3000);
    req.plyLimit = Constants::MaxPly;
    req.strength = std::clamp(skill, 0, 20) * 5;
    AeSearchResult res = h->worker->run(std::move(req));
    if (!res.hasScore) {
        h->error = "The chess engine could not find a legal move.";
        return nullptr;
    }
    h->output = aeUCI(board, res.best);
    h->error.clear();
    // The returned pointer aliases handle storage, matching the prior contract.
    static thread_local std::string best;
    best = h->output;
    return best.c_str();
}
extern "C" uint64_t ab_perft(void *handle, const char *fen, int depth) {
    auto h = static_cast<ChessHandle *>(handle);
    if (!h) return 0;
    Board board;
    std::string error;
    if (!aeBuildBoard(fen, "", board, error)) return 0;
    (void)h;
    return aePerft(board, depth);
}

// Both searches use the SAME root position, so scores are always from the
// mover's perspective, including Black. A candidate restricts only the root move.
extern "C" const char *ab_evaluate(void *handle, const char *fen, const char *moves, const char *candidate) {
    auto h = static_cast<ChessHandle *>(handle);
    if (!h || !ab_snapshot(handle, fen, moves)) return nullptr;
    Board board;
    if (!aeBuildBoard(fen, moves, board, h->error)) return nullptr;
    AeSearchRequest req;
    req.board = board;
    req.type = FixedTime;
    req.timeMs = 700;
    req.plyLimit = 12;
    req.strength = 100;
    if (candidate && *candidate) {
        Move parsed = Notation::value(board, board.sideToMove(),
                                      Notation::InputFormat::UCI, candidate, false);
        Move match = NullMove;
        if (!IsNull(parsed)) {
            for (Move legal : aeLegalMoves(board)) {
                if (StartSquare(legal) == StartSquare(parsed) &&
                    DestSquare(legal) == DestSquare(parsed) &&
                    PromoteTo(legal) == PromoteTo(parsed)) {
                    match = legal;
                    break;
                }
            }
        }
        if (IsNull(match)) { h->error = std::string("Illegal move: ") + candidate; return nullptr; }
        req.include.insert(match);
    }
    AeSearchResult res = h->worker->run(std::move(req));
    if (!res.hasScore) { h->error = "Could not rate this move."; return nullptr; }
    @autoreleasepool {
        NSData *data = [NSJSONSerialization dataWithJSONObject:@{
            @"score": @(aeToCentipawns(res.score)),
            @"bestMove": aeStr(aeUCI(board, res.best))
        } options:0 error:nil];
        h->output.assign(static_cast<const char *>(data.bytes), data.length);
    }
    h->error.clear();
    return h->output.c_str();
}
