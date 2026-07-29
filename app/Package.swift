// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KeyDeck",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure logic: config model, file IO, validation. No UI — fully testable.
        .target(name: "KeyDeckCore"),
        // The native engine: event tap, Nav Mode, pointer/display/launcher
        // actions, and the on-screen HUD. No third-party dependency, no
        // Hammerspoon — this is the whole runtime.
        .target(name: "KeyDeckEngine", dependencies: ["KeyDeckCore"]),
        // SwiftUI menu-bar app that configures and hosts the engine.
        .executableTarget(name: "KeyDeck", dependencies: ["KeyDeckCore", "KeyDeckEngine"]),
        .testTarget(name: "KeyDeckCoreTests", dependencies: ["KeyDeckCore", "KeyDeckEngine"]),
    ]
)
