// macOS-only evidence check. Not shipped in the app or the App Playground.
import Foundation
import Vision

guard CommandLine.arguments.count == 2 else {
    fatalError("Pass the simulator screenshot path")
}
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.recognitionLanguages = ["it-IT", "en-US"]
request.usesCPUOnly = true
try VNImageRequestHandler(url: URL(fileURLWithPath: CommandLine.arguments[1])).perform([request])
let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
for line in lines { print(line) }
let text = lines.joined(separator: "\n").lowercased()
let ready = ["la tua libreria", "la prossima idea parte da qui", "crea un quaderno", "guida rapida", "uno spazio per pensare"]
    .contains { text.contains($0) }
let blocked = text.contains("apertura libreria") || text.contains("libreria non disponibile")
guard ready && !blocked else { exit(1) }
