// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NeuralNotesCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "NeuralNotesCore", targets: ["NeuralNotesCore"])],
    targets: [
        .target(name: "NeuralNotesCore", path: "NeuralNotes/Core"),
        .testTarget(name: "NeuralNotesCoreTests", dependencies: ["NeuralNotesCore"])
    ]
)
