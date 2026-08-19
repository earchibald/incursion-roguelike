// See the Incursion LICENSE file for copyright information.
//
// Owns the engine thread and the C boundary. The engine runs
// incursion_engine_main on a dedicated thread and blocks there for the whole
// game; the UI feeds it events and renders the snapshots it publishes.
// Callbacks arrive on the engine thread and hop to the main queue.

import AppKit
import CIncursion

struct Frame {
    var width: Int
    var height: Int
    var cursorX: Int
    var cursorY: Int
    var mode: Int
    var seq: UInt64
    var cells: [UInt32]
}

final class EngineHost {
    static let shared = EngineHost()

    /// Called on the main thread when a new frame is available.
    var onFrame: (() -> Void)?

    /// Narrator taps; called on the main thread. Strings are copied before
    /// the hop because the C buffers die when the callback returns.
    var onGameMessage: ((String) -> Void)?
    var onPlayerState: ((Data) -> Void)?

    private var thread: Thread?
    private var dirC: UnsafeMutablePointer<CChar>?

    func start(directory: String, gridW: Int32, gridH: Int32,
               tutorial: Bool = false) {
        guard thread == nil else { return }

        // The config and its strings must outlive the engine, which runs to
        // process exit; the leak here is the point.
        dirC = strdup(directory)
        var cfg = IncEngineConfig()
        cfg.incursion_dir = UnsafePointer(dirC)
        cfg.sizeX = gridW
        cfg.sizeY = gridH
        cfg.no_sleep = 0
        cfg.strict_quit = 0
        cfg.tutorial = tutorial ? 1 : 0
        cfg.cb.ctx = nil
        cfg.cb.frame_ready = { _ in
            DispatchQueue.main.async { EngineHost.shared.onFrame?() }
        }
        cfg.cb.engine_waiting = nil
        cfg.cb.game_message = { _, cLine in
            guard let cLine else { return }
            let line = String(cString: cLine)
            DispatchQueue.main.async { EngineHost.shared.onGameMessage?(line) }
        }
        cfg.cb.player_state = { _, cJson in
            guard let cJson else { return }
            let json = Data(String(cString: cJson).utf8)
            DispatchQueue.main.async { EngineHost.shared.onPlayerState?(json) }
        }
        cfg.cb.engine_finished = { _, _ in
            DispatchQueue.main.async {
                EngineHost.shared.finished = true
                NSApp.terminate(nil)
            }
        }
        cfg.cb.fatal_error = { _, msg in
            let text = msg.map { String(cString: $0) } ?? "unknown fatal error"
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.alertStyle = .critical
                alert.messageText = "Incursion hit a fatal error"
                alert.informativeText = text
                    + "\n\nDetails are in logs/errors.log in the game folder."
                alert.runModal()
                exit(1)
            }
        }

        let t = Thread {
            var c = cfg
            let rc = incursion_engine_main(&c)
            // A nonzero return means the engine died before its callbacks
            // could fire (config error). Without this the app would sit as
            // a blank window that cancels every quit gesture.
            if rc != 0 {
                DispatchQueue.main.async {
                    EngineHost.shared.finished = true
                    let alert = NSAlert()
                    alert.alertStyle = .critical
                    alert.messageText = "Incursion could not start"
                    alert.informativeText =
                        "The engine exited with code \(rc). "
                        + "Check the game directory (INCURSIONPATH?) and Console output."
                    alert.runModal()
                    NSApp.terminate(nil)
                }
            }
        }
        t.name = "IncursionEngine"
        // The engine recurses (level generation, event dispatch) far past the
        // secondary-thread default.
        t.stackSize = 32 * 1024 * 1024
        t.qualityOfService = .userInteractive
        thread = t
        t.start()
    }

    /// True once the engine has said it is done; terminate is then final.
    /// Main-thread only.
    fileprivate(set) var finished = false

    // MARK: events

    func pushKey(_ ch: Int32, mods: Int32) {
        var ev = IncEvent()
        ev.kind = Int32(INC_EV_KEY.rawValue)
        ev.ch = ch
        ev.mods = mods
        inc_push_event(&ev)
    }

    func pushMouseDown(cellX: Int32, cellY: Int32) {
        var ev = IncEvent()
        ev.kind = Int32(INC_EV_MOUSE_DOWN.rawValue)
        ev.x = cellX
        ev.y = cellY
        inc_push_event(&ev)
    }

    func pushWheel(lines: Int32) {
        var ev = IncEvent()
        ev.kind = Int32(INC_EV_WHEEL.rawValue)
        ev.delta = lines
        inc_push_event(&ev)
    }

    func pushResize(gridW: Int32, gridH: Int32) {
        var ev = IncEvent()
        ev.kind = Int32(INC_EV_RESIZE.rawValue)
        ev.x = gridW
        ev.y = gridH
        inc_push_event(&ev)
    }

    func pushQuit() {
        var ev = IncEvent()
        ev.kind = Int32(INC_EV_QUIT.rawValue)
        inc_push_event(&ev)
    }

    // MARK: frames

    func currentFrame() -> Frame? {
        var snap = IncSnapshot()
        guard inc_snapshot_acquire(&snap) != 0, let cells = snap.cells else {
            return nil
        }
        defer { inc_snapshot_release(&snap) }
        let count = Int(snap.sizeX) * Int(snap.sizeY)
        return Frame(
            width: Int(snap.sizeX),
            height: Int(snap.sizeY),
            cursorX: Int(snap.cursorX),
            cursorY: Int(snap.cursorY),
            mode: Int(snap.mode),
            seq: snap.seq,
            cells: [UInt32](UnsafeBufferPointer(start: cells, count: count))
        )
    }
}
