import Foundation

/// Persistent license state (pure & testable). Freemium model: the app is
/// always usable; a Gumroad license unlocks Pro (unlimited launchers). The
/// app layer fills `machineID`, performs Gumroad verification, stamps
/// `firstLaunchAt` for the trial, and reads/writes this to disk.
public struct LicenseState: Codable, Equatable, Sendable {
    public var licenseKey: String?
    public var email: String?
    public var machineID: String?
    public var verifiedAt: Date?
    public var uses: Int?
    /// First app launch — start of the 14-day trial. Optional so license.json
    /// files written before trials existed still decode.
    public var firstLaunchAt: Date?

    public init(licenseKey: String? = nil, email: String? = nil, machineID: String? = nil,
                verifiedAt: Date? = nil, uses: Int? = nil, firstLaunchAt: Date? = nil) {
        self.licenseKey = licenseKey
        self.email = email
        self.machineID = machineID
        self.verifiedAt = verifiedAt
        self.uses = uses
        self.firstLaunchAt = firstLaunchAt
    }

    public static let free = LicenseState()

    public var isPro: Bool {
        guard let key = licenseKey else { return false }
        return !key.isEmpty && verifiedAt != nil
    }

    public var tier: Tier {
        Entitlements.tier(isLicensed: isPro, firstLaunch: firstLaunchAt)
    }

    /// Short status for the footer button: "Pro", "Trial · N days", or "Free".
    public func statusText() -> String {
        switch tier {
        case .pro: return "Pro"
        case .trial(let days): return "Trial · \(days) day\(days == 1 ? "" : "s")"
        case .free: return "Free"
        }
    }
}
