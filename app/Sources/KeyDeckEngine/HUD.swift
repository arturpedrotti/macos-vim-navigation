import Foundation
import AppKit
import SwiftUI

/// A row in the cheat sheet: the keys to press and what they do.
public struct HUDItem: Identifiable {
    public let id = UUID()
    public let keys: String
    public let label: String
    public init(_ keys: String, _ label: String) { self.keys = keys; self.label = label }
}

public struct HUDSection: Identifiable {
    public let id = UUID()
    public let title: String
    public let items: [HUDItem]
    public init(_ title: String, _ items: [HUDItem]) { self.title = title; self.items = items }
}

/// The on-screen feedback for Nav Mode: a small mode indicator, a transient
/// message flash, and the `?` cheat sheet.
///
/// Every window here is a non-activating panel that ignores the mouse — showing
/// the HUD must never move keyboard focus, or entering Nav Mode would yank the
/// user out of whatever app they were about to navigate.
@MainActor
public final class HUD {
    public static let shared = HUD()
    private init() {}

    private var indicator: NSPanel?
    private var sheet: NSPanel?
    private var flashPanel: NSPanel?
    private var flashWorkItem: DispatchWorkItem?

    public private(set) var isCheatSheetVisible = false

    // MARK: mode indicator

    /// Small "NAV" pill near the bottom-right of the screen the pointer is on.
    public func showIndicator(subtitle: String) {
        hideIndicator()
        let view = NSHostingView(rootView: IndicatorView(subtitle: subtitle))
        let size = CGSize(width: 168, height: 34)
        let panel = makePanel(size: size, content: view, at: indicatorOrigin(for: size))
        panel.orderFrontRegardless()
        indicator = panel
    }

    public func hideIndicator() {
        indicator?.orderOut(nil)
        indicator = nil
    }

    private func indicatorOrigin(for size: CGSize) -> CGPoint {
        // Bottom-right of the pointer's screen, in AppKit (y-up) coordinates.
        let screen = NSScreen.screens.first { $0.frame.contains(appKitPointer) } ?? NSScreen.main
        guard let f = screen?.visibleFrame else { return .zero }
        return CGPoint(x: f.maxX - size.width - 24, y: f.minY + 24)
    }

    private var appKitPointer: CGPoint { NSEvent.mouseLocation }

    // MARK: cheat sheet

    public func toggleCheatSheet(_ sections: [HUDSection]) {
        isCheatSheetVisible ? hideCheatSheet() : showCheatSheet(sections)
    }

    public func showCheatSheet(_ sections: [HUDSection]) {
        hideCheatSheet()
        let root = CheatSheetView(sections: sections)
        let view = NSHostingView(rootView: root)
        let size = view.fittingSize
        let screen = NSScreen.screens.first { $0.frame.contains(appKitPointer) } ?? NSScreen.main
        let f = screen?.visibleFrame ?? .zero
        let origin = CGPoint(x: f.midX - size.width / 2, y: f.midY - size.height / 2)
        let panel = makePanel(size: size, content: view, at: origin)
        panel.orderFrontRegardless()
        sheet = panel
        isCheatSheetVisible = true
    }

    public func hideCheatSheet() {
        sheet?.orderOut(nil)
        sheet = nil
        isCheatSheetVisible = false
    }

    // MARK: transient message

    /// Brief centered message — used when an action can't be completed (e.g. an
    /// app that won't launch), so a keypress is never silently swallowed.
    public func flash(_ message: String, duration: TimeInterval = 1.4) {
        flashWorkItem?.cancel()
        flashPanel?.orderOut(nil)

        let view = NSHostingView(rootView: FlashView(message: message))
        let size = view.fittingSize
        let screen = NSScreen.screens.first { $0.frame.contains(appKitPointer) } ?? NSScreen.main
        let f = screen?.visibleFrame ?? .zero
        let panel = makePanel(size: size, content: view,
                              at: CGPoint(x: f.midX - size.width / 2, y: f.midY - size.height / 2))
        panel.orderFrontRegardless()
        flashPanel = panel

        let work = DispatchWorkItem { [weak self] in
            self?.flashPanel?.orderOut(nil)
            self?.flashPanel = nil
        }
        flashWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    public func hideAll() {
        hideIndicator()
        hideCheatSheet()
        flashWorkItem?.cancel()
        flashPanel?.orderOut(nil)
        flashPanel = nil
    }

    // MARK: panel plumbing

    private func makePanel(size: CGSize, content: NSView, at origin: CGPoint) -> NSPanel {
        let panel = NSPanel(contentRect: CGRect(origin: origin, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        // Visible over full-screen apps and on every Space — Nav Mode has to work
        // wherever the user already is.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = content
        panel.setContentSize(size)
        panel.setFrameOrigin(origin)
        return panel
    }
}

// MARK: - Views

private struct IndicatorView: View {
    let subtitle: String
    var body: some View {
        HStack(spacing: 8) {
            Text("NAV")
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .foregroundStyle(.black)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Color.green.opacity(0.9), in: RoundedRectangle(cornerRadius: 5))
            Text(subtitle)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 12)
        .frame(width: 168, height: 34)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct FlashView: View {
    let message: String
    var body: some View {
        Text(message)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 22).padding(.vertical, 14)
            .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
            .fixedSize()
    }
}

private struct CheatSheetView: View {
    let sections: [HUDSection]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Nav Mode")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            HStack(alignment: .top, spacing: 34) {
                ForEach(columns, id: \.first?.id) { column in
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(column) { section in
                            VStack(alignment: .leading, spacing: 7) {
                                Text(section.title.uppercased())
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.4))
                                ForEach(section.items) { item in
                                    HStack(spacing: 10) {
                                        Text(item.keys)
                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                                            .foregroundStyle(.white)
                                            .frame(width: 62, alignment: .leading)
                                        Text(item.label)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.white.opacity(0.65))
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Text("? closes this  ·  esc leaves Nav Mode")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(26)
        .background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 16))
        .fixedSize()
    }

    /// Balance the sections across two columns so a long launcher list doesn't
    /// make the panel taller than the screen.
    private var columns: [[HUDSection]] {
        guard sections.count > 2 else { return [sections] }
        let split = (sections.count + 1) / 2
        return [Array(sections.prefix(split)), Array(sections.dropFirst(split))]
    }
}
