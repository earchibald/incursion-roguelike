/* WMAC.CPP -- See the Incursion LICENSE file for copyright information.

     Contains the class definition and member functions for the macTerm
   class: the bridge backend behind the native macOS app in macapp/.

     Why it exists. The engine is single-threaded and funnels all input
   through GetCharCmd and all output through the Term virtuals. This backend
   runs the whole game on a background thread: GetCharCmd blocks on an event
   queue the UI fills, and Update() publishes Glyph-grid snapshots the UI
   renders with CoreText. The Swift side sees only src/WmacBridge.h.

     The screen model follows Wposix.cpp: a plain array of Glyph, stored
   verbatim, which keeps AGetChar exact -- three engine call sites round-trip
   glyph ids through it (Term.cpp:1969, Magic.cpp, Skills.cpp) and the
   libtcod backend's lossy read-back is a defect this backend does not copy.

   Threading contract (mirrors WmacBridge.h):
     incursion_engine_main   runs the game; call on a dedicated thread.
     inc_push_event          any thread.
     inc_snapshot_*          any thread.
     Callbacks fire on the engine thread.

   Low-Level Read/Write
     void macTerm::Update()          void macTerm::PutChar(...)
     void macTerm::CursorOn/Off()    Glyph macTerm::AGetChar(...)
     void macTerm::Save/Restore()    void macTerm::Clear()
   Input Functions
     int16 macTerm::GetCharCmd(KeyCmdMode mode)  -- blocks on the event queue
   General Functions
     void macTerm::Initialize()      void Fatal(...)  void Error(...)
   File I/O
     POSIX: stat, unlink, opendir, fnmatch. Same code as Wposix.cpp.
*/

#ifdef MAC_TERM

#define _CRT_SECURE_NO_WARNINGS

#undef TRACE
#undef MIN
#undef MAX
#undef ERROR
#undef EV_BREAK

#include <stdarg.h>
#include <ctype.h>
#include <time.h>
#include <malloc.h>
#include <unistd.h>
#include <dirent.h>
#include <fnmatch.h>
#include <sys/stat.h>
#include <sys/types.h>

#include <mutex>
#include <condition_variable>
#include <deque>
#include <atomic>

#include "Incursion.h"
#undef ERROR
#undef MIN
#undef MAX

#include "ErrorLog.h"
#include "WmacBridge.h"

#define _mkdir(A) mkdir(A, 0755)

/* The game asserts on anything smaller (TextTerm::InitWindows), and every
   window position in that function is derived from these two numbers. */
#define MIN_SCREEN_W 80
#define MIN_SCREEN_H 48
/* Sanity cap; a 4-point font on a cinema display stays well under this. */
#define MAX_SCREEN_W 512
#define MAX_SCREEN_H 256

char __buffer[1600];
char __buff2[80];

class macTerm : public TextTerm {
    friend void Error(const char* fmt, ...);
    friend void Fatal(const char* fmt, ...);
    friend int ::incursion_engine_main(const IncEngineConfig *cfg);

private:
    /* Screen model. gridX/gridY duplicate sizeX/sizeY but stay in step with
       the allocation, which matters mid-resize. */
    Glyph *scr, *sav;
    int32 gridX, gridY;
    Glyph *scrollBuf;               /* MAX_SCROLL_LINES x SCROLL_WIDTH */
    bool showCursor;
    String debugText;

    /* Snapshot the UI reads. Published whole under snapLock. */
    std::mutex snapLock;
    IncCell *snapCells;
    int32 snapX, snapY, snapCursorX, snapCursorY, snapMode;
    uint64_t snapSeq;

    /* Event queue the UI fills. */
    std::mutex evLock;
    std::condition_variable evReady;
    std::deque<IncEvent> events;

    /* Parking: a thread that must never run again (Fatal, ShutDown) blocks
       here while the UI terminates the process. */
    std::mutex parkLock;
    std::condition_variable parkCV;

    IncCallbacks cb;
    bool noSleep;
    bool strictQuit;
    int16 quitEscBudget;            /* ESCs left to drain dialogs on quit */
    bool quitPending;
    char lastStateJson[256];        /* narrator tap: last published sample */

    /* File I/O */
    String CurrentDirectory;
    String CurrentFileName;
    FILE *fp;
    DIR *findDir;
    String findSpec;

    uint32 startMilli;

public:
    macTerm(const IncEngineConfig *cfg) {
        struct timespec ts;
        scr = sav = scrollBuf = NULL;
        gridX = gridY = 0;
        showCursor = false;
        snapCells = NULL;
        snapX = snapY = snapMode = 0;
        snapCursorX = snapCursorY = -1;
        snapSeq = 0;
        cb = cfg->cb;
        noSleep = cfg->no_sleep != 0;
        strictQuit = cfg->strict_quit != 0;
        quitEscBudget = 50;
        quitPending = false;
        lastStateJson[0] = 0;
        fp = NULL;
        findDir = NULL;
        initialised = false;
        sizeX = (int16)cfg->sizeX;
        sizeY = (int16)cfg->sizeY;
        clock_gettime(CLOCK_MONOTONIC, &ts);
        startMilli = (uint32)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
    }

    /* Low-Level Read/Write */
    virtual void Update();
    virtual void Message(const char *msg);
    void PublishPlayerState();
    virtual void CursorOn()  { showCursor = true; }
    virtual void CursorOff() { showCursor = false; }
    virtual int16 CursorX() { return cx; }
    virtual int16 CursorY() { return cy; }
    virtual void Save();
    virtual void Restore();
    virtual void PutChar(Glyph g);
    virtual void APutChar(int16 x, int16 y, Glyph g);
    virtual void PutChar(int16 x, int16 y, Glyph g);
    virtual Glyph AGetChar(int16 x, int16 y);
    virtual void GotoXY(int16 x, int16 y);
    virtual void Clear();
    virtual void Color(uint16 _attr) { attr = _attr; }
    virtual void StopWatch(int16 milli);
    virtual uint32 GetElapsedMilli();
    virtual int32 ConvertChar(Glyph g, char **out) { return 0; }

    /* Input Functions */
    virtual int16 GetCharRaw() { return GetCharCmd(KY_CMD_RAW); }
    virtual int16 GetCharCmd() { return GetCharCmd(KY_CMD_NORMAL_MODE); }
    virtual int16 GetCharCmd(KeyCmdMode mode);
    virtual bool CheckEscape();
    virtual void ClearKeyBuff();
    virtual void PrePrompt() { ClearKeyBuff(); }

    /* General Functions */
    virtual void Initialize();
    virtual void ShutDown();
    virtual void Reset() { }
    /* The Swift window owns resolution and fonts now; the in-game options
       for them would change nothing and mislead. */
    virtual bool hideOption(int16 opt) {
        return opt == OPT_WIND_RES || opt == OPT_FULL_RES
            || opt == OPT_WIND_FONT || opt == OPT_FULL_FONT;
    }
    virtual void SetDebugText(const char *text) { debugText = text; }
    virtual void Title() { TextTerm::Title(); }

    /* Scroll Buffer */
    virtual void SPutChar(int16 x, int16 y, Glyph g);
    virtual uint16 SGetChar(int16 x, int16 y);
    virtual void SPutColor(int16 x, int16 y, uint16 col);
    virtual uint16 SGetColor(int16 x, int16 y);
    virtual void SClear();
    virtual void BlitScrollLine(int16 wn, int32 buffline, int32 winline);

    /* System-Independant File I/O */
    virtual const char* SaveSubDir()    { return "save"; }
    virtual const char* ModuleSubDir()  { return "mod"; }
    virtual const char* LibraryPath() {
        char *envLibPath;
        static char s[MAX_PATH_LENGTH] = "";
        if (strlen(s) == 0) {
            envLibPath = getenv("INCURSIONLIBPATH");
            if (envLibPath != NULL && strlen(envLibPath)) {
                if (strcat(s, envLibPath)) {
                    if (s[strlen(s) - 1] == '/')
                        s[strlen(s) - 1] = '\0';
                }
            }
            if (strlen(s) == 0) {
                strcat(s, IncursionDirectory);
                strcat(s, "lib");
            }
        }
        return s;
    }
    virtual const char* LogSubDir()     { return "logs"; }
    virtual const char* ManualSubDir()  { return "man"; }
    virtual const char* OptionsSubDir() { return "."; }
    virtual void ChangeDirectory(const char * c, bool set) {
        if (set)
            CurrentDirectory = c;
        else {
            CurrentDirectory = (const char*)IncursionDirectory;
            if (CurrentDirectory != c)
                CurrentDirectory += c;
        }
        if (chdir(CurrentDirectory)) {
            char path[MAX_PATH_LENGTH];
            getcwd(path, MAX_PATH_LENGTH);
            Fatal("Unable to locate directory: '%s' (cwd: '%s').",
                (const char*)CurrentDirectory, path);
        }
    }
    virtual bool Exists(const char* fn);
    virtual void Delete(const char* fn);
    virtual void OpenRead(const char* fn);
    virtual void OpenWrite(const char* fn);
    virtual void OpenUpdate(const char* fn);
    virtual void Close();
    virtual void FRead(void*, size_t sz);
    virtual void FWrite(const void*, size_t sz);
    virtual void Seek(int32, int8);
    virtual void Cut(int32);
    virtual bool FirstFile(char * filespec);
    virtual bool NextFile();
    virtual char * MenuListFiles(const char * filespec, uint16 flags, const char *title);
    virtual const char* GetFileName() { return CurrentFileName; }
    virtual int32 Tell();

    void SetIncursionDirectory(const char *s);
    void PushEvent(const IncEvent &ev);
    int  SnapshotAcquire(IncSnapshot *out);
    uint64_t SnapshotSeq();

private:
    void AllocGrid(int32 w, int32 h);
    void ResizeGrid(int32 w, int32 h);
    void KeyHousekeeping(KeyCmdMode mode);
    IncEvent NextEvent();
    void Park();
};

Term *T1;
/* The engine thread constructs the terminal; the UI thread calls the C API
   the moment the window is key. The bridge functions must observe either
   NULL or a FULLY constructed object, so the pointer is published with
   release/acquire ordering. Engine-thread code (Fatal, Error) may read the
   raw pointer -- it lives on the constructing thread. */
static macTerm *MT;
static std::atomic<macTerm*> MTpub{nullptr};

/*****************************************************************************\
*                                   macTerm                                   *
*                            Low-Level Read/Write                             *
\*****************************************************************************/

void macTerm::AllocGrid(int32 w, int32 h) {
    int32 i;

    free(scr);
    free(sav);
    gridX = w;
    gridY = h;
    scr = (Glyph*)malloc(w * h * sizeof(Glyph));
    sav = (Glyph*)malloc(w * h * sizeof(Glyph));
    for (i = 0; i < w * h; i++)
        scr[i] = sav[i] = ' ';
}

/* Publish the frame. The UI reads only what this writes. */
void macTerm::Update() {
    {
        std::lock_guard<std::mutex> lk(snapLock);
        if (!snapCells || snapX != gridX || snapY != gridY) {
            free(snapCells);
            snapCells = (IncCell*)malloc(gridX * gridY * sizeof(IncCell));
            snapX = gridX;
            snapY = gridY;
        }
        memcpy(snapCells, scr, gridX * gridY * sizeof(IncCell));
        snapCursorX = showCursor ? cx : -1;
        snapCursorY = showCursor ? cy : -1;
        snapMode = Mode;
        snapSeq++;
    }
    PublishPlayerState();
    if (cb.frame_ready)
        cb.frame_ready(cb.ctx);
    updated = true;
}

/* Narrator tap: every message-pane line, verbatim, before display. */
void macTerm::Message(const char *msg) {
    if (cb.game_message && msg && *msg)
        cb.game_message(cb.ctx, msg);
    TextTerm::Message(msg);
}

static void narratorEscJson(const char *in, char *out, size_t cap) {
    size_t o = 0;
    for (; *in && o + 2 < cap; in++) {
        unsigned char c = (unsigned char)*in;
        if (c == '"' || c == '\\') { out[o++] = '\\'; out[o++] = c; }
        else if (c < 32)           { out[o++] = ' '; }
        else                       { out[o++] = (char)c; }
    }
    out[o] = 0;
}

/* Narrator tap: sample the player after an update; publish on change. */
void macTerm::PublishPlayerState() {
    if (!cb.player_state || !p || !theGame)
        return;
    char nm[64];
    narratorEscJson(p->Name(), nm, sizeof(nm));
    char buf[256];
    snprintf(buf, sizeof(buf),
        "{\"name\":\"%s\",\"level\":%d,\"depth\":%d,"
        "\"hp\":%d,\"maxhp\":%d,\"turn\":%u}",
        nm, (int)p->TotalLevel(), (int)(p->m ? p->m->Depth : 0),
        (int)p->cHP, (int)p->mHP, (unsigned)theGame->GetTurn());
    if (strcmp(buf, lastStateJson) == 0)
        return;
    strcpy(lastStateJson, buf);
    cb.player_state(cb.ctx, buf);
}

void macTerm::StopWatch(int16 milli) {
    if (noSleep)
        return;
    switch (p ? p->Opt(OPT_ANIMATION) : 0) {
    case 0: usleep((useconds_t)milli * 1000); return;
    case 1: usleep((useconds_t)((milli + 3) / 4) * 1000); return;
    case 2: return;
    }
}

void macTerm::Save() {
    memcpy(sav, scr, gridX * gridY * sizeof(Glyph));
}

void macTerm::Restore() {
    memcpy(scr, sav, gridX * gridY * sizeof(Glyph));
}

void macTerm::PutChar(Glyph g) {
    APutChar(cx++, cy, g);
}

void macTerm::APutChar(int16 x, int16 y, Glyph g) {
    uint16 fg = GLYPH_FORE_VALUE(g);
    uint16 bg = GLYPH_BACK_VALUE(g);

    if (x < 0 || x >= gridX || y < 0 || y >= gridY)
        return;

    /* A glyph with no colour of its own takes the current pen, exactly as the
       other backends do. */
    if (fg == 0 && bg == 0)
        g = GLYPH_ID_VALUE(g)
          | GLYPH_FORE(attr & COLOUR_MASK)
          | GLYPH_BACK((attr >> COLOUR_BITS) & COLOUR_MASK);

    scr[y * gridX + x] = g;
    updated = false;
}

void macTerm::PutChar(int16 x, int16 y, Glyph g) {
    APutChar(x + activeWin->Left, y + activeWin->Top, g);
}

/* Exact: the stored Glyph comes back verbatim. See the file comment. */
Glyph macTerm::AGetChar(int16 x, int16 y) {
    if (x < 0 || x >= gridX || y < 0 || y >= gridY)
        return ' ';
    return scr[y * gridX + x];
}

void macTerm::GotoXY(int16 x, int16 y) {
    cx = x + activeWin->Left;
    cy = y + activeWin->Top;
}

void macTerm::Clear() {
    int16 x, y;

    for (y = activeWin->Top; y <= activeWin->Bottom; y++)
        for (x = activeWin->Left; x <= activeWin->Right; x++)
            if (x >= 0 && x < gridX && y >= 0 && y < gridY)
                scr[y * gridX + x] = ' ';

    cWrap = 0; cx = cy = 0;
    if (activeWin == &Windows[WIN_SCREEN] || activeWin == &Windows[WIN_MESSAGE])
        linepos = linenum = 0;
    updated = false;
}

uint32 macTerm::GetElapsedMilli() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint32)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000) - startMilli;
}

/*****************************************************************************\
*                                   macTerm                                   *
*                               Scroll Buffer                                 *
\*****************************************************************************/

void macTerm::SPutChar(int16 x, int16 y, Glyph g) {
    if (!scrollBuf || x < 0 || x >= SCROLL_WIDTH || y < 0 || y >= MAX_SCROLL_LINES)
        return;
    scrollBuf[y * SCROLL_WIDTH + x] = g;
}

uint16 macTerm::SGetChar(int16 x, int16 y) {
    if (!scrollBuf || x < 0 || x >= SCROLL_WIDTH || y < 0 || y >= MAX_SCROLL_LINES)
        return ' ';
    return (uint16)GLYPH_ID_VALUE(scrollBuf[y * SCROLL_WIDTH + x]);
}

void macTerm::SPutColor(int16 x, int16 y, uint16 col) {
    if (!scrollBuf || x < 0 || x >= SCROLL_WIDTH || y < 0 || y >= MAX_SCROLL_LINES)
        return;
    scrollBuf[y * SCROLL_WIDTH + x] =
        GLYPH_ID_VALUE(scrollBuf[y * SCROLL_WIDTH + x]) | GLYPH_ATTR(col);
}

uint16 macTerm::SGetColor(int16 x, int16 y) {
    if (!scrollBuf || x < 0 || x >= SCROLL_WIDTH || y < 0 || y >= MAX_SCROLL_LINES)
        return 0;
    return (uint16)GLYPH_COLOUR_VALUE(scrollBuf[y * SCROLL_WIDTH + x]);
}

void macTerm::SClear() {
    int32 i;
    if (!scrollBuf)
        return;
    for (i = 0; i < MAX_SCROLL_LINES * SCROLL_WIDTH; i++)
        scrollBuf[i] = ' ';
}

void macTerm::BlitScrollLine(int16 wn, int32 buffline, int32 winline) {
    int16 i, width = min((int16)SCROLL_WIDTH, WinSizeX());

    if (!scrollBuf)
        return;
    for (i = 0; i < width; i++)
        APutChar(Windows[wn].Left + i, Windows[wn].Top + (int16)winline,
            scrollBuf[buffline * SCROLL_WIDTH + i]);
}

/*****************************************************************************\
*                                   macTerm                                   *
*                              Input Functions                                *
\*****************************************************************************/

void macTerm::PushEvent(const IncEvent &ev) {
    {
        std::lock_guard<std::mutex> lk(evLock);
        events.push_back(ev);
    }
    evReady.notify_one();
}

/* Blocks until an event arrives. engine_waiting fires before each wait, with
   no locks held, so the parity driver may push synchronously from inside it:
   the wait predicate re-checks the queue after the callback returns. */
IncEvent macTerm::NextEvent() {
    for (;;) {
        {
            std::lock_guard<std::mutex> lk(evLock);
            if (!events.empty()) {
                IncEvent ev = events.front();
                events.pop_front();
                return ev;
            }
        }
        if (cb.engine_waiting)
            cb.engine_waiting(cb.ctx);
        std::unique_lock<std::mutex> lk(evLock);
        evReady.wait(lk, [this] { return !events.empty(); });
    }
}

/* The engine thread must never run game code again, but the process must
   keep living until the UI terminates it. */
void macTerm::Park() {
    std::unique_lock<std::mutex> lk(parkLock);
    parkCV.wait(lk, [] { return false; });
}

bool macTerm::CheckEscape() {
    /* Same semantics as the window build: drain every pending input and
       report whether an ESC was among them. A queued click is typeahead
       too -- a stale pre-dialog click must not select something in a menu
       that opens later. Resize and quit stay queued. */
    std::lock_guard<std::mutex> lk(evLock);
    bool sawEsc = false;
    std::deque<IncEvent> keep;

    while (!events.empty()) {
        IncEvent ev = events.front();
        events.pop_front();
        if (ev.kind == INC_EV_KEY || ev.kind == INC_EV_WHEEL
            || ev.kind == INC_EV_MOUSE_DOWN) {
            if (ev.kind == INC_EV_KEY && ev.ch == KY_ESC)
                sawEsc = true;
        } else
            keep.push_back(ev);
    }
    events.swap(keep);
    return sawEsc;
}

void macTerm::ClearKeyBuff() {
    std::lock_guard<std::mutex> lk(evLock);
    std::deque<IncEvent> keep;

    while (!events.empty()) {
        IncEvent ev = events.front();
        events.pop_front();
        if (ev.kind != INC_EV_KEY && ev.kind != INC_EV_WHEEL
            && ev.kind != INC_EV_MOUSE_DOWN)
            keep.push_back(ev);
    }
    events.swap(keep);
}

/* Resize mid-game follows the same recovery path as the window build's
   Alt+Enter fullscreen toggle: rebuild the display, then hand the caller
   KY_REDRAW so it repaints whatever it had up. */
void macTerm::ResizeGrid(int32 w, int32 h) {
    if (w < MIN_SCREEN_W) w = MIN_SCREEN_W;
    if (h < MIN_SCREEN_H) h = MIN_SCREEN_H;
    if (w > MAX_SCREEN_W) w = MAX_SCREEN_W;
    if (h > MAX_SCREEN_H) h = MAX_SCREEN_H;
    if (w == gridX && h == gridY)
        return;

    AllocGrid(w, h);
    sizeX = (int16)w;
    sizeY = (int16)h;
    InitWindows();
    SetWin(WIN_SCREEN);

    /* Mirror libtcodTerm::Reset(): repaint what this mode owns. A dialog
       repaints itself through the KY_REDRAW the caller gets; the map under
       it is marked dirty so the first play prompt after the dialog closes
       redraws it rather than restoring a blanked underlay. */
    if (p)
        p->UpdateMap = true;
    if (theGame && theGame->InPlay() && p) {
        if (Mode == MO_PLAY) {
            ShowStatus();
            ShowTraits();
            RefreshMap();
            ShowViewList();
        } else if (Mode == MO_INV) {
            ShowStatus();
            ShowTraits();
            InvShowSlots();
        }
    }
    /* Whatever was just drawn is also the best available underlay for a
       dialog's Restore(); without this, Restore() blanks the screen. */
    memcpy(sav, scr, gridX * gridY * sizeof(Glyph));
    Update();
}

/* What every accepted input runs, keystroke or click: the refresh of dirty
   panels and the message-window clearing both backends do per key. Copied
   from the same block in Wposix's GetCharCmd. */
void macTerm::KeyHousekeeping(KeyCmdMode mode) {
    int16 ox, oy;
    TextWin *wn;

    if (Mode == MO_PLAY && p && p->UpdateMap)
        RefreshMap();
    if ((Mode == MO_PLAY || Mode == MO_INV) && p && p->statiChanged) {
        ShowTraits();
        ShowStatus();
    }

    /* Events arrive one keystroke at a time with no repeat detection, so
       clearing the message window is always safe here. */
    ClearMsgOK = true;
    if (theGame->Opt(OPT_CLEAR_EVERY_TURN) && mode == KY_CMD_NORMAL_MODE
        && GetMode() == MO_PLAY) {
        ox = cx; oy = cy; wn = activeWin;
        linenum = linepos = 0;
        SetWin(WIN_MESSAGE);
        Clear();
        activeWin = wn;
        cx = ox; cy = oy;
        ClearMsgOK = false;
    }
}

int16 macTerm::GetCharCmd(KeyCmdMode mode) {
    KeySetItem *keyset = theGame->Opt(OPT_ROGUELIKE) ? RoguelikeKeySet : StandardKeySet;
    int16 keyset_start = 0, keyset_delta = 0, keyset_last;
    int16 i, ox, oy, ch;
    TextWin *wn;

    ActionsSinceLastAutoSave++;
    if (p) p->GameTimeInfo.keystrokes++;

    if (QueuedChar) {
        ch = QueuedChar;
        QueuedChar = 0;
        return ch;
    }

    for (keyset_last = 0; keyset[keyset_last].cmd != KY_CMD_LAST; keyset_last++)
        ;
    keyset_last--;

    switch (mode) {
    case KY_CMD_NORMAL_MODE:
        keyset_start = keyset_last;
        keyset_delta = -1;
        break;
    case KY_CMD_TARGET_MODE:
    case KY_CMD_ARROW_MODE:
        keyset_start = 0;
        keyset_delta = +1;
        break;
    default:
        break;
    }

    ox = cx; oy = cy; wn = activeWin;
    if (theGame->InPlay()) {
        if (p->UpdateMap && Mode == MO_PLAY)
            RefreshMap();
        if (p->statiChanged) {
            ShowTraits();
            ShowStatus();
        }
    }

    Update();
    activeWin = wn;
    cx = ox; cy = oy;

    for (;;) {
        IncEvent ev;
        bool synthetic = false;

        /* A quit that arrived during a dialog drains it with synthetic ESC
           keypresses until the game is back at a normal prompt, where the
           ordinary save-and-quit path can run. The ESC goes through the
           SAME translation tail as a real key, because what a dialog wants
           varies: LMenu reads the raw 27, EffectPrompt the translated
           KY_CMD_ESCAPE. The budget stops a dialog that eats ESC forever.
           Under strictQuit the unquittable case is dropped instead, which
           is what Wposix does with @quit and what the parity diff must
           match. */
        if (quitPending) {
            if (!theGame || !theGame->InPlay()) {
                ShutDown();  /* notifies the UI and parks */
            }
            if (GetMode() == MO_PLAY && mode == KY_CMD_NORMAL_MODE) {
                quitPending = false;
                theGame->SetQuitFlag();
                return KY_CMD_QUICK_QUIT;
            }
            if (strictQuit) {
                quitPending = false;
            } else if (quitEscBudget-- > 0) {
                memset(&ev, 0, sizeof(ev));
                ev.kind = INC_EV_KEY;
                ev.ch = KY_ESC;
                synthetic = true;
            } else
                ShutDown();
        }

        if (!synthetic)
            ev = NextEvent();

        if (ev.kind == INC_EV_QUIT) {
            quitPending = true;
            continue;
        }
        if (ev.kind == INC_EV_RESIZE) {
            ResizeGrid(ev.x, ev.y);
            /* KY_REDRAW may only go to dialog readers. Its value collides
               with KY_CMD_DOWN (the KeyCmd enum runs through the 250s), so
               handing it to the normal-mode play loop would DESCEND STAIRS.
               In play, ResizeGrid has already repainted; just keep waiting. */
            if (mode == KY_CMD_NORMAL_MODE)
                continue;
            return KY_REDRAW;
        }
        if (ev.kind == INC_EV_WHEEL) {
            /* The wheel scrolls scrollable things only. In play the raw
               KY_UP/KY_DOWN would translate to movement commands, and a
               trackpad flick must never walk the character. */
            if (Mode != MO_DIALOG && Mode != MO_CHARVIEW && Mode != MO_HELP)
                continue;
            int32 n = ev.delta < 0 ? -ev.delta : ev.delta;
            if (n < 1)
                continue;
            /* One line now; the rest go back on the queue as keystrokes. */
            IncEvent line;
            memset(&line, 0, sizeof(line));
            line.kind = INC_EV_KEY;
            line.ch = ev.delta > 0 ? KY_UP : KY_DOWN;
            {
                std::lock_guard<std::mutex> lk(evLock);
                for (i = 1; i < n && i < 10; i++)
                    events.push_front(line);
            }
            ev = line;
        }
        if (ev.kind == INC_EV_MOUSE_DOWN) {
            mouseCX = (int16)ev.x;
            mouseCY = (int16)ev.y;
            /* In a dialog the click becomes KY_MOUSE and the prompt code
               hit-tests it (LMenu, LMultiSelect, EffectPrompt). In normal
               play a click on a square beside the player walks there.
               Everything else is ignored. */
            if (Mode == MO_DIALOG) {
                KeyHousekeeping(mode);
                ControlKeys = 0;
                return KY_MOUSE;
            }
            if (Mode == MO_PLAY && mode == KY_CMD_NORMAL_MODE && p
                && theGame->InPlay()
                && ev.x >= Windows[WIN_MAP].Left && ev.x <= Windows[WIN_MAP].Right
                && ev.y >= Windows[WIN_MAP].Top  && ev.y <= Windows[WIN_MAP].Bottom) {
                int16 mmx = (int16)ev.x - Windows[WIN_MAP].Left + XOff;
                int16 mmy = (int16)ev.y - Windows[WIN_MAP].Top  + YOff;
                int16 dx = mmx - p->x, dy = mmy - p->y;
                if ((dx || dy) && dx >= -1 && dx <= 1 && dy >= -1 && dy <= 1) {
                    /* Dir values: NORTH 0, SOUTH 1, EAST 2, WEST 3, NE 4,
                       NW 5, SE 6, SW 7 (inc/Defines.h). */
                    static const int16 dirFor[3][3] = {
                        { 5, 0, 4 },
                        { 3, -1, 2 },
                        { 7, 1, 6 },
                    };
                    int16 d = dirFor[dy + 1][dx + 1];
                    if (d >= 0) {
                        KeyHousekeeping(mode);
                        ControlKeys = 0;
                        return (int16)(KY_CMD_NORTH + d);
                    }
                }
            }
            continue;
        }
        if (ev.kind != INC_EV_KEY)
            continue;

        KeyHousekeeping(mode);

        ControlKeys = (uint8)ev.mods;
        ch = (int16)ev.ch;

        if (mode == KY_CMD_RAW)
            return ch;

        for (i = keyset_start; i >= 0 && keyset[i].cmd != KY_CMD_LAST; i += keyset_delta) {
            if (keyset[i].raw_key != toupper(ch))
                continue;
            if (keyset[i].raw_key_flags != -1)
                if (keyset[i].raw_key_flags != (ControlKeys & (CONTROL|SHIFT|ALT)))
                    continue;
            if (mode == KY_CMD_ARROW_MODE
                && (keyset[i].cmd < KY_CMD_FIRST_ARROW || keyset[i].cmd > KY_CMD_LAST_ARROW))
                continue;
            return keyset[i].cmd;
        }
        return ch;
    }
}

/*****************************************************************************\
*                                   macTerm                                   *
*                             General Functions                               *
\*****************************************************************************/

/* One line of setup around the shared logger: only the backend knows which
   build it is, and IncursionDirectory lives on the terminal object. */
static void LogGameError(const char *msg) {
    char banner[256], stamp[32];
    time_t now;

    time(&now);
    strftime(stamp, sizeof(stamp), "%Y-%m-%d %H:%M:%S", localtime(&now));
    snprintf(banner, sizeof(banner),
        "=== session %s  Incursion %s mac  built %s %s ===",
        stamp, VERSION_STRING, __DATE__, __TIME__);
    LogError((const char*)((macTerm*)T1)->IncursionDirectory, msg, banner);
}

void Fatal(const char*fmt,...) {
    va_list argptr;

    va_start(argptr, fmt);
    vsnprintf(__buffer, sizeof(__buffer), fmt, argptr);
    va_end(argptr);

    if (!T1 || !((macTerm*)T1)->initialised) {
        fprintf(stderr, "incursion: fatal: %s\n", __buffer);
        if (MT && MT->cb.fatal_error) {
            MT->cb.fatal_error(MT->cb.ctx, __buffer);
            MT->Park();
        }
        exit(1);
    }

    LogGameError(__buffer);
    fprintf(stderr, "incursion: fatal: %s\n", __buffer);
    if (MT->cb.fatal_error) {
        MT->cb.fatal_error(MT->cb.ctx, __buffer);
        MT->Park();
    }
    exit(1);
}

/* An error is logged and play goes on. This is the policy the window build
   settled on, for the same reason: a modal prompt used to freeze the game on
   a single error. INCURSION_ERROR_PROMPT is not honoured here yet; the app
   surfaces logs/errors.log instead. */
void Error(const char*fmt,...) {
    va_list argptr;

    va_start(argptr, fmt);
    vsnprintf(__buffer, sizeof(__buffer), fmt, argptr);
    va_end(argptr);

    if (!T1 || !((macTerm*)T1)->initialised) {
        fprintf(stderr, "%s\n", __buffer);
        return;
    }

    LogGameError(__buffer);
}

void macTerm::Initialize() {
    p = NULL;
    m = NULL;
    isHelp = false;
    ActionsSinceLastAutoSave = 0;
    cx = cy = 0;
    showCursor = false;
    OptionCount = 0;
    OffscreenC = 0;
    QueuedChar = 0;
    ControlKeys = 0;
    WViewListCount = 0;
    OptionsShown = false;
    XOff = YOff = 0;
    s1 = s2 = 0;
    MsgHistory[0] = 0;
    Mode = MO_SPLASH;

    if (sizeX < MIN_SCREEN_W) sizeX = MIN_SCREEN_W;
    if (sizeY < MIN_SCREEN_H) sizeY = MIN_SCREEN_H;
    if (sizeX > MAX_SCREEN_W) sizeX = MAX_SCREEN_W;
    if (sizeY > MAX_SCREEN_H) sizeY = MAX_SCREEN_H;
    AllocGrid(sizeX, sizeY);

    if (!scrollBuf) {
        scrollBuf = (Glyph*)malloc(MAX_SCROLL_LINES * SCROLL_WIDTH * sizeof(Glyph));
        SClear();
    }

    initialised = true;

    InitWindows();
    SetWin(WIN_SCREEN);
    Clear();
    Color(YELLOW);
}

/* Every path that used to exit the process instead tells the UI the game is
   over and parks this thread; the UI terminates the app. The final Update()
   publishes whatever was drawn since the last frame -- the save path writes
   its "Done." without one, and the last thing on screen should be true. */
void macTerm::ShutDown() {
    Update();
    if (cb.engine_finished)
        cb.engine_finished(cb.ctx, 0);
    Park();
}

void macTerm::SetIncursionDirectory(const char *s) {
    char tmp[MAX_PATH_LENGTH] = "";

    IncursionDirectory = (const char *)s;
    if (IncursionDirectory.Right(1) != "/")
        IncursionDirectory += "/";

    strcpy(tmp, s); strcat(tmp, "/mod");  _mkdir(tmp);
    strcpy(tmp, s); strcat(tmp, "/logs"); _mkdir(tmp);
    strcpy(tmp, s); strcat(tmp, "/save"); _mkdir(tmp);
}

/*****************************************************************************\
*                                   macTerm                                   *
*                               File I/O Code                                 *
\*****************************************************************************/

bool macTerm::Exists(const char *fn) {
    struct stat st;
    return !stat(fn, &st) && !S_ISDIR(st.st_mode);
}

void macTerm::Delete(const char *fn) {
    if (unlink(fn))
        Error("Can't delete file \"%s\".", fn);
}

void macTerm::OpenRead(const char*fn) {
    fp = fopen(fn, "rb");
    if (!fp)
        throw ENOFILE;
    CurrentFileName = fn;
}

void macTerm::OpenWrite(const char*fn) {
    fp = fopen(fn, "wb+");
    if (!fp)
        throw ENODIR;
    CurrentFileName = fn;
}

void macTerm::OpenUpdate(const char*fn) {
    fp = fopen(fn, "rb+");
    if (!fp)
        fp = fopen(fn, "wb+");
    if (!fp)
        throw ENODIR;
    CurrentFileName = fn;
}

void macTerm::Close() {
    if (fp) {
        fclose(fp);
        fp = NULL;
    }
}

void macTerm::FRead(void *vp, size_t sz) {
    if (fread(vp, 1, sz, fp) != sz)
        throw EREADERR;
}

void macTerm::FWrite(const void *vp, size_t sz) {
    if (!fp)
        return;
    if (fwrite(vp, 1, sz, fp) != sz)
        throw EWRIERR;
}

int32 macTerm::Tell() {
    return ftell(fp);
}

void macTerm::Seek(int32 pos, int8 rel) {
    if (fseek(fp, pos, rel))
        throw ECORRUPT;
}

void macTerm::Cut(int32 amt) {
    int32 start, end;
    void *block;

    start = ftell(fp);
    fseek(fp, 0, SEEK_END);
    end = ftell(fp);
    fseek(fp, start + amt, SEEK_SET);
    block = malloc(end - (start + amt));
    fread(block, end - (start + amt), 1, fp);
    fseek(fp, start, SEEK_SET);
    fwrite(block, end - (start + amt), 1, fp);
    free(block);
}

char * macTerm::MenuListFiles(const char * filespec, uint16 flags, const char * title) {
    static char persistent_retval[MAX_PATH_LENGTH];
    char *file_names[MAX_MENU_OPTIONS];
    int option_count = -1;
    struct dirent *ent;
    DIR *d;

    d = opendir(CurrentDirectory);
    if (!d) {
        Error("Problem listing files for user perusal.");
        return (char*)"";
    }
    while ((ent = readdir(d)) != NULL && option_count < MAX_MENU_OPTIONS - 1) {
        if (fnmatch(filespec, ent->d_name, 0))
            continue;
        option_count++;
        file_names[option_count] = (char *)alloca(strlen(ent->d_name) + 1);
        memcpy(file_names[option_count], ent->d_name, strlen(ent->d_name) + 1);
        LOption(file_names[option_count], option_count);
    }
    closedir(d);

    option_count = (int)LMenu(flags, title);
    if (option_count == -1)
        return NULL;
    persistent_retval[0] = '\0';
    memcpy(persistent_retval, file_names[option_count],
        strlen(file_names[option_count]) + 1);
    return persistent_retval;
}

/* FirstFile/NextFile walk a directory and leave each match open for reading,
   which is how the module loader reads every .mod in a folder. */
bool macTerm::FirstFile(char * filespec) {
    if (findDir) {
        closedir(findDir);
        findDir = NULL;
    }
    findDir = opendir(CurrentDirectory);
    if (!findDir)
        return false;
    findSpec = filespec;
    return NextFile();
}

bool macTerm::NextFile() {
    struct dirent *ent;

    if (!findDir)
        return false;

    while ((ent = readdir(findDir)) != NULL) {
        if (fnmatch(findSpec, ent->d_name, 0))
            continue;
        try {
            OpenRead(ent->d_name);
        } catch (int) {
            fp = NULL;
            continue;
        }
        ASSERT(fp);
        return true;
    }

    closedir(findDir);
    findDir = NULL;
    return false;
}

/*****************************************************************************\
*                                   macTerm                                   *
*                               The C Boundary                                *
\*****************************************************************************/

int macTerm::SnapshotAcquire(IncSnapshot *out) {
    std::lock_guard<std::mutex> lk(snapLock);
    if (!snapCells || !snapSeq)
        return 0;
    IncCell *copy = (IncCell*)malloc(snapX * snapY * sizeof(IncCell));
    memcpy(copy, snapCells, snapX * snapY * sizeof(IncCell));
    out->sizeX = snapX;
    out->sizeY = snapY;
    out->cursorX = snapCursorX;
    out->cursorY = snapCursorY;
    out->mode = snapMode;
    out->seq = snapSeq;
    out->cells = copy;
    return 1;
}

uint64_t macTerm::SnapshotSeq() {
    std::lock_guard<std::mutex> lk(snapLock);
    return snapSeq;
}

extern "C" {

int incursion_engine_main(const IncEngineConfig *cfg) {
    int retval = 0;
    char failure[MAX_PATH_LENGTH + 80];

    /* A config error must still reach the UI, or the app sits as a blank
       window that ignores every quit gesture: `finished` never goes true
       and applicationShouldTerminate keeps cancelling. */
    if (!cfg || !cfg->incursion_dir || cfg->incursion_dir[0] != '/') {
        snprintf(failure, sizeof(failure), "The engine needs an absolute "
            "game directory; got '%s'.",
            (cfg && cfg->incursion_dir) ? cfg->incursion_dir : "(null)");
        fprintf(stderr, "incursion: %s\n", failure);
        if (cfg && cfg->cb.fatal_error)
            cfg->cb.fatal_error(cfg->cb.ctx, failure);
        return 2;
    }

    /* Must be absolute AND resolved: ChangeDirectory() returns to the game
       folder by chdir()ing to IncursionDirectory, so a symlinked or dotted
       path must collapse to its real form here, once. */
    char resolvedPath[MAX_PATH_LENGTH];
    if (!realpath(cfg->incursion_dir, resolvedPath)) {
        snprintf(failure, sizeof(failure), "The game directory '%s' does "
            "not exist or cannot be resolved.", cfg->incursion_dir);
        fprintf(stderr, "incursion: %s\n", failure);
        if (cfg->cb.fatal_error)
            cfg->cb.fatal_error(cfg->cb.ctx, failure);
        return 2;
    }

    theGame = new Game();
    MT = new macTerm(cfg);
    MT->SetIncursionDirectory(resolvedPath);
    T1 = MT;
    MTpub.store(MT, std::memory_order_release);

    T1->Initialize();
    TutorialRequested = cfg->tutorial != 0;
    theGame->StartMenu();
    T1->ShutDown();  /* notifies the UI and parks; not normally reached */

    delete theGame;
    return retval;
}

void inc_push_event(const IncEvent *ev) {
    macTerm *t = MTpub.load(std::memory_order_acquire);
    if (t && ev)
        t->PushEvent(*ev);
}

int inc_snapshot_acquire(IncSnapshot *out) {
    macTerm *t = MTpub.load(std::memory_order_acquire);
    if (!t || !out)
        return 0;
    return t->SnapshotAcquire(out);
}

void inc_snapshot_release(const IncSnapshot *snap) {
    if (snap && snap->cells)
        free((void*)snap->cells);
}

uint64_t inc_snapshot_seq(void) {
    macTerm *t = MTpub.load(std::memory_order_acquire);
    return t ? t->SnapshotSeq() : 0;
}

} /* extern "C" */

#endif /* MAC_TERM */
