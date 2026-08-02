import Foundation

/// Hold-to-repeat for Nav Mode keys.
///
/// The OS's own key auto-repeat is not usable here: its rate is a system
/// preference tuned for typing, and the engine swallows the repeated keyDowns
/// anyway. Instead each held key gets a fire-immediately / wait / then-repeat
/// timer, so `j` nudges the pointer once on tap and glides on hold.
@MainActor
final class Repeater {
    private var timers: [Int: [Timer]] = [:]

    /// Run `action` now, then again every `interval` after `delay`, until
    /// `stop(keyCode:)`. Starting a key that is already held is a no-op, which
    /// makes it safe to call from every keyDown including stray repeats.
    ///
    /// Timers are added to the main run loop in `.common` mode: the default mode
    /// stalls while a menu or modal event-tracking loop is running, which would
    /// freeze a hold-to-repeat glide mid-flight.
    func start(keyCode: Int, delay: TimeInterval, interval: TimeInterval, action: @escaping () -> Void) {
        guard timers[keyCode] == nil else { return }
        action()
        var group: [Timer] = []
        let delayTimer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.timers[keyCode] != nil else { return }
                let repeatTimer = Timer(timeInterval: interval, repeats: true) { _ in
                    MainActor.assumeIsolated { action() }
                }
                RunLoop.main.add(repeatTimer, forMode: .common)
                self.timers[keyCode, default: []].append(repeatTimer)
            }
        }
        RunLoop.main.add(delayTimer, forMode: .common)
        group.append(delayTimer)
        timers[keyCode] = group
    }

    func stop(keyCode: Int) {
        timers[keyCode]?.forEach { $0.invalidate() }
        timers[keyCode] = nil
    }

    /// Stop everything — called on Nav Mode exit so no timer outlives the mode.
    func stopAll() {
        for (_, group) in timers { group.forEach { $0.invalidate() } }
        timers.removeAll()
    }
}
