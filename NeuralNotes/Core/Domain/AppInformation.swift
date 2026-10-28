import Foundation

/// Diagnostic text deliberately excludes account identifiers and notebook content.
public struct AppInformation: Equatable, Sendable {
    public var version: String, build: String, system: String, device: String
    public init(version: String?, build: String?, system: String, device: String) {
        self.version = version?.isEmpty == false ? version! : "—"
        self.build = build?.isEmpty == false ? build! : "—"
        self.system = system; self.device = device
    }
    public var versionLabel: String { "Versione \(version) (build \(build))" }
    public var diagnosticText: String {
        "NeuralNotes\n\(versionLabel)\niPadOS \(system)\nDispositivo: \(device)"
    }
    public static func credits(_ data: Data?) -> [String] {
        struct Credits: Decodable { var names: [String] }
        guard let data, data.count <= 32_768,
              let decoded = try? JSONDecoder().decode(Credits.self, from: data) else { return [] }
        var seen = Set<String>()
        return decoded.names.prefix(100).compactMap { raw in
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.count <= 80, !name.contains(where: { $0.isNewline }), seen.insert(name).inserted else { return nil }
            return name
        }
    }
    public static func publicLink(_ raw: String?) -> URL? {
        guard let raw, let url = URL(string: raw), url.scheme == "https", url.host?.isEmpty == false,
              url.user == nil, url.password == nil else { return nil }
        return url
    }
    public static func feedbackEmail(_ raw: String?) -> String? {
        guard let raw, raw.count <= 254, raw == raw.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.contains(where: { $0.isWhitespace || $0.isNewline }),
              raw.range(of: #"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?\.[A-Za-z]{2,}$"#, options: .regularExpression) != nil else { return nil }
        return raw
    }
    public func mailURL(email: String, problem: Bool) -> URL? {
        guard let email = Self.feedbackEmail(email) else { return nil }
        var value = URLComponents(); value.scheme = "mailto"; value.path = email
        let subject = problem ? "NeuralNotes · Segnalazione problema" : "NeuralNotes · Feedback"
        value.queryItems = [URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: "\(problem ? "Descrivi il problema e come riprodurlo:" : "Scrivi qui la tua idea:")\n\n\n\(diagnosticText)")]
        return value.url
    }
}
