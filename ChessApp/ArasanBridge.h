#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// All handle operations run on one serial executor. Search is bounded and synchronous.
// MIT-licensed Arasan engine backend (replaces the former GPL Stockfish backend).
void *ab_create(const char *resourceDirectory);
void ab_destroy(void *handle);
const char *ab_snapshot(void *handle, const char *fen, const char *moves);
const char *ab_search(void *handle, const char *fen, const char *moves, int skill, int milliseconds);
const char *ab_evaluate(void *handle, const char *fen, const char *moves, const char *candidate);
const char *ab_last_error(void *handle);
uint64_t ab_perft(void *handle, const char *fen, int depth);
#ifdef __cplusplus
}
#endif
