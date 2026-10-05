import os, json, zlib, struct, math, hashlib

import sys
ROOT = sys.argv[1]
APP = os.path.join(ROOT, "CameraOverlay")

# ---------- Info.plist / entitlements ----------
info = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>$(DEVELOPMENT_LANGUAGE)</string>
	<key>CFBundleDisplayName</key>
	<string>Camera Overlay</string>
	<key>CFBundleExecutable</key>
	<string>$(EXECUTABLE_NAME)</string>
	<key>CFBundleIconName</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$(PRODUCT_NAME)</string>
	<key>CFBundlePackageType</key>
	<string>$(PRODUCT_BUNDLE_PACKAGE_TYPE)</string>
	<key>CFBundleShortVersionString</key>
	<string>$(MARKETING_VERSION)</string>
	<key>CFBundleVersion</key>
	<string>$(CURRENT_PROJECT_VERSION)</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.video</string>
	<key>LSMinimumSystemVersion</key>
	<string>$(MACOSX_DEPLOYMENT_TARGET)</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSCameraUsageDescription</key>
	<string>This app uses the camera to display a floating webcam overlay.</string>
	<key>NSHumanReadableCopyright</key>
	<string></string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
"""
open(os.path.join(APP, "Info.plist"), "w").write(info)

ent = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.device.camera</key>
	<true/>
</dict>
</plist>
"""
open(os.path.join(APP, "CameraOverlay.entitlements"), "w").write(ent)

# ---------- Assets ----------
assets = os.path.join(APP, "Resources", "Assets.xcassets")
os.makedirs(os.path.join(assets, "AppIcon.appiconset"), exist_ok=True)
os.makedirs(os.path.join(assets, "AccentColor.colorset"), exist_ok=True)
json.dump({"info": {"author": "xcode", "version": 1}}, open(os.path.join(assets, "Contents.json"), "w"), indent=2)
json.dump({"colors": [{"color": {"color-space": "srgb", "components": {"alpha": "1.000", "red": "0.270", "green": "0.850", "blue": "0.790"}}, "idiom": "universal"}],
           "info": {"author": "xcode", "version": 1}}, open(os.path.join(assets, "AccentColor.colorset", "Contents.json"), "w"), indent=2)

def png(path, size, pixels):
    raw = b"".join(b"\x00" + bytes(pixels[y*size*4:(y+1)*size*4]) for y in range(size))
    def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    open(path, "wb").write(data)

def clamp(v): return max(0.0, min(1.0, v))

def render(size):
    px = bytearray(size * size * 4)
    s = size / 1024.0
    inset, rad = 100 * s, 185 * s   # macOS icon grid: 824pt body, ~185 radius
    cx = cy = size / 2
    ring_r, ring_w = 250 * s, 34 * s
    for y in range(size):
        for x in range(size):
            fx, fy = x + 0.5, y + 0.5
            # rounded-rect signed distance
            qx = abs(fx - cx) - (size / 2 - inset - rad)
            qy = abs(fy - cy) - (size / 2 - inset - rad)
            d = math.hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - rad
            a_body = clamp(0.5 - d)
            if a_body <= 0:
                continue
            t = fy / size
            r, g, b = 0.10 - 0.03 * t, 0.12 - 0.03 * t, 0.13 - 0.03 * t
            dist = math.hypot(fx - cx, fy - cy)
            # camera bubble fill
            a_fill = clamp(ring_r - dist + 0.5)
            r, g, b = r + (0.17 - r) * a_fill, g + (0.21 - g) * a_fill, b + (0.22 - b) * a_fill
            # teal ring
            a_ring = clamp(ring_w / 2 - abs(dist - ring_r) + 0.5)
            r, g, b = r + (0.27 - r) * a_ring, g + (0.85 - g) * a_ring, b + (0.79 - b) * a_ring
            # little person glyph: head + shoulders
            hd = math.hypot(fx - cx, fy - (cy - 55 * s))
            a_head = clamp(62 * s - hd + 0.5) * (1 - a_ring)
            sd = math.hypot((fx - cx) / 1.25, fy - (cy + 150 * s))
            a_sh = clamp(120 * s - sd + 0.5) * clamp(ring_r - ring_w / 2 - dist + 0.5)
            a_p = max(a_head, a_sh)
            r, g, b = r + (0.85 - r) * a_p, g + (0.93 - g) * a_p, b + (0.92 - b) * a_p
            i = (y * size + x) * 4
            px[i:i+4] = bytes([int(r * 255), int(g * 255), int(b * 255), int(a_body * 255)])
    return px

images = []
cache = {}
for pt in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        px_size = pt * scale
        name = f"icon_{pt}x{pt}{'@2x' if scale == 2 else ''}.png"
        if px_size not in cache:
            cache[px_size] = render(px_size)
        png(os.path.join(assets, "AppIcon.appiconset", name), px_size, cache[px_size])
        images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{pt}x{pt}"})
json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, open(os.path.join(assets, "AppIcon.appiconset", "Contents.json"), "w"), indent=2)

# ---------- project.pbxproj ----------
def oid(name):
    return hashlib.md5(name.encode()).hexdigest()[:24].upper()

groups = {
    "App": ["AppDelegate.swift"],
    "Camera": ["CameraCaptureManager.swift", "CameraDeviceManager.swift", "CameraPermission.swift"],
    "Overlay": ["CameraOverlayController.swift", "CameraOverlayPanel.swift", "CameraOverlayView.swift", "OverlayPlaceholderView.swift"],
    "Shapes": ["CameraShape.swift"],
    "Tracking": ["FaceTracker.swift"],
    "Settings": ["SettingsWindowController.swift", "SettingsView.swift", "SettingsComponents.swift", "CameraSettingsView.swift",
                 "ShapeSettingsView.swift", "LookSettingsView.swift", "FramingSettingsView.swift", "FaceTrackingSettingsView.swift"],
    "MenuBar": ["MenuBarController.swift", "LaunchAtLogin.swift"],
    "Persistence": ["AppSettings.swift"],
}
for g, files in groups.items():
    for f in files:
        assert os.path.exists(os.path.join(APP, g, f)), f

P = oid("project"); MAIN = oid("maingroup"); PRODUCTS = oid("products"); APPG = oid("appgroup"); RES = oid("resources")
TARGET = oid("target"); PRODUCT = oid("product.app")
SRC_PHASE = oid("phase.sources"); FW_PHASE = oid("phase.frameworks"); RES_PHASE = oid("phase.resources")
PCL = oid("project.configlist"); TCL = oid("target.configlist")
PDBG = oid("project.debug"); PREL = oid("project.release"); TDBG = oid("target.debug"); TREL = oid("target.release")
ASSETS_REF = oid("ref.assets"); ASSETS_BUILD = oid("build.assets")
INFO_REF = oid("ref.info"); ENT_REF = oid("ref.entitlements")

file_refs, build_files, group_sections, sources = [], [], [], []
for g, files in groups.items():
    children = []
    for f in files:
        r, b = oid("ref." + g + f), oid("build." + g + f)
        file_refs.append(f'\t\t{r} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {f}; sourceTree = "<group>"; }};')
        build_files.append(f'\t\t{b} /* {f} in Sources */ = {{isa = PBXBuildFile; fileRef = {r} /* {f} */; }};')
        sources.append(f'\t\t\t\t{b} /* {f} in Sources */,')
        children.append(f'\t\t\t\t{r} /* {f} */,')
    gid = oid("group." + g)
    group_sections.append((gid, g, children))

file_refs += [
    f'\t\t{ASSETS_REF} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; }};',
    f'\t\t{INFO_REF} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};',
    f'\t\t{ENT_REF} /* CameraOverlay.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = CameraOverlay.entitlements; sourceTree = "<group>"; }};',
    f'\t\t{PRODUCT} /* CameraOverlay.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = CameraOverlay.app; sourceTree = BUILT_PRODUCTS_DIR; }};',
]
build_files.append(f'\t\t{ASSETS_BUILD} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {ASSETS_REF} /* Assets.xcassets */; }};')

def group(gid, name, children, path=True):
    p = f"\t\t\tpath = {name};\n" if path else f"\t\t\tname = {name};\n"
    return (f"\t\t{gid} /* {name} */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n" + "\n".join(children) +
            f"\n\t\t\t);\n{p}\t\t\tsourceTree = \"<group>\";\n\t\t}};")

group_text = []
group_text.append(f"\t\t{MAIN} = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{APPG} /* CameraOverlay */,\n\t\t\t\t{PRODUCTS} /* Products */,\n\t\t\t);\n\t\t\tsourceTree = \"<group>\";\n\t\t}};")
group_text.append(group(APPG, "CameraOverlay", [f"\t\t\t\t{gid} /* {g} */," for gid, g, _ in group_sections] +
                        [f"\t\t\t\t{RES} /* Resources */,", f"\t\t\t\t{INFO_REF} /* Info.plist */,", f"\t\t\t\t{ENT_REF} /* CameraOverlay.entitlements */,"]))
for gid, g, children in group_sections:
    group_text.append(group(gid, g, children))
group_text.append(group(RES, "Resources", [f"\t\t\t\t{ASSETS_REF} /* Assets.xcassets */,"]))
group_text.append(f"\t\t{PRODUCTS} /* Products */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{PRODUCT} /* CameraOverlay.app */,\n\t\t\t);\n\t\t\tname = Products;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};")

def settings_block(d):
    out = []
    for k in sorted(d):
        v = d[k]
        if isinstance(v, list):
            out.append(f"\t\t\t\t{k} = (\n" + "".join(f"\t\t\t\t\t{x},\n" for x in v) + "\t\t\t\t);")
        else:
            out.append(f"\t\t\t\t{k} = {v};")
    return "\n".join(out)

common = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ANALYZER_NONNULL": "YES",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
    "COPY_PHASE_STRIP": "NO",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "GCC_NO_COMMON_BLOCKS": "YES",
    "MACOSX_DEPLOYMENT_TARGET": "13.0",
    "SDKROOT": "macosx",
    "SWIFT_VERSION": "5.0",
}
pdebug = dict(common, **{
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_TESTABILITY": "YES",
    "GCC_OPTIMIZATION_LEVEL": "0",
    "GCC_PREPROCESSOR_DEFINITIONS": ['"DEBUG=1"', '"$(inherited)"'],
    "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
    "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": '"DEBUG $(inherited)"',
    "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
})
prelease = dict(common, **{
    "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
    "ENABLE_NS_ASSERTIONS": "NO",
    "MTL_ENABLE_DEBUG_INFO": "NO",
    "SWIFT_COMPILATION_MODE": "wholemodule",
    "SWIFT_OPTIMIZATION_LEVEL": '"-O"',
})
target = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_ENTITLEMENTS": "CameraOverlay/CameraOverlay.entitlements",
    "CODE_SIGN_IDENTITY": '"-"',
    "CODE_SIGN_STYLE": "Automatic",
    "COMBINE_HIDPI_IMAGES": "YES",
    "CURRENT_PROJECT_VERSION": "1",
    "DEVELOPMENT_TEAM": '""',
    "ENABLE_HARDENED_RUNTIME": "YES",
    "GENERATE_INFOPLIST_FILE": "NO",
    "INFOPLIST_FILE": "CameraOverlay/Info.plist",
    "LD_RUNPATH_SEARCH_PATHS": ['"$(inherited)"', '"@executable_path/../Frameworks"'],
    "MARKETING_VERSION": "1.0",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.abir.CameraOverlay",
    "PRODUCT_NAME": '"$(TARGET_NAME)"',
    "SWIFT_EMIT_LOC_STRINGS": "NO",
}

def config(cid, name, d):
    return f"\t\t{cid} /* {name} */ = {{\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {{\n{settings_block(d)}\n\t\t\t}};\n\t\t\tname = {name};\n\t\t}};"

pbx = f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 56;
	objects = {{

/* Begin PBXBuildFile section */
{chr(10).join(build_files)}
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
{chr(10).join(file_refs)}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		{FW_PHASE} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
{chr(10).join(group_text)}
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{TARGET} /* CameraOverlay */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {TCL} /* Build configuration list for PBXNativeTarget "CameraOverlay" */;
			buildPhases = (
				{SRC_PHASE} /* Sources */,
				{FW_PHASE} /* Frameworks */,
				{RES_PHASE} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = CameraOverlay;
			productName = CameraOverlay;
			productReference = {PRODUCT} /* CameraOverlay.app */;
			productType = "com.apple.product-type.application";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{P} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1500;
				LastUpgradeCheck = 1500;
				TargetAttributes = {{
					{TARGET} = {{
						CreatedOnToolsVersion = 15.0;
					}};
				}};
			}};
			buildConfigurationList = {PCL} /* Build configuration list for PBXProject "CameraOverlay" */;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = {MAIN};
			productRefGroup = {PRODUCTS} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{TARGET} /* CameraOverlay */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		{RES_PHASE} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{ASSETS_BUILD} /* Assets.xcassets in Resources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		{SRC_PHASE} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{chr(10).join(sources)}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
{config(PDBG, "Debug", pdebug)}
{config(PREL, "Release", prelease)}
{config(TDBG, "Debug", target)}
{config(TREL, "Release", target)}
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		{PCL} /* Build configuration list for PBXProject "CameraOverlay" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{PDBG} /* Debug */,
				{PREL} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{TCL} /* Build configuration list for PBXNativeTarget "CameraOverlay" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{TDBG} /* Debug */,
				{TREL} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */
	}};
	rootObject = {P} /* Project object */;
}}
"""
proj = os.path.join(ROOT, "CameraOverlay.xcodeproj")
os.makedirs(os.path.join(proj, "xcshareddata", "xcschemes"), exist_ok=True)
open(os.path.join(proj, "project.pbxproj"), "w").write(pbx)

scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1500" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{TARGET}" BuildableName = "CameraOverlay.app" BlueprintName = "CameraOverlay" ReferencedContainer = "container:CameraOverlay.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{TARGET}" BuildableName = "CameraOverlay.app" BlueprintName = "CameraOverlay" ReferencedContainer = "container:CameraOverlay.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{TARGET}" BuildableName = "CameraOverlay.app" BlueprintName = "CameraOverlay" ReferencedContainer = "container:CameraOverlay.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""
open(os.path.join(proj, "xcshareddata", "xcschemes", "CameraOverlay.xcscheme"), "w").write(scheme)
print("ok")
