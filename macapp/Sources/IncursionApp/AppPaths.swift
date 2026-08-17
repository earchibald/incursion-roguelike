// See the Incursion LICENSE file for copyright information.
//
// Where the game lives on disk. The engine wants ONE writable directory it
// may chdir under freely (save/, logs/, mod/, Options.Dat); a signed .app
// cannot be that directory, so the standard home is Application Support.
//
//   INCURSIONPATH        overrides everything -- the portable-folder layout
//                        the classic release uses keeps working.
//   ~/Library/Application Support/Incursion/
//                        otherwise. The game-data module is copied in from
//                        the bundle's Resources when missing or when the
//                        bundle version changes; the module is welded to
//                        the binary that compiled it, so it must follow
//                        the app, never linger.

import CryptoKit
import Foundation

enum AppPaths {
    static func resolveGameDirectory() -> String {
        if let env = ProcessInfo.processInfo.environment["INCURSIONPATH"],
           !env.isEmpty {
            return env
        }

        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory,
                           in: .userDomainMask)[0]
            .appendingPathComponent("Incursion", isDirectory: true)
        let mod = base.appendingPathComponent("mod", isDirectory: true)
        try? fm.createDirectory(at: mod, withIntermediateDirectories: true)

        if let bundled = Bundle.main.url(forResource: "Incursion",
                                         withExtension: "Mod"),
           let data = try? Data(contentsOf: bundled) {
            let dst = mod.appendingPathComponent("Incursion.Mod")
            let stampFile = mod.appendingPathComponent(".module-version")
            // The stamp is the module's own content hash. A version string
            // would go stale the first time nobody bumped it, and the
            // module is rebuilt on every app build; a lingering old module
            // makes the engine silently reject or misread its data.
            let stamp = SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }.joined()
            let old = try? String(contentsOf: stampFile, encoding: .utf8)
            if !fm.fileExists(atPath: dst.path) || old != stamp {
                try? fm.removeItem(at: dst)
                try? fm.copyItem(at: bundled, to: dst)
                try? stamp.write(to: stampFile, atomically: true,
                                 encoding: .utf8)
            }
        }

        return base.path
    }
}
