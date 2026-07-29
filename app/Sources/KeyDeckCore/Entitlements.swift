import Foundation

/// What the user is entitled to right now.
public enum Tier: Equatable, Sendable {
    case pro
    case trial(daysLeft: Int)
    case free
}

/// Freemium model: 14-day unlimited trial, then free forever within the
/// launcher cap; a Pro license lifts the cap. The core product (NAV MODE,
/// display switching, the capped launchers) never stops working.
public enum Entitlements {
    public static let freeMaxLaunchers = 3
    public static let trialDays = 14

    public static func tier(isLicensed: Bool, firstLaunch: Date?, now: Date = Date()) -> Tier {
        if isLicensed { return .pro }
        guard let start = firstLaunch else { return .trial(daysLeft: trialDays) }
        let daysUsed = Int(now.timeIntervalSince(start) / 86_400)
        let left = trialDays - daysUsed
        return left > 0 ? .trial(daysLeft: left) : .free
    }

    /// May the user add another launcher? The cap only blocks ADDING — a config
    /// already over the cap keeps working.
    public static func canAddLauncher(currentCount: Int, tier: Tier) -> Bool {
        switch tier {
        case .pro, .trial: return true
        case .free: return currentCount < freeMaxLaunchers
        }
    }
}
