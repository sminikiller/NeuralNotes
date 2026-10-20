import Foundation
import Observation
import SwiftUI
import os

/// Local record of the last transcription blocks: method, time, recognized
/// characters, free memory and error. Shown in Audio and in Verifica sul
/// dispositivo so a stopped transcription can be diagnosed; never sent anywhere.
@MainActor @Observable
final class TranscriptionLog {
    static let shared = TranscriptionLog()
    struct Entry: Codable, Identifiable, Equatable {
        var id = UUID()
        var date = Date()
        var block: String
        var method: String
        var seconds: Double
        var characters: Int
        var freeMemoryMB: Int?
        var error: String?
    }
    private(set) var entries: [Entry] = []
    private let file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent("NeuralNotesDiagnostics", isDirectory: true).appendingPathComponent("transcription-log.json")

    init() {
        if let file, let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = Array(saved.suffix(200))
        }
    }

    func add(block: String, method: String, seconds: Double, characters: Int, error: String?) {
        let free = os_proc_available_memory()
        entries.append(Entry(block: block, method: method, seconds: seconds.isFinite ? max(0, seconds) : 0, characters: characters,
            freeMemoryMB: free > 0 ? free / 1_048_576 : nil, error: error))
        if entries.count > 200 { entries.removeFirst(entries.count - 200) }
        persist()
    }

    func clear() { entries = []; persist() }

    func line(_ entry: Entry) -> String {
        var parts = [entry.date.formatted(date: .omitted, time: .standard), entry.block, entry.method,
                     String(format: "%.1f s", entry.seconds), "\(entry.characters) caratteri"]
        if let free = entry.freeMemoryMB { parts.append("\(free) MB liberi") }
        if let error = entry.error { parts.append("ERRORE: \(error)") }
        return parts.joined(separator: " · ")
    }

    var report: String {
        entries.isEmpty ? "Nessun blocco registrato." : entries.map(line).joined(separator: "\n")
    }

    private func persist() {
        guard let file else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: file, options: .atomic) }
    }
}

@MainActor
struct TranscriptionLogView: View {
    var limit = 8
    private let log = TranscriptionLog.shared
    var body: some View {
        if log.entries.isEmpty {
            Text("Nessun blocco registrato.").font(.caption).foregroundStyle(.secondary)
        } else {
            ForEach(log.entries.suffix(limit).reversed()) { entry in
                Text(log.line(entry)).font(.caption2)
                    .foregroundStyle(entry.error == nil ? Color.secondary : Color.red)
                    .textSelection(.enabled)
            }
            ShareLink("Condividi registro", item: log.report)
            Button("Svuota registro", role: .destructive) { log.clear() }
        }
    }
}
