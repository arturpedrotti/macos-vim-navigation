import Foundation
import AppKit
import CoreGraphics

/// Multi-display geometry, in Core Graphics coordinates.
///
/// AppKit hands out `NSScreen.frame` with the origin at the *bottom*-left of the
/// primary screen and y growing upward; CGEvent/CGWarp use the top-left with y
/// growing downward. Every frame this type returns is already converted, so the
/// rest of the engine only ever deals with one coordinate space.
public enum Displays {
    /// Height of the primary screen — the pivot for the y-axis flip.
    private static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    private static func cgFrame(_ screen: NSScreen) -> CGRect {
        let f = screen.frame
        return CGRect(x: f.origin.x, y: primaryHeight - f.origin.y - f.height,
                      width: f.width, height: f.height)
    }

    public static var mainFrame: CGRect {
        NSScreen.main.map(cgFrame) ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    /// Physical screens, left-to-right. Names matching any `|`-separated token in
    /// `skipPattern` are treated as virtual (BetterDisplay and friends create
    /// screens the user never actually looks at, and cycling into one is a
    /// pointer that seems to vanish).
    public static func physicalScreens(skipPattern: String) -> [NSScreen] {
        let tokens = skipPattern.split(separator: "|").map(String.init).filter { !$0.isEmpty }
        return NSScreen.screens
            .filter { screen in
                let name = screen.localizedName
                return !tokens.contains { name.localizedCaseInsensitiveContains($0) }
            }
            .sorted { $0.frame.origin.x < $1.frame.origin.x }
    }

    public static func frame(of screen: NSScreen) -> CGRect { cgFrame(screen) }

    public static func center(of screen: NSScreen) -> CGPoint {
        let f = cgFrame(screen)
        return CGPoint(x: f.midX, y: f.midY)
    }

    public static func screenFrame(containing point: CGPoint) -> CGRect? {
        NSScreen.screens.map(cgFrame).first { $0.contains(point) }
    }

    /// Index of the screen the pointer is on within `screens`, or 0.
    public static func indexOfPointer(in screens: [NSScreen]) -> Int {
        let p = Pointer.location
        return screens.firstIndex { cgFrame($0).contains(p) } ?? 0
    }

    /// Move the pointer to the center of the next (or previous) physical screen,
    /// wrapping around.
    public static func cycle(by offset: Int, skipPattern: String) {
        let screens = physicalScreens(skipPattern: skipPattern)
        guard screens.count > 1 else { return }
        let i = indexOfPointer(in: screens)
        let next = ((i + offset) % screens.count + screens.count) % screens.count
        Pointer.move(to: center(of: screens[next]))
    }

    /// Center the pointer on the Nth physical screen (1-based), optionally
    /// clicking to move keyboard focus there too.
    public static func jump(to index: Int, click: Bool, skipPattern: String) {
        let screens = physicalScreens(skipPattern: skipPattern)
        guard index >= 1, index <= screens.count else { return }
        Pointer.move(to: center(of: screens[index - 1]))
        if click {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { Pointer.click() }
        }
    }

    /// Keep a point inside some screen. Warping off-screen strands the pointer
    /// where the user can't see it, which feels like a crash.
    public static func clampToVisibleScreens(_ point: CGPoint) -> CGPoint {
        let frames = NSScreen.screens.map(cgFrame)
        guard !frames.isEmpty else { return point }
        if frames.contains(where: { $0.contains(point) }) { return point }
        // Snap into whichever screen's frame is nearest.
        let nearest = frames.min { a, b in
            distance(from: point, to: a) < distance(from: point, to: b)
        } ?? frames[0]
        return CGPoint(x: min(max(point.x, nearest.minX + 1), nearest.maxX - 1),
                       y: min(max(point.y, nearest.minY + 1), nearest.maxY - 1))
    }

    private static func distance(from p: CGPoint, to r: CGRect) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX)
        let dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return dx * dx + dy * dy
    }
}
