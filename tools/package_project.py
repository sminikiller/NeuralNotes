"""Package only tracked-intended project files, never local tooling, Git or user data."""
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
EXCLUDED = {".git", ".verification", ".build", ".swiftpm", "DerivedData", "__pycache__", "xcuserdata", "node_modules"}


def package():
    destination = ROOT / ".verification/NeuralNotes-Sorgenti-0.15.1.zip"
    destination.parent.mkdir(exist_ok=True)
    files = [p for p in ROOT.rglob("*") if p.is_file()
             and not EXCLUDED.intersection(p.relative_to(ROOT).parts)
             and p.suffix not in {".pyc", ".xcuserstate"}
             and p.name != ".env" and not p.name.startswith(".env.")]
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(files):
            archive.write(path, "NeuralNotes/" + path.relative_to(ROOT).as_posix())
    with zipfile.ZipFile(destination) as archive:
        assert archive.testzip() is None
        assert "NeuralNotes/NeuralNotes.xcodeproj/project.pbxproj" in archive.namelist()
        assert "NeuralNotes/Package.swift" in archive.namelist()
        expected = {"NeuralNotes/" + p.relative_to(ROOT).as_posix(): p for p in files}
        assert set(archive.namelist()) == set(expected)
        for name, path in expected.items():
            assert archive.read(name) == path.read_bytes(), name
    print(f"Packaged {len(files)} files: {destination}")


if __name__ == "__main__":
    package()
