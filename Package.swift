// swift-tools-version: 5.9
import PackageDescription

// Apple builds use the system CryptoKit. Linux tests use its official Swift
// Crypto counterpart; this dependency is never added to the iPad Playground.
var platformPackages: [Package.Dependency] = []
var coreDependencies: [Target.Dependency] = []
#if os(Linux)
platformPackages = [.package(url: "https://github.com/apple/swift-crypto.git", exact: "3.12.3")]
coreDependencies = [.product(name: "Crypto", package: "swift-crypto")]
#endif

let package = Package(
    name: "NeuralNotesCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "NeuralNotesCore", targets: ["NeuralNotesCore"])],
    dependencies: platformPackages,
    targets: [
        .target(name: "NeuralNotesCore", dependencies: coreDependencies, path: "NeuralNotes/Core"),
        .testTarget(name: "NeuralNotesCoreTests", dependencies: ["NeuralNotesCore"])
    ]
)
