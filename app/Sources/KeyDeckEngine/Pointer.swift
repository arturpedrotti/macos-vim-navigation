import Foundation
import AppKit
import CoreGraphics

/// Every synthetic pointer action the engine performs: move, scroll, click.
///
/// Coordinates here are Core Graphics "global display" coordinates (origin at
/// the top-left of the main display, y growing downward) — the space
/// `CGEvent.location` and `CGWarpMouseCursorPosition` both use. `Displays`
/// converts AppKit's flipped `NSScreen` frames into this space, so nothing
/// outside these two files has to think about it.
public enum Pointer {
    public static var location: CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    public static func move(to point: CGPoint) {
        let clamped = Displays.clampToVisibleScreens(point)
        CGWarpMouseCursorPosition(clamped)
        // Warping alone leaves apps thinking the pointer never moved (no
        // hover/tracking updates). Re-associating the cursor and posting a
        // mouseMoved event makes hover states follow the pointer.
        CGAssociateMouseAndMouseCursorPosition(1)
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                mouseCursorPosition: clamped, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    /// Move by a fraction of the *current* screen's size — so the same keystroke
    /// travels a proportional distance on a laptop panel and a 5K display.
    public static func move(byFractionX xf: CGFloat, y yf: CGFloat) {
        let p = location
        let frame = Displays.screenFrame(containing: p) ?? Displays.mainFrame
        move(to: CGPoint(x: p.x + frame.width * xf, y: p.y + frame.height * yf))
    }

    /// Scroll at the pointer. `dy > 0` scrolls content *up* (like a wheel push
    /// away from you) regardless of the user's natural-scrolling setting —
    /// CGEvent scroll wheel deltas are already in the system's logical space.
    public static func scroll(dx: Int32 = 0, dy: Int32 = 0) {
        guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                              wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0)
        else { return }
        e.post(tap: .cghidEventTap)
    }

    /// Click `count` times at the pointer, setting the click-state field so the
    /// receiving app sees a genuine double/triple click (word/line selection).
    public static func click(button: CGMouseButton = .left, count: Int = 1) {
        let p = location
        let (down, up): (CGEventType, CGEventType) =
            button == .left ? (.leftMouseDown, .leftMouseUp) : (.rightMouseDown, .rightMouseUp)
        for i in 1...max(1, count) {
            let d = CGEvent(mouseEventSource: nil, mouseType: down, mouseCursorPosition: p, mouseButton: button)
            d?.setIntegerValueField(.mouseEventClickState, value: Int64(i))
            d?.post(tap: .cghidEventTap)
            let u = CGEvent(mouseEventSource: nil, mouseType: up, mouseCursorPosition: p, mouseButton: button)
            u?.setIntegerValueField(.mouseEventClickState, value: Int64(i))
            u?.post(tap: .cghidEventTap)
        }
    }
}
