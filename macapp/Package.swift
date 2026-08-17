// swift-tools-version:5.9
// See the Incursion LICENSE file for copyright information.
//
// The native macOS app. The engine comes in as a static library built by
// the repo's build script -- run, from the repo root:
//
//     BACKEND=mac ./build_macos.sh
//
// then build here (DEVELOPER_DIR may be needed; see docs):
//
//     swift build
//
// The -L path is relative to this package directory. The library carries
// C++ objects, so libc++ links alongside it, and zlib is the engine's own
// save/module compression.
import PackageDescription
import Foundation

// Which engine archive to link: the developer library by default, or the
// shipping one (no resource compiler, no GPL ACCENT code) when the bundle
// script sets INCURSION_ENGINE_LIB=incursion-mac-ship.
let engineLib = ProcessInfo.processInfo.environment["INCURSION_ENGINE_LIB"]
    ?? "incursion-mac"

let package = Package(
    name: "IncursionApp",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CIncursion"),
        .executableTarget(
            name: "IncursionApp",
            dependencies: ["CIncursion"],
            linkerSettings: [
                .unsafeFlags(["-L../build"]),
                .linkedLibrary(engineLib),
                .linkedLibrary("c++"),
                .linkedLibrary("z"),
            ]
        ),
    ]
)
