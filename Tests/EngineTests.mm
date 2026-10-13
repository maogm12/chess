#import <Foundation/Foundation.h>
#include <cassert>
#include <iostream>
#include "../ChessApp/ArasanBridge.h"

static const char *start = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";
NSDictionary *snapshot(void *h, const char *fen, const char *moves = "") {
    const char *json = ab_snapshot(h, fen, moves);
    if (!json) { std::cerr << ab_last_error(h) << std::endl; abort(); }
    return [NSJSONSerialization JSONObjectWithData:[[NSString stringWithUTF8String:json] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
}
bool has(NSDictionary *s, NSString *uci) {
    for (NSDictionary *m in s[@"legal"]) if ([m[@"uci"] isEqual:uci]) return true;
    return false;
}
int main(int argc, char **argv) {
    @autoreleasepool {
        void *h = ab_create(argv[1]);
        assert(h);
        auto initial = snapshot(h, start);
        assert([initial[@"legal"] count] == 20);
        assert(!has(initial, @"e2e5"));
        assert(ab_perft(h, start, 3) == 8902);
        auto castle = snapshot(h, "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1");
        assert(has(castle, @"e1g1") && has(castle, @"e1c1"));
        auto castled = snapshot(h, "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1", "e1g1");
        assert([castled[@"notation"][0] isEqual:@"O-O"]);
        assert([castled[@"pieceIDs"][6] intValue] == 4);
        assert([castled[@"pieceIDs"][5] intValue] == 7);
        assert([castle[@"pieceIDs"][4] intValue] == 4);
        assert([castle[@"pieceIDs"][7] intValue] == 7);
        auto ep = snapshot(h, start, "e2e4 a7a6 e4e5 d7d5");
        assert(has(ep, @"e5d6"));
        auto epCapture = snapshot(h, start, "e2e4 a7a6 e4e5 d7d5 e5d6");
        assert([epCapture[@"captured"] isEqual:@[@"p"]]);
        assert([epCapture[@"pieceIDs"][43] intValue] == 12);
        assert([epCapture[@"pieceIDs"][35] intValue] == -1);
        auto promotion = snapshot(h, "7k/P7/8/8/8/8/8/7K w - - 0 1");
        for (NSString *m in @[@"a7a8q", @"a7a8r", @"a7a8b", @"a7a8n"]) assert(has(promotion,m));
        auto promoted = snapshot(h, "7k/P7/8/8/8/8/8/7K w - - 0 1", "a7a8q");
        assert([promoted[@"pieceIDs"][56] intValue] == 48);
        assert([promoted[@"captured"] count] == 0);
        auto mate = snapshot(h, start, "f2f3 e7e5 g2g4 d8h4");
        assert([mate[@"result"] isEqual:@"0-1"]);
        assert([mate[@"notation"][3] isEqual:@"Qh4#"]);
        auto stale = snapshot(h, "7k/5K2/6Q1/8/8/8/8/8 b - - 0 1");
        assert([stale[@"reason"] isEqual:@"Stalemate"]);
        auto material = snapshot(h, "7k/8/8/8/8/8/8/K7 w - - 0 1");
        assert([material[@"reason"] isEqual:@"Insufficient material"]);
        auto repeat = snapshot(h, start, "g1f3 g8f6 f3g1 f6g8 g1f3 g8f6 f3g1 f6g8");
        assert([repeat[@"reason"] isEqual:@"Threefold repetition"]);
        auto fifty = snapshot(h, "7k/8/8/8/8/8/R7/K7 w - - 100 51");
        assert([fifty[@"reason"] isEqual:@"50-move rule"]);
        assert(ab_snapshot(h, start, "e2e5") == nullptr);
        assert([snapshot(h,start)[@"legal"] count] == 20);
        std::string moves;
        for (int ply = 0; ply < 24; ++ply) {
            auto before = snapshot(h,start,moves.c_str());
            if (![before[@"result"] isEqual:@"*"]) break;
            std::string move = ab_search(h,start,moves.c_str(),12,120);
            assert(has(before, [NSString stringWithUTF8String:move.c_str()]));
            moves += (moves.empty() ? "" : " ") + move;
            snapshot(h,start,moves.c_str());
        }
        ab_destroy(h);
        std::cout << "PASS: perft, legality, castling, en passant, promotion, mate, stalemate, draws, 24 engine plies." << std::endl;
    }
}
