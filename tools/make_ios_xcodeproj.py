#!/usr/bin/env python3
"""Fallback: build an Xcode project from the Godot iOS template + exported .pck.
Usage: make_ios_xcodeproj.py <ios.zip> <data.pck> <outdir> <team_id> <bundle_id> [debug|release]"""
import sys, os, re, shutil, zipfile, plistlib
tpl, pck, out, team, bundle = sys.argv[1:6]
cfg = sys.argv[6] if len(sys.argv) > 6 else "debug"
NAME = "Tminus"
shutil.rmtree(out, ignore_errors=True); os.makedirs(out)
tmp = out + ".tpl"; shutil.rmtree(tmp, ignore_errors=True)
zipfile.ZipFile(tpl).extractall(tmp)
sh = lambda *a: [shutil.copytree if os.path.isdir(a[0]) else shutil.copy2][0](*a)
sh(f"{tmp}/godot_apple_embedded", f"{out}/{NAME}")
sh(f"{tmp}/godot_apple_embedded.xcodeproj", f"{out}/{NAME}.xcodeproj")
sh(f"{tmp}/MoltenVK.xcframework", f"{out}/MoltenVK.xcframework")
sh(f"{tmp}/libgodot.ios.{cfg}.xcframework", f"{out}/{NAME}.xcframework")
shutil.copy2(pck, f"{out}/{NAME}.pck")
os.rename(f"{out}/{NAME}/godot_apple_embedded-Info.plist", f"{out}/{NAME}/{NAME}-Info.plist")
os.rename(f"{out}/{NAME}/godot_apple_embedded.entitlements", f"{out}/{NAME}/{NAME}.entitlements")
os.rename(f"{out}/{NAME}.xcodeproj/xcshareddata/xcschemes/godot_apple_embedded.xcscheme", f"{out}/{NAME}.xcodeproj/xcshareddata/xcschemes/{NAME}.xcscheme")
land = "<string>UIInterfaceOrientationLandscapeRight</string>\n<string>UIInterfaceOrientationLandscapeLeft</string>"
V = dict(binary=NAME, team_id=team, bundle_identifier=bundle, name=NAME, version="1", short_version="1.0",
  godot_archs="arm64", valid_archs="arm64", sdkroot="iphoneos", linker_flags="-ObjC -framework Metal -framework MetalKit -framework QuartzCore -framework IOSurface -framework CoreGraphics -framework UIKit -framework AVFoundation -framework AudioToolbox -framework CoreAudio -framework CoreMotion -framework GameController -framework CoreHaptics -framework CoreMedia -framework CoreVideo -framework Foundation -framework Security -framework SystemConfiguration -framework OpenGLES -framework CoreText -framework CoreServices -framework Photos -framework UniformTypeIdentifiers -framework Accelerate -lc++ -lz",
  os_deployment_target="IPHONEOS_DEPLOYMENT_TARGET = 15.0;", targeted_device_family="2",
  default_build_config="Debug" if cfg=="debug" else "Release",
  code_sign_identity_debug="Apple Development", code_sign_identity_release="Apple Development",
  code_sign_style_debug="Automatic", code_sign_style_release="Automatic",
  interface_orientations=land, ipad_interface_orientations=land, signature="????",
  required_device_capabilities="<string>arm64</string>", plist_launch_screen_name="<key>UILaunchStoryboardName</key><string>Launch Screen</string>",
  moltenvk_fileref='DEADBEEF3F582BE20003B888 /* MoltenVK.xcframework */ = {isa = PBXFileReference; lastKnownFileType = wrapper.xcframework; path = MoltenVK.xcframework; sourceTree = "<group>"; };',
  moltenvk_buildfile='DEADBEEF4F582BE20003B888 /* MoltenVK.xcframework in Frameworks */ = {isa = PBXBuildFile; fileRef = DEADBEEF3F582BE20003B888 /* MoltenVK.xcframework */; };',
  moltenvk_buildphase='DEADBEEF4F582BE20003B888 /* MoltenVK.xcframework in Frameworks */,',
  moltenvk_buildgrp='DEADBEEF3F582BE20003B888 /* MoltenVK.xcframework */,',
  cpp_code="void godot_apple_embedded_plugins_initialize() {}\nvoid godot_apple_embedded_plugins_deinitialize() {}\n",
  entitlements_full="", camera_usage_description="Camera", photolibrary_usage_description="Photos",
  microphone_usage_description="Microphone", docs_in_place="", docs_sharing="", additional_plist_content="")
def sub(text):
    keys = sorted(V, key=len, reverse=True)
    text = re.sub(r"\$(" + "|".join(keys) + r")\b", lambda m: V[m.group(1)], text)
    return re.sub(r"\$[a-z_]+\b", "", text)  # remaining optional tokens -> empty
for root, _, fs in os.walk(out):
    if root.endswith(".xcframework") or ".xcframework/" in root or root.endswith("dylibs"): continue
    for f in fs:
        if f.endswith((".pbxproj", ".plist", ".entitlements", ".xcscheme", ".storyboard", ".h", ".cpp", ".swift")):
            p = os.path.join(root, f)
            try: t = open(p, encoding="utf-8").read()
            except Exception: continue
            open(p, "w", encoding="utf-8").write(sub(t))
# Godot's prebuilt "ios-arm64_x86_64-simulator" slice is x86_64-only, but the iOS 26 simulator on Apple Silicon
# needs arm64. Merge a locally built arm64 simulator libgodot.a (scons platform=ios simulator=yes arch=arm64)
# from the export-templates cache into that slice, so Xcode builds native arm64 + x86_64.
import subprocess
ARM_SIM = os.path.expanduser("~/Library/Application Support/Godot/export_templates/4.7.2.stable/libgodot.ios.template_release.arm64.simulator.a")
slice_lib = f"{out}/{NAME}.xcframework/ios-arm64_x86_64-simulator/libgodot.a"
if os.path.exists(ARM_SIM) and os.path.exists(slice_lib):
    have = subprocess.run(["lipo", "-archs", slice_lib], capture_output=True, text=True).stdout.split()
    if "arm64" not in have:
        subprocess.check_call(["lipo", "-create", slice_lib, ARM_SIM, "-output", slice_lib + ".fat"])
        os.replace(slice_lib + ".fat", slice_lib)
else:
    print("WARNING: arm64 simulator libgodot.a missing; simulator build will fail on Apple Silicon")
pbx = f"{out}/{NAME}.xcodeproj/project.pbxproj"
t = open(pbx, encoding="utf-8").read()
t = re.sub(r'^(\s*)SDKROOT = iphoneos;\n', lambda m: m.group(0) + f'{m.group(1)}ONLY_ACTIVE_ARCH = NO;\n', t, flags=re.M)
open(pbx, "w", encoding="utf-8").write(t)
ai = f"{out}/{NAME}/Images.xcassets/AppIcon.appiconset"; os.makedirs(ai, exist_ok=True)
shutil.copy2(os.environ.get("ICON", "icon.png"), f"{ai}/icon.png")
open(f"{ai}/Contents.json", "w").write('{"images":[{"filename":"icon.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}')
shutil.copy2(f"{tmp}/PrivacyInfo.xcprivacy", f"{out}/PrivacyInfo.xcprivacy")
shutil.rmtree(tmp)
print("created", f"{out}/{NAME}.xcodeproj")
