import Foundation

/// Plan, limits and AI credits used, as reported by the NeuralNotes gateway.
/// Plans are proposals until subscriptions are activated on the server.
public struct ManagedAccountOverview: Equatable, Sendable {
    public let displayName: String?
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

    public static func operationURL(studyURL: URL, path: String, query: [URLQueryItem] = []) -> URL? {
        guard ["account", "profile", "account/export", "account/delete"].contains(path),
              (try? ManagedAIService.configurationURL(studyURL: studyURL)) != nil,
              var parts = URLComponents(url: studyURL, resolvingAgainstBaseURL: false) else { return nil }
        parts.path = String(parts.path.dropLast("study".count)) + "platform/" + path
        parts.queryItems = query.isEmpty ? nil : query; return parts.url
    }

    public static func decode(_ data: Data) throws -> ManagedAccountOverview {
        struct Entitlement: Decodable {
            let plan: String; let dailyLimit: Int; let monthlyLimit: Int; let storageLimit: Int64
            enum CodingKeys: String, CodingKey { case plan, dailyLimit = "daily_ai_limit", monthlyLimit = "monthly_ai_limit", storageLimit = "storage_limit" }
        }
        struct Usage: Decodable { let today: Int; let month: Int }
        struct Profile: Decodable { let display_name: String }
        struct Root: Decodable { let profile: [Profile]?; let entitlements: [Entitlement]?; let usage: Usage? }
        guard data.count <= 65_536, let root = try? JSONDecoder().decode(Root.self, from: data) else { throw ManagedAIFailure.response }
        // The schema gives every new account the free plan; mirror it until the row exists.
        let entitlement = root.entitlements?.first ?? Entitlement(plan: "free", dailyLimit: 10, monthlyLimit: 100, storageLimit: 268_435_456)
        let usage = root.usage ?? Usage(today: 0, month: 0)
        guard ["free", "study", "pro", "team"].contains(entitlement.plan), (0...100_000).contains(entitlement.dailyLimit),
              (0...10_000_000).contains(entitlement.monthlyLimit), entitlement.storageLimit >= 0,
              usage.today >= 0, usage.month >= usage.today else { throw ManagedAIFailure.response }
        let name = root.profile?.first?.display_name
        if let name, !(1...80).contains(name.count) { throw ManagedAIFailure.response }
        return ManagedAccountOverview(displayName: name, plan: entitlement.plan, dailyLimit: entitlement.dailyLimit, monthlyLimit: entitlement.monthlyLimit,
                                      storageLimit: entitlement.storageLimit, usedToday: usage.today, usedThisMonth: usage.month)
    }

    public var planTitle: String {
        switch plan { case "study": return "Studio"; case "pro": return "Pro"; case "team": return "Gruppo"; default: return "Base" }
    }
    /// Credits still available now: the stricter of the daily and monthly limits.
    public var remaining: Int { max(0, min(dailyLimit - usedToday, monthlyLimit - usedThisMonth)) }
}


/// A bounded, self-scoped page of metadata, never signed URLs or authentication data.
public struct ManagedAccountExportPage: Sendable {
    public static let sections = ["profile", "entitlements", "usage", "documents", "snapshots", "resources", "hubs", "memberships", "reports", "blocks"]
    public let rows: Data
    public let count: Int
    public let nextOffset: Int?
    public static func decode(_ data: Data, userID: UUID, section: String, offset: Int) throws -> Self {
        guard sections.contains(section), (0...10_000).contains(offset), data.count <= 65_536,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["version"] as? Int == 1, let id = root["userID"] as? String, UUID(uuidString: id) == userID,
              root["section"] as? String == section, let rows = root["rows"] as? [[String: Any]], rows.count <= 10 else { throw ManagedAIFailure.response }
        let next: Int?
        if root["nextOffset"] is NSNull { next = nil } else {
            guard let value = root["nextOffset"] as? Int, value == offset + 10, value <= 10_000, rows.count == 10 else { throw ManagedAIFailure.response }
            next = value
        }
        guard next != nil || rows.count < 10 else { throw ManagedAIFailure.response }
        return Self(rows: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]), count: rows.count, nextOffset: next)
    }
}


public enum ManagedAccountExport {
    /// Writes pages directly to disk, removes interrupted exports, never overwrites a file.
    public static func write(userID: UUID, email: String?, to file: URL,
                             fetch: @Sendable (String, Int) async throws -> Data) async throws {
        guard !FileManager.default.fileExists(atPath: file.path), FileManager.default.createFile(atPath: file.path, contents: nil) else { throw ManagedAIFailure.response }
        let output = try FileHandle(forWritingTo: file); var complete = false, size = 0
        defer { try? output.close(); if !complete { try? FileManager.default.removeItem(at: file) } }
        func write(_ data: Data) throws {
            size += data.count; guard size <= 32 * 1024 * 1024 else { throw ManagedAIFailure.response }
            try output.write(contentsOf: data)
        }
        let header = try JSONSerialization.data(withJSONObject: ["version": 1, "userID": userID.uuidString,
            "email": email ?? "", "exportedAt": ISO8601DateFormatter().string(from: Date())], options: [.sortedKeys])
        try write(header.dropLast()); try write(Data(",\"sections\":{".utf8))
        for (index, section) in ManagedAccountExportPage.sections.enumerated() {
            if index > 0 { try write(Data(",".utf8)) }
            try write(Data("\"\(section)\":[".utf8)); var offset = 0, wroteRows = false
            while true {
                try Task.checkCancellation()
                let data = try await fetch(section, offset)
                let page = try ManagedAccountExportPage.decode(data, userID: userID, section: section, offset: offset)
                if page.count > 0 {
                    if wroteRows { try write(Data(",".utf8)) }
                    try write(page.rows.dropFirst().dropLast()); wroteRows = true
                }
                guard let next = page.nextOffset else { break }; offset = next
            }
            try write(Data("]".utf8))
        }
        try write(Data("}}".utf8)); try output.synchronize(); complete = true
    }
}
