# STAX — iOS build pipeline (READ BEFORE BUILDING FOR iOS)

The Godot **source** in this repo is configured (AdMob addon, ios/plugins, project.godot,
export_presets, icons, auth). BUT Godot's iOS export still needs **post-export patches** to
produce a working App Store build. These are NOT captured by the Godot project — you must apply
them to the generated Xcode project every time you do a full iOS export. (A code-only change can
skip the full export: just re-run `--export-pack "iOS"` to refresh `stax.pck` and re-archive.)

Team ID: `MXR22HH76N`. Bundle: `com.whitzy.stax`. Godot: 4.6.3.

## Already in the Godot source (no action needed)
- `addons/admob/` (Poing AdMob plugin, enabled in project.godot `[editor_plugins]`)
- `ios/plugins/poing-godot-admob*` — `.gdip` has the **real GADApplicationIdentifier**
  (`ca-app-pub-8118111609250042~3048642220`) + NSUserTrackingUsageDescription + SKAdNetwork list
- `project.godot`: `[rendering] textures/vram_compression/import_etc2_astc=true` (REQUIRED or iOS
  export fails), boot_splash/show_image=false, portrait orientation
- `export_presets.cfg`: iOS preset (team, bundle, version), `plugins/AdMob=true`, signing fields
- `icon.svg.png` (+ .import) — the real STAX Blocks icon
- `scripts/AdsAdmob.gd`: real iOS rewarded unit `ca-app-pub-8118111609250042/5979726199`
  (interstitial is still a TEST unit but is never called)
- `scripts/Auth.gd`: `AUTH_REDIRECT` (currently the Vercel paste-code page)

## Post-export patches (apply to the generated Xcode project every full export)
Generate: `Godot --headless --path . --export-release "iOS" <out>/stax.xcodeproj`
(NOTE: the FIRST export run often generates nothing — just run it again. Godot's own archive step
fails on distribution signing — ignore it; the project still generates.)

1. **Google frameworks (the big one):** Godot writes a `Package.swift` (PoingGodotAdMobDeps) but
   does NOT attach it, so GoogleMobileAds/UMP symbols are undefined → link them directly instead.
   Download once (URLs from each repo's pinned Package.swift binaryTarget) and reuse:
   - GoogleMobileAds 13.1.0 + GoogleUserMessagingPlatform 3.1.0 xcframeworks (both STATIC).
   Copy both `.xcframework` into `<out>/`, add PBXFileReference + PBXBuildFile for each, and add
   both to the app target's **PBXFrameworksBuildPhase**. (FRAMEWORK_SEARCH_PATHS is already
   `$(PROJECT_DIR)/**`.) Kept locally at `/Users/whitzy/stax-game/admob_xcframeworks/`.
2. **Signing:** in pbxproj `sed`: `CODE_SIGN_STYLE = "Manual"` → `"Automatic"`,
   `CODE_SIGN_IDENTITY = "Apple Distribution"` → `"Apple Development"`, and delete the hard-coded
   `PROVISIONING_PROFILE = "<uuid>";` lines. (Xcode re-signs distribution at Upload.)
3. **Orientation:** in `stax/stax-Info.plist`, `UIInterfaceOrientationLandscapeLeft/Right` →
   `UIInterfaceOrientationPortrait` (Godot wrongly exports landscape).
4. **Icon:** Godot falls back to a placeholder icon. Re-bake the real icon (flattened, NO alpha —
   Apple rejects alpha) into every size in `stax/Images.xcassets/AppIcon.appiconset/` (PIL:
   alpha_composite onto opaque black → RGB → resize to Contents.json sizes incl. 1024).
5. **Splash (remove Godot logo):** overwrite `stax/Images.xcassets/SplashImage.imageset/splash@2x.png`
   and `@3x.png` with a solid #0A0814 (rgb 10,8,20) 800x600 PNG. (Godot generates the Godot-logo
   launch screen regardless of show_image.)
6. **Crash-on-close fix:** add `stax/CleanExit.m` (Obj-C, swizzles
   `-[GDTApplicationDelegate applicationWillTerminate:]` to `_Exit(0)` — Godot 4.x crashes tearing
   down GDScript lambdas on terminate). Add PBXFileReference (path `"stax/CleanExit.m"`) +
   PBXBuildFile + entry in **PBXSourcesBuildPhase**.

## Archive + upload
```
xcodebuild archive -project <out>/stax.xcodeproj -scheme stax -configuration Release \
  -destination "generic/platform=iOS" -archivePath build/stax.xcarchive \
  CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" \
  DEVELOPMENT_TEAM=MXR22HH76N -allowProvisioningUpdates
```
Then Xcode Organizer → Distribute App → App Store Connect → Upload (or `altool` with an
App Store Connect API key + Issuer ID). Bump `CURRENT_PROJECT_VERSION` each upload.
iOS launch-screen is cached — if an old splash persists after update, DELETE + reinstall.

## Save-file constraints (from the original dev — DO NOT violate)
- NEVER reorder fields in `GameState._save` / `_read_save_fields` — only append at the end.
- Leave the crash-safe save intact (atomic temp+rename, .bak, no-wipe-on-short-read).
