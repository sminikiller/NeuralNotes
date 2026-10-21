"""Build a self-contained native App Playground from the canonical app sources.

No Swift code is rewritten: the iPad build keeps Core as a separate local target.
This script verifies package structure and file equality; it does NOT compile Swift.
"""
from pathlib import Path
import hashlib
import shutil
import zipfile

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / ".verification/ipad-0.14.1/NeuralNotes.swiftpm"
MANIFEST = '''// swift-tools-version: 5.9
import PackageDescription
import AppleProductTypes

let package = Package(
    name: "NeuralNotes",
    defaultLocalization: "it",
    platforms: [.iOS("17.0")],
    products: [
        .iOSApplication(
            name: "NeuralNotes",
            targets: ["AppModule"],
            displayVersion: "0.14.1",
            bundleVersion: "26",
            appIcon: .asset("AppIcon"),
            supportedDeviceFamilies: [.pad],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ],
            capabilities: [
                .microphone(purposeString: "Registra lezioni e collega gli appunti al momento dell’audio."),
                .camera(purposeString: "Scatta foto da ritagliare e inserire nei tuoi appunti."),
                .speechRecognition(purposeString: "Trascrive sul dispositivo le registrazioni dei tuoi quaderni.")
            ],
            additionalInfoPlistContentFilePath: "AppInfo.plist"
        )
    ],
    targets: [
        .target(name: "NeuralNotesCore", path: "Core"),
        .executableTarget(
            name: "AppModule",
            dependencies: ["NeuralNotesCore"],
            path: ".",
            exclude: ["Core", "AppInfo.plist"],
            resources: [.process("Resources")]
        )
    ],
    swiftLanguageVersions: [.v5]
)
'''


def package():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    (OUTPUT / "Package.swift").write_text(MANIFEST, encoding="utf-8")
    pairs = []
    source_root = ROOT / "NeuralNotes"
    pairs.append((source_root / "App/PlaygroundInfo.plist", OUTPUT / "AppInfo.plist"))
    for source in sorted(source_root.rglob("*.swift")):
        relative = source.relative_to(source_root)
        if relative.parts[0] == "Core":
            destination = OUTPUT / relative
        else:
            destination = OUTPUT / relative
        pairs.append((source, destination))
    resources = source_root / "Resources"
    for source in resources.rglob("*"):
        if source.is_file() and source.name != "Info.plist":
            pairs.append((source, OUTPUT / "Resources" / source.relative_to(resources)))
    for source, destination in pairs:
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
        assert source.read_bytes() == destination.read_bytes(), source

    expected = {destination.resolve() for _, destination in pairs} | {(OUTPUT / "Package.swift").resolve()}
    actual = {p.resolve() for p in OUTPUT.rglob("*") if p.is_file()}
    assert actual == expected, "Unexpected stale files in generated app playground; inspect output before rebuilding."
    assert sum("@main" in p.read_text(encoding="utf-8") for p in OUTPUT.rglob("*.swift")) == 1
    assert (OUTPUT / "Core/Domain/LibraryModels.swift").is_file()
    assert (OUTPUT / "Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png").is_file()
    # Root app target follows Apple's App Playground layout. Core stays independent.
    assert 'bundle: .module' in (OUTPUT / "DesignSystem/Brand.swift").read_text()
    core_sources = {p.relative_to(OUTPUT).as_posix() for p in (OUTPUT / "Core").rglob("*.swift")}
    app_sources = {p.relative_to(OUTPUT).as_posix() for p in OUTPUT.rglob("*.swift")
                   if p.name != "Package.swift" and p.relative_to(OUTPUT).parts[0] != "Core"}
    assert core_sources and app_sources and core_sources.isdisjoint(app_sources)
    assert "App/AppController.swift" in app_sources
    assert "App/NeuralNotesApp.swift" in app_sources
    assert len(core_sources | app_sources) == sum(1 for _ in source_root.rglob("*.swift"))
    assert 'path: ".",\n            exclude: ["Core", "AppInfo.plist"]' in MANIFEST

    archive_path = ROOT / ".verification/NeuralNotes-iPad-0.14.1.zip"
    with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(OUTPUT.rglob("*")):
            if path.is_file():
                archive.write(path, "NeuralNotes.swiftpm/" + path.relative_to(OUTPUT).as_posix())
    with zipfile.ZipFile(archive_path) as archive:
        assert archive.testzip() is None
        assert len(archive.namelist()) == len(expected)
        for name in archive.namelist():
            disk = OUTPUT / name.removeprefix("NeuralNotes.swiftpm/")
            assert archive.read(name) == disk.read_bytes()
    print(f"PASS: self-contained iPad app playground ({len(pairs)} unchanged source/resource files + manifest)")
    print("PASS: archive checksums, exact file set, single entry point and resource lookup")
    print(f"ZIP: {archive_path}")
    print(f"SHA256: {hashlib.sha256(archive_path.read_bytes()).hexdigest()}")
    print("NOT RUN: Swift compilation and execution on iPad")


if __name__ == "__main__":
    package()
