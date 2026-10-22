"""Structural checks only. Does NOT compile Swift, type-check APIs or execute XCTest."""
from pathlib import Path
import argparse
import json
import plistlib
import re
import struct
import sys
import xml.etree.ElementTree as ET
import zlib

ROOT = Path(__file__).resolve().parents[1]


class OpenStepParser:
    """Small OpenStep plist reader so the committed pbxproj is checked on Windows too."""
    def __init__(self, text):
        text = re.sub(r"//[^\n]*|/\*.*?\*/", "", text, flags=re.S)
        self.tokens = re.findall(r'"(?:\\.|[^"\\])*"|[{}()=;,]|[^\s{}()=;,]+', text)
        self.index = 0

    def take(self, expected=None):
        token = self.tokens[self.index]
        self.index += 1
        if expected is not None:
            assert token == expected, (token, expected)
        return token

    def value(self):
        token = self.take()
        if token == "{":
            result = {}
            while self.tokens[self.index] != "}":
                key = self.value()
                self.take("=")
                assert key not in result, f"Duplicate key {key}"
                result[key] = self.value()
                self.take(";")
            self.take("}")
            return result
        if token == "(":
            result = []
            while self.tokens[self.index] != ")":
                result.append(self.value())
                if self.tokens[self.index] != ")":
                    self.take(",")
            self.take(")")
            return result
        return json.loads(token) if token.startswith('"') else token


def check_structure():
    parser = OpenStepParser((ROOT / "NeuralNotes.xcodeproj/project.pbxproj").read_text(encoding="utf-8"))
    project = parser.value()
    assert parser.index == len(parser.tokens)
    objects = project["objects"]
    assert objects[project["rootObject"]]["isa"] == "PBXProject"

    def refs(value):
        if isinstance(value, dict):
            for item in value.values():
                yield from refs(item)
        elif isinstance(value, list):
            for item in value:
                yield from refs(item)
        elif re.fullmatch(r"[0-9A-F]{24}", value):
            yield value

    for value in objects.values():
        for reference in refs(value):
            assert reference in objects, f"Unresolved PBX reference {reference}"
    for item in objects.values():
        if item["isa"] == "PBXFileReference" and item.get("sourceTree") == "SOURCE_ROOT":
            assert (ROOT / item["path"]).exists(), item["path"]
        if item["isa"] == "XCLocalSwiftPackageReference":
            assert (ROOT / item["relativePath"] / "Package.swift").is_file()

    targets = {item["name"]: item for item in objects.values() if item["isa"] == "PBXNativeTarget"}
    assert set(targets) == {"NeuralNotes", "NeuralNotesTests", "NeuralNotesUITests"}
    expected = {
        "NeuralNotes": {p.relative_to(ROOT).as_posix() for p in (ROOT / "NeuralNotes").rglob("*.swift")
                        if "Core" not in p.relative_to(ROOT / "NeuralNotes").parts},
        "NeuralNotesTests": {p.relative_to(ROOT).as_posix() for base in ["Tests", "NeuralNotesTests"]
                             for p in (ROOT / base).rglob("*.swift")},
        "NeuralNotesUITests": {p.relative_to(ROOT).as_posix() for p in (ROOT / "NeuralNotesUITests").rglob("*.swift")},
    }
    for name, target in targets.items():
        phases = [objects[p] for p in target["buildPhases"]]
        source = next(p for p in phases if p["isa"] == "PBXSourcesBuildPhase")
        actual = [objects[objects[b]["fileRef"]]["path"] for b in source["files"]]
        assert len(actual) == len(set(actual)), f"Duplicate sources in {name}"
        assert set(actual) == expected[name], f"Wrong target membership: {name}"
        for ident in objects[target["buildConfigurationList"]]["buildConfigurations"]:
            config = objects[ident]["buildSettings"]
            assert config["TARGETED_DEVICE_FAMILY"] == "2"
        if name != "NeuralNotes":
            assert target["dependencies"], f"Missing host dependency: {name}"
    scheme = ET.parse(ROOT / "NeuralNotes.xcodeproj/xcshareddata/xcschemes/NeuralNotes.xcscheme")
    assert len(scheme.findall("./TestAction/Testables/TestableReference")) == 2
    for item in scheme.findall(".//BuildableReference"):
        assert objects[item.attrib["BlueprintIdentifier"]]["name"] == item.attrib["BlueprintName"]
    print(f"PASS: project graph ({len(objects)} objects), source membership, local package and test scheme")

    info = plistlib.loads((ROOT / "NeuralNotes/Resources/Info.plist").read_bytes())
    assert len(info["UISupportedInterfaceOrientations~ipad"]) == 4
    assert info["UIApplicationSceneManifest"]["UIApplicationSupportsMultipleScenes"] is True
    assert info["UIBackgroundModes"] == ["audio"]
    for key in ["NSCameraUsageDescription", "NSMicrophoneUsageDescription", "NSSpeechRecognitionUsageDescription"]:
        assert info[key], f"Missing permission description: {key}"
    playground_info = plistlib.loads((ROOT / "NeuralNotes/App/PlaygroundInfo.plist").read_bytes())
    assert playground_info["UIApplicationSceneManifest"]["UIApplicationSupportsMultipleScenes"] is True
    assert playground_info["UIBackgroundModes"] == ["audio"]
    privacy = plistlib.loads((ROOT / "NeuralNotes/Resources/PrivacyInfo.xcprivacy").read_bytes())
    assert privacy["NSPrivacyTracking"] is False
    assert privacy["NSPrivacyCollectedDataTypes"] == []
    assert privacy["NSPrivacyAccessedAPITypes"][0]["NSPrivacyAccessedAPITypeReasons"] == ["CA92.1"]
    print("PASS: app Info.plist and privacy manifest parse and expected settings")

    for path in (ROOT / "NeuralNotes/Resources/Assets.xcassets").rglob("Contents.json"):
        data = json.loads(path.read_text())
        for image in data.get("images", []):
            assert (path.parent / image["filename"]).is_file()
    icon = (ROOT / "NeuralNotes/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png").read_bytes()
    assert icon[:8] == b"\x89PNG\r\n\x1a\n"
    position = 8
    while position < len(icon):
        length = struct.unpack(">I", icon[position:position + 4])[0]
        kind = icon[position + 4:position + 8]
        payload = icon[position + 8:position + 8 + length]
        checksum = struct.unpack(">I", icon[position + 8 + length:position + 12 + length])[0]
        assert zlib.crc32(kind + payload) & 0xFFFFFFFF == checksum
        if kind == b"IHDR":
            assert struct.unpack(">IIBBBBB", payload) == (1024, 1024, 8, 2, 0, 0, 0)
        position += length + 12
    print("PASS: asset catalogs and opaque RGB 1024px app icon (PNG checksums)")
    count = sum(len(re.findall(r"func test\w+\(", p.read_text(encoding="utf-8")))
                for base in ["Tests", "NeuralNotesTests", "NeuralNotesUITests"]
                for p in (ROOT / base).rglob("*.swift"))
    print(f"INFO: {count} XCTest methods present; none executed by this structural check")


def check_syntax():
    sys.path.insert(0, str(ROOT / ".verification/python-tooling"))
    from tree_sitter import Language, Parser
    import tree_sitter_swift
    parser = Parser(Language(tree_sitter_swift.language()))
    def shadowed_error_assignments(node, source, implicit_error=False):
        if node.type == "catch_block":
            implicit_error = re.match(rb"catch\s*\{", source[node.start_byte:node.end_byte]) is not None
        result = []
        if implicit_error and node.type == "assignment" and node.named_children:
            target = node.named_children[0]
            if source[target.start_byte:target.end_byte].strip() == b"error":
                result.append(node.start_point.row + 1)
        for child in node.named_children:
            result.extend(shadowed_error_assignments(child, source, implicit_error))
        return result
    def uikit_hidden_properties(node, source, view=False):
        # UIView's Objective-C property hidden is imported as isHidden. A Swift
        # stored property named hidden still collides, even if it is private.
        if node.type == "class_declaration":
            header = source[node.start_byte:node.end_byte].split(b"{", 1)[0]
            view = re.search(rb"\bclass\s+\w+\s*:\s*(?:UIView|UIControl|UILabel|UIImageView|UITextView|UIScrollView|UIButton|UIStackView|PKCanvasView)\b", header) is not None
        result = []
        if view and node.type == "property_declaration":
            declaration = source[node.start_byte:node.end_byte]
            if re.search(rb"\b(?:var|let)\s+hidden\b", declaration):
                result.append(node.start_point.row + 1)
        for child in node.named_children:
            result.extend(uikit_hidden_properties(child, source, view))
        return result
    # The old SelectionCommands failure is valid grammar but invalid Swift:
    # bare catch binds an immutable Error named error, shadowing the UI property.
    bad = b'func f() { do { try g() } catch { error = "failed" } }'
    good = b'func f() { do { try g() } catch { self.error = error.localizedDescription } }'
    assert shadowed_error_assignments(parser.parse(bad).root_node, bad)
    assert not shadowed_error_assignments(parser.parse(good).root_node, good)
    hidden_bad = b'class Overlay: UIView { private var hidden: UUID? }'
    hidden_good = b'class Overlay: UIView { private var draggedNoteID: UUID? }'
    hidden_state = b'struct State { var hidden: UUID? }; class Overlay: UIView { var state = State() }'
    assert uikit_hidden_properties(parser.parse(hidden_bad).root_node, hidden_bad)
    assert not uikit_hidden_properties(parser.parse(hidden_good).root_node, hidden_good)
    assert not uikit_hidden_properties(parser.parse(hidden_state).root_node, hidden_state)
    paths = [ROOT / "Package.swift"]
    paths += [p for base in ["NeuralNotes", "Tests", "NeuralNotesTests", "NeuralNotesUITests"]
              for p in (ROOT / base).rglob("*.swift")]
    failures = []
    for path in paths:
        source = path.read_bytes()
        tree = parser.parse(source)
        for line in shadowed_error_assignments(tree.root_node, source):
            failures.append(f"{path.relative_to(ROOT)}:{line}: assignment to implicit catch error; qualify the UI property")
        for line in uikit_hidden_properties(tree.root_node, source):
            failures.append(f"{path.relative_to(ROOT)}:{line}: hidden collides with UIKit; use a dedicated property name")
        if tree.root_node.has_error:
            def walk(node):
                if node.type == "ERROR" or node.is_missing:
                    failures.append(f"{path.relative_to(ROOT)}:{node.start_point.row + 1}: {node.type}")
                for child in node.children:
                    walk(child)
            walk(tree.root_node)
    assert not failures, "\n".join(failures)
    print(f"PASS: syntax grammar parsing of {len(paths)} Swift files (not type checking or an SDK build)")
    print("PASS: no assignment to the implicit immutable error in bare catch blocks")
    print("PASS: no stored hidden property in the checked UIKit view subclasses (not a full SDK audit)")


if __name__ == "__main__":
    arguments = argparse.ArgumentParser()
    arguments.add_argument("--swift-syntax", action="store_true")
    args = arguments.parse_args()
    check_structure()
    if args.swift_syntax:
        check_syntax()
