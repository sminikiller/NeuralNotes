import Foundation

/// Plan, limits and AI credits used, as reported by the NeuralNotes gateway.
/// Plans are proposals until subscriptions are activated on the server.
public struct ManagedAccountOverview: Equatable, Sendable {
    public let plan: String
    public let dailyLimit: Int
    public let monthlyLimit: Int
    public let storageLimit: Int64
    public let usedToday: Int
    public let usedThisMonth: Int

    public static func accountURL(studyURL: URL) -> URL? {
        guard studyURL.scheme == "https", studyURL.host?.isEmpty == false, studyURL.path.hasSuffix("/v1/study"),
              studyURL.query == nil, studyURL.user == nil, var parts = URLComponents(url: studyURL, resolvingAgainstBaseURL: false) else { return nil }
        parts.path = String(parts.path.dropLast("study".count)) + "platform/account"; return parts.url
    }

    public static func decode(_ data: Data) throws -> ManagedAccountOverview {
        struct Entitlement: Decodable {
            let plan: String; let dailyLimit: Int; let monthlyLimit: Int; let storageLimit: Int64
            enum CodingKeys: String, CodingKey { case plan, dailyLimit = "daily_ai_limit", monthlyLimit = "monthly_ai_limit", storageLimit = "storage_limit" }
        }
        struct Usage: Decodable { let today: Int; let month: Int }
        struct Root: Decodable { let entitlements: [Entitlement]?; let usage: Usage? }
        guard data.count <= 65_536, let root = try? JSONDecoder().decode(Root.self, from: data) else { throw ManagedAIFailure.response }
        // The schema gives every new account the free plan; mirror it until the row exists.
        let entitlement = root.entitlements?.first ?? Entitlement(plan: "free", dailyLimit: 10, monthlyLimit: 100, storageLimit: 268_435_456)
        let usage = root.usage ?? Usage(today: 0, month: 0)
        guard ["free", "study", "pro", "team"].contains(entitlement.plan), (0...100_000).contains(entitlement.dailyLimit),
              (0...10_000_000).contains(entitlement.monthlyLimit), entitlement.storageLimit >= 0,
              usage.today >= 0, usage.month >= usage.today else { throw ManagedAIFailure.response }
        return ManagedAccountOverview(plan: entitlement.plan, dailyLimit: entitlement.dailyLimit, monthlyLimit: entitlement.monthlyLimit,
                                      storageLimit: entitlement.storageLimit, usedToday: usage.today, usedThisMonth: usage.month)
    }

    public var planTitle: String {
        switch plan { case "study": return "Studio"; case "pro": return "Pro"; case "team": return "Gruppo"; default: return "Base" }
    }
    /// Credits still available now: the stricter of the daily and monthly limits.
    public var remaining: Int { max(0, min(dailyLimit - usedToday, monthlyLimit - usedThisMonth)) }
}
