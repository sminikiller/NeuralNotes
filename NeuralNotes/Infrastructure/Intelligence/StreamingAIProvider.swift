import Foundation
import NeuralNotesCore

private struct StudyStreamEvent: Decodable {
    let type: String
    let text: String?
    let artifact: AIArtifact?
    let code: String?
}
extension RemoteAIProvider {
    @MainActor
    func generateStreaming(_ request: AIRequest, onDelta: @MainActor (String) -> Void) async throws -> AIArtifact {
        guard endpoint.scheme == "https", endpoint.host != nil, !sessionToken.isEmpty else { throw AIConnectionFailure.configuration }
        var call = URLRequest(url: endpoint); call.httpMethod = "POST"; call.timeoutInterval = 90
        call.setValue("application/json", forHTTPHeaderField: "Content-Type")
        call.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")
        call.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization"); call.httpBody = try JSONEncoder().encode(request)
        let configuration = URLSessionConfiguration.ephemeral; configuration.httpShouldSetCookies = false; configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: call)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw AIConnectionFailure.backend("Connessione AI non disponibile o non autorizzata. Controlla endpoint e token.") }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let streaming = http.value(forHTTPHeaderField: "Content-Type")?.contains("application/x-ndjson") == true
        var line = Data(), total = 0, shown = 0
        for try await byte in bytes {
            try Task.checkCancellation(); total += 1
            guard total <= 2 * 1024 * 1024 else { throw AIConnectionFailure.response }
            if streaming && byte == 10 {
                if line.isEmpty { continue }
                let event = try decoder.decode(StudyStreamEvent.self, from: line); line.removeAll(keepingCapacity: true)
                if event.type == "delta", let delta = event.text {
                    shown += delta.count; guard shown <= 100_000 else { throw AIConnectionFailure.response }; onDelta(delta)
                } else if event.type == "result", let result = event.artifact { return try validated(result, request: request) }
                else if event.type == "error" { throw AIConnectionFailure.backend("Risposta interrotta: \(event.code ?? "servizio non disponibile"). Puoi riprovare.") }
            } else { line.append(byte) }
        }
        if !streaming { return try validated(decoder.decode(AIArtifact.self, from: line), request: request) }
        throw AIConnectionFailure.response
    }
    private func validated(_ artifact: AIArtifact, request: AIRequest) throws -> AIArtifact {
        let allowed = request.sources.map(\.reference)
        guard !artifact.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, artifact.text.count <= 100_000,
              !artifact.references.isEmpty, artifact.references.allSatisfy({ allowed.contains($0) }) else { throw AIConnectionFailure.invalidCitation }
        return artifact
    }
}
