/* MACTERM_PARITY.CPP -- See the Incursion LICENSE file for copyright
   information.

     Drives the Wmac backend (src/Wmac.cpp) through its C API with the same
   key scripts, the same environment contract and the same screen-dump format
   as the Wposix headless backend, so that

       diff <(posix run)/logs/screens <(mac run)/logs/screens

   is the correctness oracle for the whole native-app bridge. It exists to be
   run through tools/headless.sh:

       INCURSION_BIN=./build/macterm-parity tools/headless.sh tools/keys/smoke.keys 7

   CLI contract (matches src/Wposix.cpp main): -keys FILE, -timeout SECONDS;
   INCURSIONPATH is the game directory; INCURSION_SEED and INCURSION_MAX_KEYS
   pass through the environment. Exit codes: 0 clean, 1 Fatal, 2 bad script,
   3 out of keys or budget, 4 watchdog.

     The script token language (chars, "strings", named keys, ^X, TOK*N,
   @dump, @quit, @include, @while/@until) is duplicated from src/Wposix.cpp
   :835-1099 -- this is a tool, and the two copies are kept honest by the
   parity check itself: a divergence in parsing shows up as a screen diff.
*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <ctype.h>
#include <signal.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/types.h>

#include <thread>
#include <vector>

#include "Defines.h"       /* Glyph packing macros and GLYPH_* ids */
#include "WmacBridge.h"

/* Key codes, computed exactly as inc/Term.h computes them (KY_UP is
   200 + NORTH, and the Dir constants come from Defines.h, included above).
   Term.h itself cannot be included without the whole engine header stack.
   F1-F12 are enum values inside Term.h's KeyCmd and cannot be recovered
   here; no script in tools/keys/ uses them, and TokenToKey rejects them
   loudly rather than diverge from Wposix silently. */
#define KY_ESC        27
#define KY_ENTER      13
#define KY_TAB        '\t'
#define KY_SPACE      ' '
#define KY_BACKSPACE  213
#define KY_UP         (200 + NORTH)
#define KY_DOWN       (200 + SOUTH)
#define KY_LEFT       (200 + WEST)
#define KY_RIGHT      (200 + EAST)
#define KY_PGUP       (200 + NORTHEAST)
#define KY_PGDN       (200 + SOUTHEAST)
#define KY_HOME       (200 + NORTHWEST)
#define KY_END        (200 + SOUTHWEST)

#define SHIFT_FLAG   0x01
#define CONTROL_FLAG 0x02

#define SCREEN_W 80
#define SCREEN_H 48

#define DEFAULT_MAX_KEYS 20000
#define DEFAULT_TIMEOUT_S 300

#define EXIT_OUT_OF_KEYS 3
#define EXIT_OUT_OF_TIME 4

#define SK_DUMP  (-1)
#define SK_QUIT  (-2)
#define SK_WHILE (-3)
#define SK_UNTIL (-4)
/* Mac-driver only: @click "text" finds the text on the current screen and
   pushes a mouse event at its first cell. @clickrel DX DY clicks relative
   to the player's '@'. @wheel N pushes a scroll of N lines (+up/-down).
   Wposix has no mouse; scripts that use these cannot run there, so keep
   them out of the parity pair list. */
#define SK_CLICK    (-5)
#define SK_CLICKREL (-6)
#define SK_WHEEL    (-7)

#define SK_LOOP_MAX  200
#define SK_BODY_MAX  8

typedef struct ScriptKey {
    int ch;
    unsigned char mods;
    char label[64];
    int bodyCh[SK_BODY_MAX];
    unsigned char bodyMods[SK_BODY_MAX];
    int bodyCount, bodyPos, iter;
} ScriptKey;

static std::vector<ScriptKey> g_keys;
static size_t g_next = 0;
static long g_keysRead = 0;
static long g_maxKeys = DEFAULT_MAX_KEYS;
static int g_dumpCount = 0;
static unsigned g_timeout = DEFAULT_TIMEOUT_S;
static char g_dir[4096] = "";

/* ---------------------------------------------------------------- glyphs -- */

/* Same table, same fallbacks, as src/Wposix.cpp glyph_to_ascii. */
static char glyph_to_ascii(IncCell g) {
    static char t[GLYPH_LAST + 2];
    int c = GLYPH_ID_VALUE(g);

    if (!t[GLYPH_LAST + 1]) {
        int i;
        for (i = 0; i <= GLYPH_LAST; i++)
            t[i] = 0;

        t[GLYPH_UNSEEN] = ' ';
        t[GLYPH_VLINE] = '|';
        t[GLYPH_HLINE] = '-';
        t[GLYPH_DIVIDE] = '/';
        t[GLYPH_APPROXIMATELY] = '~';
        t[GLYPH_BLACK_SQUARE] = '*';
        t[GLYPH_CHECK] = 'v';
        t[GLYPH_CHECKMARK] = 'v';

        t[GLYPH_PERSON] = 'P';
        t[GLYPH_BULK] = '+';
        t[GLYPH_WATER] = '~';
        t[GLYPH_FOG] = '~';
        t[GLYPH_ICE] = '*';
        t[GLYPH_WEB] = '#';
        t[GLYPH_LAVA] = '~';
        t[GLYPH_BLAST] = '*';
        t[GLYPH_WALL] = '#';
        t[GLYPH_ROCK] = '#';
        t[GLYPH_SOLID] = '#';
        t[GLYPH_PILLAR1] = 'o';
        t[GLYPH_PILLAR2] = 'o';
        t[GLYPH_VIEWPOINT] = 'o';
        t[GLYPH_GRAVE] = 'n';
        t[GLYPH_SHELF] = '+';

        t[GLYPH_POTION] = '!';
        t[GLYPH_SCROLL] = '?';
        t[GLYPH_WEAPON] = 'v';
        t[GLYPH_ROD] = '|';
        t[GLYPH_STAFF] = '/';
        t[GLYPH_WAND] = '-';
        t[GLYPH_FOOD] = '%';
        t[GLYPH_CORPSE] = '%';
        t[GLYPH_BOOK] = '*';
        t[GLYPH_TORCH] = '}';
        t[GLYPH_LARMOUR] = '[';
        t[GLYPH_MARMOUR] = '[';
        t[GLYPH_HARMOUR] = '[';
        t[GLYPH_SHIELD] = ']';
        t[GLYPH_GAUNTLETS] = ']';
        t[GLYPH_HELMET] = ']';
        t[GLYPH_HEADBAND] = ']';
        t[GLYPH_BOOTS] = ']';
        t[GLYPH_BRACERS] = ']';
        t[GLYPH_GIRDLE] = ']';
        t[GLYPH_CLOTHES] = '[';
        t[GLYPH_CONTAIN] = '(';
        t[GLYPH_CROWN] = '^';
        t[GLYPH_DUST] = '=';
        t[GLYPH_DECK] = '=';
        t[GLYPH_RING] = '=';
        t[GLYPH_AMULET] = '"';
        t[GLYPH_FIGURE] = '&';
        t[GLYPH_HORN] = '&';
        t[GLYPH_EYES] = '&';
        t[GLYPH_HERB] = '"';
        t[GLYPH_MUSH] = ',';
        t[GLYPH_GEM] = '*';
        t[GLYPH_COIN] = '$';
        t[GLYPH_TOOL] = '&';
        t[GLYPH_SWORD] = '(';
        t[GLYPH_BOW] = ')';
        t[GLYPH_JUNK] = '&';
        t[GLYPH_CHEST] = '(';
        t[GLYPH_CLOAK] = '[';
        t[GLYPH_STATUE] = '&';
        t[GLYPH_PILE] = '*';
        t[GLYPH_MULTI] = '&';
        t[GLYPH_ALTAR] = '_';
        t[GLYPH_FOUNTAIN] = '{';
        t[GLYPH_THRONE] = '\\';
        t[GLYPH_SYMBOL] = '0';

        t[GLYPH_HEDGE] = '"';
        t[GLYPH_RUBBLE] = ':';
        t[GLYPH_BRIDGE] = '=';
        t[GLYPH_FLOOR] = '.';
        t[GLYPH_FLOOR2] = ',';
        t[GLYPH_VDOOR] = '|';
        t[GLYPH_HDOOR] = '-';
        t[GLYPH_ODOOR] = '+';
        t[GLYPH_BDOOR] = 'x';
        t[GLYPH_PIT] = '0';
        t[GLYPH_PORTAL] = '=';
        t[GLYPH_SUMMONING_CIRCLE] = '0';

        t[GLYPH_STORE] = '$';
        t[GLYPH_GUILD] = '$';
        t[GLYPH_STORE_VWALL] = '|';
        t[GLYPH_STORE_HWALL] = '-';
        t[GLYPH_STORE_CORNER] = '+';

        t[GLYPH_USTAIRS] = '<';
        t[GLYPH_DSTAIRS] = '>';
        t[GLYPH_TREE] = 'T';
        t[GLYPH_FURNATURE] = '*';
        t[GLYPH_UNKNOWN] = '?';
        t[GLYPH_TRASH] = '&';
        t[GLYPH_BONES] = '&';

        t[GLYPH_TRAP] = '^';
        t[GLYPH_DISARMED] = '/';

        t[GLYPH_ARROW] = '^';
        t[GLYPH_ARROW_UP] = '^';
        t[GLYPH_ARROW_DOWN] = 'v';
        t[GLYPH_ARROW_RIGHT] = '>';
        t[GLYPH_ARROW_LEFT] = '<';
        t[GLYPH_POINTER_LEFT] = '<';
        t[GLYPH_POINTER_RIGHT] = '>';

        t[GLYPH_GUARD] = 'i';
        t[GLYPH_TOWNIE] = 'i';
        t[GLYPH_TOWNSCUM] = 'i';
        t[GLYPH_TOWN_NPC] = 'i';
        t[GLYPH_LDEMON] = 'u';
        t[GLYPH_GDEMON] = 'U';
        t[GLYPH_LDEVIL] = 'o';
        t[GLYPH_GDEVIL] = 'O';
        t[GLYPH_FIEND] = 'y';

        t[GLYPH_PLAYER] = '@';
        t[GLYPH_HUMAN] = 'h';
        t[GLYPH_ELF] = 'e';
        t[GLYPH_DWARF] = 'd';
        t[GLYPH_GNOME] = 'g';
        t[GLYPH_HOBBIT] = 'g';

        t[GLYPH_LAST + 1] = 1;
    }

    if (c == 0)
        return ' ';
    if (c < GLYPH_FIRST)
        return (c >= 32 && c < 127) ? (char)c : '?';
    if (c > GLYPH_LAST)
        return '?';
    return t[c] ? t[c] : '?';
}

/* ----------------------------------------------------------------- dumps -- */

static void DumpScreen(const char *label) {
    char path[4200], dir[4200];
    IncSnapshot snap;
    FILE *f;
    int x, y, last;

    if (!inc_snapshot_acquire(&snap))
        return;

    snprintf(dir, sizeof(dir), "%slogs/screens", g_dir);
    mkdir(dir, 0755);
    snprintf(path, sizeof(path), "%s/%04d%s%s.txt", dir, ++g_dumpCount,
        (label && *label) ? "-" : "", (label && *label) ? label : "");

    f = fopen(path, "w");
    if (!f) {
        inc_snapshot_release(&snap);
        return;
    }

    fprintf(f, "=== screen %04d %s  key %ld  mode %d ===\n",
        g_dumpCount, (label && *label) ? label : "", g_keysRead,
        (int)snap.mode);

    for (y = 0; y < snap.sizeY; y++) {
        char line[SCREEN_W * 8 + 2];
        for (x = 0; x < snap.sizeX && x < SCREEN_W * 8; x++)
            line[x] = glyph_to_ascii(snap.cells[y * snap.sizeX + x]);
        for (last = x - 1; last >= 0 && line[last] == ' '; last--)
            ;
        line[last + 1] = '\0';
        fprintf(f, "%s\n", line);
    }

    /* Matches the INCURSION_DUMP_COLOR section Wposix emits, so the diff
       covers colours and the cursor -- the things the app actually draws
       that the ASCII fold cannot see. */
    if (getenv("INCURSION_DUMP_COLOR")) {
        fprintf(f, "--- colours ---\n");
        for (y = 0; y < snap.sizeY; y++) {
            for (x = 0; x < snap.sizeX; x++)
                fprintf(f, "%02x",
                    (unsigned)((snap.cells[y * snap.sizeX + x] >> 12) & 0xFF));
            fprintf(f, "\n");
        }
        if (snap.cursorX >= 0)
            fprintf(f, "cursor %d %d 1\n", (int)snap.cursorX, (int)snap.cursorY);
        else
            fprintf(f, "cursor -1 -1 0\n");
    }

    fclose(f);
    inc_snapshot_release(&snap);
}

static bool ScreenShows(const char *text) {
    IncSnapshot snap;
    bool found = false;
    int x, y;

    if (!text || !*text || !inc_snapshot_acquire(&snap))
        return false;

    for (y = 0; y < snap.sizeY && !found; y++) {
        char line[SCREEN_W * 8 + 2];
        for (x = 0; x < snap.sizeX && x < SCREEN_W * 8; x++)
            line[x] = glyph_to_ascii(snap.cells[y * snap.sizeX + x]);
        line[x] = '\0';
        if (strstr(line, text))
            found = true;
    }

    inc_snapshot_release(&snap);
    return found;
}

/* ---------------------------------------------------------------- script -- */

static const struct { const char *name; int ch; } NamedKeys[] = {
    { "ESC", KY_ESC }, { "ENTER", KY_ENTER }, { "RETURN", KY_ENTER },
    { "TAB", KY_TAB }, { "SPACE", KY_SPACE }, { "BKSP", KY_BACKSPACE },
    { "BACKSPACE", KY_BACKSPACE },
    { "UP", KY_UP }, { "DOWN", KY_DOWN }, { "LEFT", KY_LEFT },
    { "RIGHT", KY_RIGHT }, { "HOME", KY_HOME }, { "END", KY_END },
    { "PGUP", KY_PGUP }, { "PGDN", KY_PGDN },
    { NULL, 0 }
};

/* See the key-code comment above: these exist in Wposix but not here. */
static const char *UnsupportedKeys[] = {
    "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12",
    NULL
};

static bool TokenToKey(const char *tok, ScriptKey *out) {
    int i;

    memset(out, 0, sizeof(*out));

    if (tok[0] == '@') {
        if (!strncmp(tok + 1, "dump", 4) && (!tok[5] || tok[5] == ':')) {
            out->ch = SK_DUMP;
            if (tok[5] == ':')
                snprintf(out->label, sizeof(out->label), "%s", tok + 6);
            return true;
        }
        if (!strcmp(tok + 1, "quit")) {
            out->ch = SK_QUIT;
            return true;
        }
        return false;
        /* @click is parsed in LoadKeyScript, since it carries quoted text. */
    }

    if (tok[0] == '^' && tok[1] && !tok[2]) {
        out->ch = tolower((unsigned char)tok[1]);
        out->mods = CONTROL_FLAG;
        return true;
    }

    for (i = 0; NamedKeys[i].name; i++)
        if (!strcasecmp(tok, NamedKeys[i].name)) {
            out->ch = NamedKeys[i].ch;
            return true;
        }

    for (i = 0; UnsupportedKeys[i]; i++)
        if (!strcasecmp(tok, UnsupportedKeys[i])) {
            printf("macterm-parity: key '%s' is not supported here; "
                "see the key-code comment in tools/macterm_parity.cpp.\n", tok);
            exit(2);
        }

    if (tok[0] && !tok[1]) {
        out->ch = (unsigned char)tok[0];
        if (isupper((unsigned char)tok[0]))
            out->mods = SHIFT_FLAG;
        return true;
    }

    return false;
}

static void LoadKeyScript(const char *fn) {
    static int depth = 0;
    FILE *f = fopen(fn, "r");
    char tok[4096];
    int c;

    if (!f) {
        printf("Cannot open key script '%s'.\n", fn);
        exit(2);
    }
    if (++depth > 8) {
        printf("Key script '%s': includes are nested too deeply.\n", fn);
        exit(2);
    }

    for (;;) {
        int n = 0, repeat = 1, i;
        ScriptKey k;

        c = fgetc(f);
        if (c == EOF)
            break;
        if (isspace(c))
            continue;
        if (c == '#') {
            while (c != EOF && c != '\n')
                c = fgetc(f);
            continue;
        }

        if (c == '"') {
            while ((c = fgetc(f)) != EOF && c != '"') {
                char one[2] = { (char)c, 0 };
                if (TokenToKey(one, &k))
                    g_keys.push_back(k);
            }
            continue;
        }

        tok[n++] = (char)c;
        while ((c = fgetc(f)) != EOF && !isspace(c) && n < (int)sizeof(tok) - 1)
            tok[n++] = (char)c;
        tok[n] = '\0';

        if (!strcmp(tok, "@include")) {
            char inc[4096], resolved[4200];
            const char *slash;

            n = 0;
            while ((c = fgetc(f)) != EOF && isspace(c))
                ;
            while (c != EOF && !isspace(c) && n < (int)sizeof(inc) - 1) {
                inc[n++] = (char)c;
                c = fgetc(f);
            }
            inc[n] = '\0';

            slash = strrchr(fn, '/');
            if (inc[0] == '/' || !slash)
                snprintf(resolved, sizeof(resolved), "%s", inc);
            else
                snprintf(resolved, sizeof(resolved), "%.*s%s",
                    (int)(slash - fn + 1), fn, inc);
            LoadKeyScript(resolved);
            continue;
        }

        if (!strcmp(tok, "@click")) {
            memset(&k, 0, sizeof(k));
            k.ch = SK_CLICK;
            while ((c = fgetc(f)) != EOF && isspace(c))
                ;
            if (c != '"') {
                printf("Key script '%s': @click needs a quoted screen text.\n",
                    fn);
                exit(2);
            }
            n = 0;
            while ((c = fgetc(f)) != EOF && c != '"' &&
                   n < (int)sizeof(k.label) - 1)
                k.label[n++] = (char)c;
            k.label[n] = '\0';
            if (!n) {
                printf("Key script '%s': @click was given an empty text.\n",
                    fn);
                exit(2);
            }
            g_keys.push_back(k);
            continue;
        }

        if (!strcmp(tok, "@clickrel") || !strcmp(tok, "@wheel")) {
            char numtok[64];
            int wantTwo = !strcmp(tok, "@clickrel");
            int vals[2] = { 0, 0 }, nv;

            memset(&k, 0, sizeof(k));
            k.ch = wantTwo ? SK_CLICKREL : SK_WHEEL;
            for (nv = 0; nv < (wantTwo ? 2 : 1); nv++) {
                while ((c = fgetc(f)) != EOF && isspace(c))
                    ;
                n = 0;
                while (c != EOF && !isspace(c) && n < (int)sizeof(numtok) - 1) {
                    numtok[n++] = (char)c;
                    c = fgetc(f);
                }
                numtok[n] = '\0';
                if (!n || !(isdigit((unsigned char)numtok[0])
                            || numtok[0] == '-')) {
                    printf("Key script '%s': %s needs %d number(s).\n",
                        fn, tok, wantTwo ? 2 : 1);
                    exit(2);
                }
                vals[nv] = atoi(numtok);
            }
            k.bodyCh[0] = vals[0];
            k.bodyCh[1] = vals[1];
            g_keys.push_back(k);
            continue;
        }

        if (!strcmp(tok, "@while") || !strcmp(tok, "@until")) {
            char keytok[4096];
            ScriptKey loop;

            memset(&k, 0, sizeof(k));
            k.ch = !strcmp(tok, "@while") ? SK_WHILE : SK_UNTIL;

            while ((c = fgetc(f)) != EOF && isspace(c))
                ;
            if (c != '"') {
                printf("Key script '%s': %s needs a quoted screen text.\n",
                    fn, tok);
                exit(2);
            }
            n = 0;
            while ((c = fgetc(f)) != EOF && c != '"' &&
                   n < (int)sizeof(k.label) - 1)
                k.label[n++] = (char)c;
            k.label[n] = '\0';
            if (!n) {
                printf("Key script '%s': %s was given an empty text.\n",
                    fn, tok);
                exit(2);
            }

            for (;;) {
                while ((c = fgetc(f)) != EOF && (c == ' ' || c == '\t'))
                    ;
                if (c == EOF || c == '\n')
                    break;
                if (c == '#') {
                    while ((c = fgetc(f)) != EOF && c != '\n')
                        ;
                    break;
                }

                n = 0;
                while (c != EOF && !isspace(c) && n < (int)sizeof(keytok) - 1) {
                    keytok[n++] = (char)c;
                    c = fgetc(f);
                }
                keytok[n] = '\0';

                if (!TokenToKey(keytok, &loop) || loop.ch < 0) {
                    printf("Key script '%s': %s takes ordinary keys after its "
                        "text, and got '%s'.\n", fn, tok, keytok);
                    exit(2);
                }
                if (k.bodyCount >= SK_BODY_MAX) {
                    printf("Key script '%s': %s \"%s\" has more than %d keys "
                        "in its body.\n", fn, tok, k.label, SK_BODY_MAX);
                    exit(2);
                }
                k.bodyCh[k.bodyCount] = loop.ch;
                k.bodyMods[k.bodyCount] = loop.mods;
                k.bodyCount++;

                if (c == '\n' || c == EOF)
                    break;
            }

            if (!k.bodyCount) {
                printf("Key script '%s': %s \"%s\" has no keys after it.\n",
                    fn, tok, k.label);
                exit(2);
            }
            g_keys.push_back(k);
            continue;
        }

        if (n > 1) {
            char *star = strrchr(tok, '*');
            if (star && star != tok && isdigit((unsigned char)star[1])) {
                repeat = atoi(star + 1);
                *star = '\0';
                if (repeat < 1)
                    repeat = 1;
            }
        }

        if (!TokenToKey(tok, &k)) {
            printf("Key script '%s': cannot read token '%s'.\n", fn, tok);
            exit(2);
        }

        for (i = 0; i < repeat; i++)
            g_keys.push_back(k);
    }

    fclose(f);
    depth--;
}

/* ------------------------------------------------------------- callbacks -- */

static void PushKey(int ch, unsigned char mods) {
    IncEvent ev;
    memset(&ev, 0, sizeof(ev));
    ev.kind = INC_EV_KEY;
    ev.ch = ch;
    ev.mods = mods;
    inc_push_event(&ev);
    g_keysRead++;
    alarm(g_timeout);
}

/* Called on the engine thread whenever the game is blocked for input with a
   settled frame. Feeds exactly one keystroke per call, exactly as Wposix's
   NextKey feeds its wait loop. */
static void OnEngineWaiting(void *ctx) {
    (void)ctx;

    for (;;) {
        ScriptKey *e;

        if (g_keysRead >= g_maxKeys) {
            DumpScreen("maxkeys");
            fprintf(stderr, "incursion: key budget of %ld reached\n", g_maxKeys);
            exit(EXIT_OUT_OF_KEYS);
        }
        if (g_next >= g_keys.size()) {
            DumpScreen("final");
            fprintf(stderr, "incursion: key script exhausted after %ld keys\n",
                g_keysRead);
            exit(0);
        }

        e = &g_keys[g_next];

        /* Wposix counts every consumed token -- @dump and @quit included --
           in keysRead, and the count is printed in every dump header, so
           this must count the same way. */
        if (e->ch == SK_DUMP) {
            g_keysRead++;
            DumpScreen(e->label);
            g_next++;
            continue;
        }
        if (e->ch == SK_QUIT) {
            IncEvent ev;
            memset(&ev, 0, sizeof(ev));
            ev.kind = INC_EV_QUIT;
            g_keysRead++;
            inc_push_event(&ev);
            g_next++;
            alarm(g_timeout);
            return;
        }
        if (e->ch == SK_CLICK) {
            IncSnapshot snap;
            IncEvent ev;
            int x, y, foundX = -1, foundY = -1;

            if (inc_snapshot_acquire(&snap)) {
                for (y = 0; y < snap.sizeY && foundY < 0; y++) {
                    char line[SCREEN_W * 8 + 2];
                    for (x = 0; x < snap.sizeX && x < SCREEN_W * 8; x++)
                        line[x] = glyph_to_ascii(snap.cells[y * snap.sizeX + x]);
                    line[x] = '\0';
                    const char *hit = strstr(line, e->label);
                    if (hit) {
                        foundX = (int)(hit - line);
                        foundY = y;
                    }
                }
                inc_snapshot_release(&snap);
            }
            if (foundY < 0) {
                fprintf(stderr, "macterm-parity: @click \"%s\" is not on the "
                    "screen\n", e->label);
                DumpScreen("clickmiss");
                exit(2);
            }
            memset(&ev, 0, sizeof(ev));
            ev.kind = INC_EV_MOUSE_DOWN;
            ev.x = foundX;
            ev.y = foundY;
            g_keysRead++;
            inc_push_event(&ev);
            g_next++;
            alarm(g_timeout);
            return;
        }
        if (e->ch == SK_CLICKREL) {
            IncSnapshot snap;
            IncEvent ev;
            int x, y, atX = -1, atY = -1;

            if (inc_snapshot_acquire(&snap)) {
                for (y = 0; y < snap.sizeY && atY < 0; y++)
                    for (x = 0; x < snap.sizeX; x++)
                        if (glyph_to_ascii(snap.cells[y * snap.sizeX + x]) == '@') {
                            atX = x;
                            atY = y;
                            break;
                        }
                inc_snapshot_release(&snap);
            }
            if (atY < 0) {
                fprintf(stderr, "macterm-parity: @clickrel found no '@' on "
                    "the screen\n");
                DumpScreen("clickmiss");
                exit(2);
            }
            memset(&ev, 0, sizeof(ev));
            ev.kind = INC_EV_MOUSE_DOWN;
            ev.x = atX + e->bodyCh[0];
            ev.y = atY + e->bodyCh[1];
            g_keysRead++;
            inc_push_event(&ev);
            g_next++;
            alarm(g_timeout);
            return;
        }
        if (e->ch == SK_WHEEL) {
            IncEvent ev;
            memset(&ev, 0, sizeof(ev));
            ev.kind = INC_EV_WHEEL;
            ev.delta = e->bodyCh[0];
            g_keysRead++;
            inc_push_event(&ev);
            g_next++;
            alarm(g_timeout);
            return;
        }
        if (e->ch == SK_WHILE || e->ch == SK_UNTIL) {
            if (e->bodyPos == 0) {
                bool shown = ScreenShows(e->label);
                bool fire = (e->ch == SK_WHILE) ? shown : !shown;

                if (!fire || e->iter >= SK_LOOP_MAX) {
                    if (fire)
                        fprintf(stderr, "incursion: %s \"%s\" gave up after %d "
                            "passes\n", e->ch == SK_WHILE ? "@while" : "@until",
                            e->label, SK_LOOP_MAX);
                    e->iter = 0;
                    g_next++;
                    continue;
                }
                e->iter++;
            }

            PushKey(e->bodyCh[e->bodyPos], e->bodyMods[e->bodyPos]);
            e->bodyPos++;
            if (e->bodyPos >= e->bodyCount)
                e->bodyPos = 0;
            return;
        }

        PushKey(e->ch, e->mods);
        g_next++;
        return;
    }
}

static void OnEngineFinished(void *ctx, int rc) {
    (void)ctx;
    DumpScreen("shutdown");
    exit(rc);
}

static void OnFatal(void *ctx, const char *msg) {
    (void)ctx;
    DumpScreen("fatal");
    fprintf(stderr, "incursion: fatal: %s\n", msg);
    exit(1);
}

static void OnTimeout(int sig) {
    const char msg[] = "incursion: watchdog timeout, no key read in time\n";
    ssize_t ignored = write(2, msg, sizeof(msg) - 1);
    (void)ignored;
    (void)sig;
    _exit(EXIT_OUT_OF_TIME);
}

/* ------------------------------------------------------------------ main -- */

int main(int argc, char *argv[]) {
    const char *keyScript = NULL;
    char *envPath = getenv("INCURSIONPATH");
    int i;

    for (i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "-keys") && i + 1 < argc)
            keyScript = argv[++i];
        else if (!strcmp(argv[i], "-timeout") && i + 1 < argc)
            g_timeout = (unsigned)atoi(argv[++i]);
    }

    if (envPath && *envPath)
        snprintf(g_dir, sizeof(g_dir), "%s", envPath);
    else if (!getcwd(g_dir, sizeof(g_dir))) {
        fprintf(stderr, "macterm-parity: cannot resolve a game directory\n");
        return 2;
    }
    /* Must be absolute, same rule and same fix as the Wposix main(): the
       engine chdir()s constantly and returns home via this path. */
    {
        char resolved[4096];
        if (realpath(g_dir, resolved))
            snprintf(g_dir, sizeof(g_dir), "%s", resolved);
    }
    if (g_dir[strlen(g_dir) - 1] != '/')
        strncat(g_dir, "/", sizeof(g_dir) - strlen(g_dir) - 1);

    if (!keyScript) {
        fprintf(stderr, "usage: macterm-parity -keys FILE [-timeout SECONDS]\n"
            "environment: INCURSIONPATH, INCURSION_SEED, INCURSION_MAX_KEYS\n");
        return 2;
    }

    if (getenv("INCURSION_MAX_KEYS"))
        g_maxKeys = atol(getenv("INCURSION_MAX_KEYS"));

    LoadKeyScript(keyScript);

    signal(SIGALRM, OnTimeout);
    alarm(g_timeout);

    IncEngineConfig cfg;
    memset(&cfg, 0, sizeof(cfg));
    cfg.incursion_dir = g_dir;
    cfg.sizeX = SCREEN_W;
    cfg.sizeY = SCREEN_H;
    cfg.no_sleep = 1;
    cfg.strict_quit = 1;
    cfg.cb.engine_waiting = OnEngineWaiting;
    cfg.cb.engine_finished = OnEngineFinished;
    cfg.cb.fatal_error = OnFatal;

    /* The engine never returns except on a config error; every real ending
       arrives through a callback above. */
    return incursion_engine_main(&cfg);
}
