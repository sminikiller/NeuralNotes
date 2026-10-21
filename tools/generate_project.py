"""Reproducible Xcode project, shared test scheme and original app icon. Stdlib only.

Run from any directory: python tools/generate_project.py
No Swift source or user data is modified. No external project generator is required.
"""
from pathlib import Path
import hashlib
import json
import math
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1]


def uid(key):
    return hashlib.sha256(key.encode()).hexdigest()[:24].upper()


def quote(value):
    return json.dumps(str(value), ensure_ascii=False)


def make_project():
    objects = {}

    def add(key, value):
        ident = uid(key)
        objects[ident] = value
        return ident

    def buildfile(key, file_ref=None, product_ref=None):
        field = f"fileRef = {file_ref};" if file_ref else f"productRef = {product_ref};"
        return add("build:" + key, f"{{isa = PBXBuildFile; {field}}}")

    app_files = sorted(p.relative_to(ROOT).as_posix() for p in (ROOT / "NeuralNotes").rglob("*.swift")
                       if "Core" not in p.relative_to(ROOT / "NeuralNotes").parts)
    unit_files = sorted(p.relative_to(ROOT).as_posix() for base in ["NeuralNotesTests", "Tests"]
                        for p in (ROOT / base).rglob("*.swift"))
    ui_files = sorted(p.relative_to(ROOT).as_posix() for p in (ROOT / "NeuralNotesUITests").rglob("*.swift"))
    resource_files = ["NeuralNotes/Resources/Assets.xcassets", "NeuralNotes/Resources/PrivacyInfo.xcprivacy"]
    refs = {}
    for path in app_files + unit_files + ui_files + resource_files + ["NeuralNotes/Resources/Info.plist"]:
        kind = "sourcecode.swift" if path.endswith(".swift") else (
            "folder.assetcatalog" if path.endswith(".xcassets") else "text.plist.xml")
        refs[path] = add("file:" + path,
            f"{{isa = PBXFileReference; lastKnownFileType = {kind}; path = {quote(path)}; sourceTree = SOURCE_ROOT;}}")

    products = {}
    for target, suffix, kind in [("NeuralNotes", "app", "wrapper.application"),
                                  ("NeuralNotesTests", "xctest", "wrapper.cfbundle"),
                                  ("NeuralNotesUITests", "xctest", "wrapper.cfbundle")]:
        products[target] = add("product:" + target,
            f"{{isa = PBXFileReference; explicitFileType = {kind}; includeInIndex = 0; path = {target}.{suffix}; sourceTree = BUILT_PRODUCTS_DIR;}}")
    product_group = add("products", "{isa = PBXGroup; children = (" + ",".join(products.values()) + "); name = Products; sourceTree = \"<group>\";}")
    main_group = add("main", "{isa = PBXGroup; children = (" + ",".join(refs.values()) + "," + product_group + "); sourceTree = \"<group>\";}")
    package_ref = add("local-package", '{isa = XCLocalSwiftPackageReference; relativePath = ".";}')

    def configuration_list(key, debug, release):
        ids = []
        for name, settings in [("Debug", debug), ("Release", release)]:
            settings_string = " ".join(f"{k} = {quote(v)};" for k, v in sorted(settings.items()))
            ids.append(add(key + name, f"{{isa = XCBuildConfiguration; buildSettings = {{{settings_string}}}; name = {name};}}"))
        return add(key + "configs", "{isa = XCConfigurationList; buildConfigurations = (" + ",".join(ids) + "); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;}")

    common = {
        "SDKROOT": "iphoneos", "IPHONEOS_DEPLOYMENT_TARGET": "17.0", "SWIFT_VERSION": "5.0",
        "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES", "GCC_C_LANGUAGE_STANDARD": "gnu17",
        "SWIFT_STRICT_CONCURRENCY": "complete", "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES", "CLANG_WARN_UNREACHABLE_CODE": "YES",
    }
    project_configs = configuration_list("project", dict(common, **{
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone", "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)",
        "ENABLE_TESTABILITY": "YES", "DEBUG_INFORMATION_FORMAT": "dwarf", "ONLY_ACTIVE_ARCH": "YES",
    }), dict(common, **{
        "SWIFT_COMPILATION_MODE": "wholemodule", "SWIFT_OPTIMIZATION_LEVEL": "-O",
        "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym", "VALIDATE_PRODUCT": "YES",
    }))

    targets = []
    for target, files, product_type in [
        ("NeuralNotes", app_files, "com.apple.product-type.application"),
        ("NeuralNotesTests", unit_files, "com.apple.product-type.bundle.unit-test"),
        ("NeuralNotesUITests", ui_files, "com.apple.product-type.bundle.ui-testing"),
    ]:
        sources = [buildfile(target + p, file_ref=refs[p]) for p in files]
        source_phase = add(target + "sources", "{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (" + ",".join(sources) + "); runOnlyForDeploymentPostprocessing = 0;}")
        framework_files, package_products = [], []
        if target != "NeuralNotesUITests":
            dependency = add(target + "core", f"{{isa = XCSwiftPackageProductDependency; package = {package_ref}; productName = NeuralNotesCore;}}")
            package_products.append(dependency)
            framework_files.append(buildfile(target + "core", product_ref=dependency))
        framework_phase = add(target + "frameworks", "{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (" + ",".join(framework_files) + "); runOnlyForDeploymentPostprocessing = 0;}")
        resources = [buildfile(target + p, file_ref=refs[p]) for p in resource_files] if target == "NeuralNotes" else []
        resource_phase = add(target + "resources", "{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (" + ",".join(resources) + "); runOnlyForDeploymentPostprocessing = 0;}")
        settings = {
            "PRODUCT_NAME": "$(TARGET_NAME)", "PRODUCT_BUNDLE_IDENTIFIER": "com.neuralnotes." + target,
            "TARGETED_DEVICE_FAMILY": "2", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
            "SUPPORTS_MACCATALYST": "NO", "CODE_SIGN_STYLE": "Automatic", "DEVELOPMENT_TEAM": "64R668842U",
            "MARKETING_VERSION": "0.15.1", "CURRENT_PROJECT_VERSION": "28",
            "GENERATE_INFOPLIST_FILE": "YES", "SWIFT_EMIT_LOC_STRINGS": "YES",
        }
        if target == "NeuralNotes":
            settings.update({"GENERATE_INFOPLIST_FILE": "NO", "INFOPLIST_FILE": "NeuralNotes/Resources/Info.plist", "CODE_SIGN_ENTITLEMENTS": "NeuralNotes/Resources/NeuralNotes.entitlements",
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
                "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks"})
        else:
            settings["LD_RUNPATH_SEARCH_PATHS"] = "$(inherited) @executable_path/Frameworks @loader_path/Frameworks"
            if target == "NeuralNotesTests":
                settings.update({"TEST_HOST": "$(BUILT_PRODUCTS_DIR)/NeuralNotes.app/NeuralNotes", "BUNDLE_LOADER": "$(TEST_HOST)"})
            else:
                settings["TEST_TARGET_NAME"] = "NeuralNotes"
        configs = configuration_list(target, settings, settings)
        target_dependencies = []
        if target != "NeuralNotes":
            proxy = add(target + "proxy", f"{{isa = PBXContainerItemProxy; containerPortal = {uid('project')}; proxyType = 1; remoteGlobalIDString = {uid('target:NeuralNotes')}; remoteInfo = NeuralNotes;}}")
            target_dependencies.append(add(target + "appdependency", f"{{isa = PBXTargetDependency; target = {uid('target:NeuralNotes')}; targetProxy = {proxy};}}"))
        targets.append(add("target:" + target, f"{{isa = PBXNativeTarget; buildConfigurationList = {configs}; buildPhases = ({source_phase},{framework_phase},{resource_phase}); buildRules = (); dependencies = ({','.join(target_dependencies)}); name = {target}; packageProductDependencies = ({','.join(package_products)}); productName = {target}; productReference = {products[target]}; productType = {quote(product_type)};}}"))

    attrs = " ".join(f"{ident} = {{CreatedOnToolsVersion = 15.0;" +
        (f" TestTargetID = {targets[0]};" if ident != targets[0] else "") + "};" for ident in targets)
    add("project", f"{{isa = PBXProject; attributes = {{BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1500; TargetAttributes = {{{attrs}}};}}; buildConfigurationList = {project_configs}; compatibilityVersion = \"Xcode 14.0\"; developmentRegion = it; hasScannedForEncodings = 0; knownRegions = (it,en,Base); mainGroup = {main_group}; packageReferences = ({package_ref}); productRefGroup = {product_group}; projectDirPath = \"\"; projectRoot = \"\"; targets = ({','.join(targets)});}}")
    project = ROOT / "NeuralNotes.xcodeproj"
    project.mkdir(exist_ok=True)
    contents = "// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n"
    contents += "".join(f"\t\t{key} = {value};\n" for key, value in objects.items())
    contents += f"\t}};\n\trootObject = {uid('project')};\n}}\n"
    (project / "project.pbxproj").write_text(contents, encoding="utf-8")

    def buildable(target):
        suffix = "app" if target == "NeuralNotes" else "xctest"
        return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid("target:" + target)}" BuildableName="{target}.{suffix}" BlueprintName="{target}" ReferencedContainer="container:NeuralNotes.xcodeproj"/>'

    scheme_dir = project / "xcshareddata" / "xcschemes"
    scheme_dir.mkdir(parents=True, exist_ok=True)
    scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1500" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
    <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{buildable('NeuralNotes')}</BuildActionEntry>
  </BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables>
    <TestableReference skipped="NO">{buildable('NeuralNotesTests')}</TestableReference>
    <TestableReference skipped="NO">{buildable('NeuralNotesUITests')}</TestableReference>
  </Testables></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable('NeuralNotes')}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable('NeuralNotes')}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
    (scheme_dir / "NeuralNotes.xcscheme").write_text(scheme, encoding="utf-8")


def make_assets():
    assets = ROOT / "NeuralNotes/Resources/Assets.xcassets"
    assets.mkdir(parents=True, exist_ok=True)
    info = {"author": "xcode", "version": 1}
    (assets / "Contents.json").write_text(json.dumps({"info": info}, indent=2) + "\n")
    accent = assets / "AccentColor.colorset"
    accent.mkdir(exist_ok=True)
    colors = [{"idiom": "universal", "color": {"color-space": "srgb", "components": {
        "red": "0.090", "green": "0.420", "blue": "0.400", "alpha": "1.000"}}},
        {"idiom": "universal", "appearances": [{"appearance": "luminosity", "value": "dark"}],
         "color": {"color-space": "srgb", "components": {
             "red": "0.420", "green": "0.800", "blue": "0.740", "alpha": "1.000"}}}]
    (accent / "Contents.json").write_text(json.dumps({"colors": colors, "info": info}, indent=2) + "\n")
    icon = assets / "AppIcon.appiconset"
    icon.mkdir(exist_ok=True)
    (icon / "Contents.json").write_text(json.dumps({"images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}], "info": info}, indent=2) + "\n")

    # Original geometric mark: two open pages crossed by a rising thought stroke.
    # Opaque RGB icon; the OS supplies the corner mask.
    def segment_distance(x, y, ax, ay, bx, by):
        dx, dy = bx - ax, by - ay
        t = max(0, min(1, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy)))
        return math.hypot(x - ax - t * dx, y - ay - t * dy)

    segments = [(0.26, 0.31, 0.26, 0.69), (0.26, 0.69, 0.49, 0.76),
                (0.49, 0.76, 0.49, 0.38), (0.49, 0.38, 0.26, 0.31),
                (0.55, 0.38, 0.76, 0.31), (0.76, 0.31, 0.76, 0.69),
                (0.76, 0.69, 0.55, 0.76)]
    rows = bytearray()
    size = 1024
    for iy in range(size):
        rows.append(0)
        y = (iy + 0.5) / size
        for ix in range(size):
            x = (ix + 0.5) / size
            base = (int(23 + 9 * (1 - y)), int(66 + 34 * (1 - y)), int(67 + 27 * x))
            distance = min(segment_distance(x, y, *s) for s in segments)
            amount = max(0, min(1, (0.016 - distance) * size + 0.5))
            color = tuple(round(b * (1 - amount) + c * amount) for b, c in zip(base, (236, 245, 233)))
            sparkle = abs(x - 0.75) + abs(y - 0.22)
            if sparkle < 0.033:
                color = (208, 225, 166)
            rows.extend(color)

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(rows), 9)) + chunk(b"IEND", b"")
    (icon / "AppIcon.png").write_bytes(png)


if __name__ == "__main__":
    make_project()
    make_assets()
    print("Generated NeuralNotes.xcodeproj, shared scheme, accent and app icon.")
