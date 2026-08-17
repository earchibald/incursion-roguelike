/* See the Incursion LICENSE file for copyright information.

   The C boundary between the Incursion engine (running on a background
   thread behind the Wmac.cpp Term backend) and the native macOS app in
   macapp/. The Swift side sees only this header: cells out, events in.

   Threading contract: incursion_engine_main() runs the whole game and
   blocks until quit -- call it on a dedicated thread. inc_push_event and
   the snapshot functions are safe from any thread. Callbacks fire on the
   engine thread; do minimal work and hop to the main queue.
*/
#ifndef WMAC_BRIDGE_H
#define WMAC_BRIDGE_H
#include <stdint.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif

/* A cell is the engine's Glyph verbatim: bits 0-11 glyph id (ids < 256 are
   CP437 characters, ids 256..375 the semantic GLYPH_* constants of
   inc/Defines.h), bits 12-15 foreground palette index, 16-19 background. */
typedef uint32_t IncCell;

typedef struct IncSnapshot {
    int32_t  sizeX, sizeY;      /* grid dimensions                      */
    int32_t  cursorX, cursorY;  /* absolute cell; -1,-1 = hidden        */
    int32_t  mode;              /* the engine's MO_* ui mode            */
    uint64_t seq;               /* increments once per engine Update()  */
    const IncCell *cells;       /* sizeX*sizeY, row-major; owned by the
                                   snapshot until inc_snapshot_release   */
} IncSnapshot;

typedef enum IncEventKind {
    INC_EV_KEY        = 1, /* ch = raw KY_* code, mods = modifier bits   */
    INC_EV_MOUSE_DOWN = 2, /* x,y = absolute cell                        */
    INC_EV_WHEEL      = 3, /* delta = +N lines up / -N lines down        */
    INC_EV_RESIZE     = 4, /* x,y = new grid size, floor 80x48           */
    INC_EV_QUIT       = 5  /* window closing: engine saves and finishes  */
} IncEventKind;

/* Modifier bits, matching SHIFT/CONTROL/ALT in inc/Term.h. */
enum { INC_MOD_SHIFT = 1, INC_MOD_CONTROL = 2, INC_MOD_ALT = 4 };

typedef struct IncEvent {
    int32_t kind;   /* IncEventKind */
    int32_t ch;     /* KEY: raw KY_* code (inc/Term.h)  */
    int32_t mods;   /* KEY: INC_MOD_* bits              */
    int32_t x, y;   /* MOUSE: cell; RESIZE: new sizeX,Y */
    int32_t delta;  /* WHEEL: signed line count         */
} IncEvent;

typedef struct IncCallbacks {
    void *ctx;
    void (*frame_ready)(void *ctx);             /* snapshot seq advanced    */
    void (*engine_waiting)(void *ctx);          /* about to block for input */
    void (*engine_finished)(void *ctx, int rc); /* game over; terminate app */
    void (*fatal_error)(void *ctx, const char *msg); /* logged; then parks  */
} IncCallbacks;

typedef struct IncEngineConfig {
    const char *incursion_dir; /* ABSOLUTE writable root (save/ logs/ mod/) */
    int32_t sizeX, sizeY;      /* initial grid, floor 80x48                 */
    int32_t no_sleep;          /* 1 = skip StopWatch animation sleeps       */
    int32_t strict_quit;       /* 1 = Wposix @quit semantics: a quit at an
                                  unquittable moment is dropped. Parity runs
                                  only; the app wants 0, where a quit drains
                                  dialogs with ESC until it can act.        */
    IncCallbacks cb;
} IncEngineConfig;

/* Runs the whole game (the Wlibtcod main() equivalent: Game before Term,
   SetIncursionDirectory before Initialize). Returns the game's retval. */
int  incursion_engine_main(const IncEngineConfig *cfg);

void inc_push_event(const IncEvent *ev);

/* Fills *out with a copy of the latest published frame. Returns 1 on
   success, 0 if no frame has been published yet. Pair with release. */
int  inc_snapshot_acquire(IncSnapshot *out);
void inc_snapshot_release(const IncSnapshot *snap);
uint64_t inc_snapshot_seq(void);

#ifdef __cplusplus
}
#endif
#endif /* WMAC_BRIDGE_H */
