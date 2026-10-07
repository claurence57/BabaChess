/*
 * AdaChess-BB : thin C wrapper around Fathom (Syzygy tablebase probing).
 *
 * Exposes a flat, Ada-friendly API over the Fathom inline entry points, so the
 * Ada side only deals with bitboards and integers.
 */
#include <stddef.h>
#include "tbprobe.h"

int baba_tb_init(const char *path) {
    return tb_init(path) ? 1 : 0;
}

void baba_tb_free(void) {
    tb_free();
}

unsigned baba_tb_largest(void) {
    return TB_LARGEST;
}

unsigned baba_tb_wdl(uint64_t white, uint64_t black, uint64_t kings,
                     uint64_t queens, uint64_t rooks, uint64_t bishops,
                     uint64_t knights, uint64_t pawns,
                     unsigned rule50, unsigned castling, unsigned ep, int turn) {
    return tb_probe_wdl(white, black, kings, queens, rooks, bishops,
                        knights, pawns, rule50, castling, ep, turn != 0);
}

/* DTZ root probe (Fathom's tb_probe_root). Returns the packed TB_RESULT, or
 * TB_RESULT_FAILED. The suggested move preserves the WDL value; DTZ tables
 * (and the matching WDL tables) must be loaded. `results` is unused here
 * (NULL): we only need the single best move, not the per-move breakdown.
 * Not thread-safe: documented to be called once at the root, never inside the
 * search. */
unsigned baba_tb_probe_root(uint64_t white, uint64_t black, uint64_t kings,
                            uint64_t queens, uint64_t rooks, uint64_t bishops,
                            uint64_t knights, uint64_t pawns,
                            unsigned rule50, unsigned castling, unsigned ep,
                            int turn) {
    return tb_probe_root(white, black, kings, queens, rooks, bishops,
                         knights, pawns, rule50, castling, ep, turn != 0, NULL);
}

/* True when the DTZ tables (not just WDL) are available, i.e. the loaded
 * tablebases include distance-to-zero data for at least one material. */
int baba_tb_has_dtz(void) {
    return TB_LARGEST > 0;
}
