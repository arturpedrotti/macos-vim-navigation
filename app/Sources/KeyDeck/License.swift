import Foundation
import IOKit
import KeyDeckCore

/// Fill these after creating the Gumroad product. `productID` is the product's ID
/// (Gumroad: Product → Advanced → "product_id"); `buyURL` is its public page.
///
/// TODO(release): set the real Gumroad product ID and verify buyURL before
/// shipping — activation fails with "not configured" until then. See the
/// release checklist in the README.
enum LicenseConfig {
    static let productID = "YOUR_GUMROAD_PRODUCT_ID"
    static let buyURL = URL(string: "https://gumroad.com/l/keydeck")!
    static let maxActivations = 3
    static let reverifyAfterDays = 7.0
}

enum LicenseError: Error, LocalizedError {
    case invalid, activationLimit, network, notConfigured
    var errorDescription: String? {
        switch self {
        case .invalid: return "That license key wasn't recognized."
        case .activationLimit: return "This license has reached its activation limit."
        case .network: return "Couldn't reach the license server. Check your connection."
        case .notConfigured: return "Licensing isn't configured yet (set LicenseConfig.productID)."
        }
    }
}

/// Owns the on-disk LicenseState, the Gumroad verification call, and machine binding.
@MainActor
final class LicenseManager: ObservableObject {
    @Published private(set) var state: LicenseState

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KeyDeck", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("license.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let s = try? Self.decoder.decode(LicenseState.self, from: data) {
            state = s
        } else {
            state = .free
        }
        // Trial clock starts on the very first launch and persists forever.
        if state.firstLaunchAt == nil {
            state.firstLaunchAt = Date()
        }
        persist()
    }

    var isPro: Bool { state.isPro }
    func statusText() -> String { state.statusText() }

    /// Verify a key with Gumroad, bind it to this machine, and cache the result.
    /// `incrementUses` must be true only for a NEW activation: silent
    /// re-verification with it set would burn an activation every week and
    /// eventually lock out a legitimate user via maxActivations.
    func activate(key: String, incrementUses: Bool = true) async -> Result<Void, LicenseError> {
        guard LicenseConfig.productID != "YOUR_GUMROAD_PRODUCT_ID" else { return .failure(.notConfigured) }
        var req = URLRequest(url: URL(string: "https://api.gumroad.com/v2/licenses/verify")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        req.httpBody = Self.formEncode([
            ("product_id", LicenseConfig.productID),
            ("license_key", trimmed),
            ("increment_uses_count", incrementUses ? "true" : "false"),
        ]).data(using: .utf8)
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                // An unparseable body is a transport/server problem, never a
                // verdict on the key — .invalid would let revalidateIfStale()
                // deactivate a good license during a Gumroad outage.
                return .failure(.network)
            }
            if json["success"] as? Bool != true {
                // Only definitive negatives count as invalid: Gumroad answers
                // 404 for an unknown key, and a 2xx with success:false is an
                // explicit rejection. Anything else (429, 5xx, …) is the
                // server having a bad day, not the license.
                if status == 404 || (200...299).contains(status) {
                    return .failure(.invalid)
                }
                return .failure(.network)
            }
            let uses = json["uses"] as? Int
            if let uses, uses > LicenseConfig.maxActivations { return .failure(.activationLimit) }
            let purchase = json["purchase"] as? [String: Any]
            // Gumroad answers success=true even for refunded / charged-back /
            // lapsed purchases — those flags make the license invalid.
            if purchase?["refunded"] as? Bool == true
                || purchase?["chargebacked"] as? Bool == true
                || Self.isPresent(purchase?["subscription_cancelled_at"])
                || Self.isPresent(purchase?["subscription_failed_at"])
                || Self.isPresent(purchase?["subscription_ended_at"]) {
                return .failure(.invalid)
            }
            state.licenseKey = trimmed
            state.email = purchase?["email"] as? String
            state.verifiedAt = Date()
            state.machineID = Self.machineID()
            state.uses = uses
            persist()
            return .success(())
        } catch {
            return .failure(.network)
        }
    }

    /// Re-verify silently if the cached receipt is stale (keeps offline use
    /// working). Never increments the Gumroad uses count — this is a check,
    /// not a new activation. A definitive "invalid" (bad key, refunded,
    /// charged back) clears the Pro state; a network failure never does.
    func revalidateIfStale() async {
        guard state.isPro, let key = state.licenseKey, let at = state.verifiedAt else { return }
        guard Date().timeIntervalSince(at) > LicenseConfig.reverifyAfterDays * 86_400 else { return }
        if case .failure(.invalid) = await activate(key: key, incrementUses: false) {
            deactivate()
        }
    }

    func deactivate() {
        state.licenseKey = nil; state.email = nil; state.verifiedAt = nil; state.uses = nil
        persist()
    }

    private func persist() { try? Self.encoder.encode(state).write(to: Self.fileURL, options: .atomic) }

    /// x-www-form-urlencoded body with every value percent-encoded (RFC 3986
    /// unreserved characters only) — a key containing `&`, `=`, `+`, etc. must
    /// not be able to smuggle extra form fields into the request.
    private static func formEncode(_ fields: [(String, String)]) -> String {
        var unreserved = CharacterSet.alphanumerics
        unreserved.insert(charactersIn: "-._~")
        func enc(_ s: String) -> String {
            s.addingPercentEncoding(withAllowedCharacters: unreserved) ?? s
        }
        return fields.map { "\(enc($0.0))=\(enc($0.1))" }.joined(separator: "&")
    }

    /// True when a JSON field is present with a real (non-null) value.
    private static func isPresent(_ value: Any?) -> Bool {
        guard let value else { return false }
        return !(value is NSNull)
    }

    // MARK: machine binding

    static func machineID() -> String {
        let port: mach_port_t = kIOMainPortDefault
        let service = IOServiceGetMatchingService(port, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return "unknown" }
        defer { IOObjectRelease(service) }
        guard let cf = IORegistryEntryCreateCFProperty(service, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String else { return "unknown" }
        return cf
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted]; return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()
}
