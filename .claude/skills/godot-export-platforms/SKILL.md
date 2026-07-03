---
name: godot-export-platforms
description: Godot 4.x export and platform delivery — export presets and templates, Windows/macOS/Linux desktop builds, Android (GABE/Gradle, 4.7), iOS, Web/HTML5 exports and their constraints, feature tags, PCK patching, encryption, and per-platform gotchas (input, files, rendering). Use when exporting a Godot game, setting up CI builds, or fixing platform-specific issues.
---

# Godot Export & Platforms (4.x, current through 4.7)

## Export fundamentals

- Install matching **export templates** (Editor > Manage Export Templates) — template version must equal editor version exactly.
- **Export presets** live in `export_presets.cfg` (commit it; secrets like keystore passwords go in `~/.config` overrides or CI env vars — the file supports `ENV` substitution via CI writing them, don't commit credentials).
- Two artifacts: executable + **PCK** (packed resources). Embed PCK for single-file desktop builds, or keep separate for patchable installs.
- Headless CI export:
```bash
godot --headless --export-release "Windows Desktop" build/game.exe
godot --headless --export-debug "Web" build/index.html
# first run on fresh CI: godot --headless --import  (build .godot cache before exporting)
```
- Debug vs release exports: debug keeps asserts, remote debugging, `OS.is_debug_build()` = true. Never ship debug (slow + console-visible).
- **Shader baker (4.5+)**: enable in export settings to precompile shaders → removes first-run shader stutter, faster startup (bigger binary; per-driver caveats — test).

## Resource handling on export

- Only referenced resources export by default; **non-resource files (`.json`, `.txt`, `.csv`) need "Filters to export non-resource files"** (e.g. `*.json`) or they silently won't exist in builds — classic "works in editor, breaks in export" bug.
- `res://` is **read-only** in exports (it's inside the PCK). All writes → `user://` (set `application/config/custom_user_dir_name`).
- Path case sensitivity: exports are case-sensitive even on Windows (PCK paths) — `load("res://Sprites/foo.png")` vs `sprites/` breaks only in builds. Match exact case always.
- PCK encryption: set an encryption key (compile-time env `SCRIPT_AES256_ENCRYPTION_KEY` + preset toggle) to deter casual asset ripping — determined attackers still win; don't put secrets in the client, ever.
- Patches: load extra PCKs at runtime `ProjectSettings.load_resource_pack("user://patch1.pck")` — later packs override earlier files. Good for DLC/patches/mods (load only trusted packs — PCKs contain scripts; see save-security note in godot-architecture).

## Feature tags & per-platform code

```gdscript
if OS.has_feature("web"): ...        # platform: windows, macos, linux, android, ios, web
if OS.has_feature("mobile"): ...     # class: mobile, pc; build: debug, release; arch: x86_64, arm64
if OS.has_feature("demo"): ...       # custom tags set per-preset — demo builds, storefront variants
```
Feature tags also drive **project setting overrides** (`application/config/name.web`) and can gate export of files. Use custom tags for storefront-specific integrations (steam/itch builds) instead of forked branches.

## Desktop (Windows / macOS / Linux)

- Windows: set icon + version info in preset; SmartScreen will nag unsigned exes — code-sign (EV/OV cert or Azure Trusted Signing) for wide distribution; Steam builds don't need it.
- macOS: **must** be signed + notarized for distribution outside the App Store (preset supports codesign/notarization; needs Apple Developer ID). Universal (x86_64+arm64) is default. `.app` bundle; entitlements matter if using mics/cameras/network.
- Linux: export x86_64 (+arm64 if desired); test on oldest supported glibc (build on old distro or use official templates as-is).
- Steam: no built-in Steamworks — use **GodotSteam** (GDExtension or precompiled templates). Ship Steam builds with a custom `steam` feature tag.
- Renderer fallback: Forward+ auto-falls back D3D12/Vulkan/Metal per OS; expose a `--rendering-driver opengl3` style launch option or a Compatibility fallback for ancient GPUs if your audience skews old hardware.

## Android

- **GABE — Godot Android Build Environment (stable in 4.7)**: the sanctioned Gradle-based pipeline; use Gradle builds for anything beyond a toy (required for plugins, ads, services, App Bundles).
- One-time setup: Android SDK + JDK paths in Editor Settings; install Android build template into the project (`Project > Install Android Build Template`) for Gradle builds.
- Signing: debug keystore auto; **release needs your keystore** (guard it — Play updates require the same key or Play App Signing).
- Play requires **AAB** (App Bundle) + target recent API level; arm64-v8a mandatory (ship arm64 + optionally armv7).
- Permissions in preset (internet, vibrate…); Android 13+ notification/media permissions need runtime requests via plugins.
- Renderer: Mobile renderer default; Compatibility for low-end reach. Test on a real low-end device early — thermal throttling and tile-GPU overdraw behave nothing like desktop.
- Input: back button = `ui_cancel`-ish via `NOTIFICATION_WM_GO_BACK_REQUEST`; handle app pause `NOTIFICATION_APPLICATION_PAUSED` (save there — Android kills backgrounded apps freely).
- 4.7 bonus: GDScript can implement Java interfaces — lighter-weight interop with Android APIs/plugins.
- One-click deploy over USB/wifi debugging is the fast iteration loop; `adb logcat -s godot` for logs.

## iOS

- Export produces an **Xcode project** — final build/sign/upload happens in Xcode on a Mac (Apple Developer account required).
- Set bundle id, team, icons/launch images in preset; usage descriptions (camera/mic/photos) if touched, or App Review rejects.
- Metal renderer; test on oldest supported device — memory limits are the usual crash source (jetsam), watch VRAM.
- `NOTIFICATION_APPLICATION_PAUSED`/`RESUMED` for save/audio handling; no runtime JIT — C# on iOS uses AOT (test early if using C#).
- TestFlight for beta distribution.

## Web (HTML5)

The most constrained target — decide early if you ship web, and test web weekly, not at the end:
- Renderer: **Compatibility** (WebGL2). Forward+/Mobile aren't available on web. No SDFGI/VoxelGI/volumetrics; plan lighting accordingly (LightmapGI works).
- **Threads**: the default export uses threads → requires **cross-origin isolation headers** (`Cross-Origin-Opener-Policy: same-origin`, `Cross-Origin-Embedder-Policy: require-corp`). Itch.io supports (checkbox "SharedArrayBuffer support"); plain static hosts need header config. If you can't control headers, export with Threads disabled (perf cost).
- No ENet — WebSocket/WebRTC only (see godot-multiplayer). HTTP via `HTTPRequest` is subject to CORS.
- Audio quirks: playback can't start before first user interaction (browser policy) — gate audio behind a "click to start" screen. Use the AudioWorklet default.
- File system: `user://` maps to IndexedDB (persists per-origin; can be wiped by the browser) — offer export/import of saves for anything precious.
- Performance: expect ~2–5× slower than native; keep VRAM tiny, compress textures, avoid huge PCKs (streaming download is per-file progressive; show the built-in loading bar or a custom shell).
- Mobile browsers: treat as lowest tier; Safari has the most quirks (test it specifically).
- C#/.NET web export: unsupported (as of 4.7) — GDScript projects only for web.

## Console (context, not how-to)

No public console exports (NDA'd SDKs). Ports go through licensed partners (e.g. W4 Games) or your own devkit + source access. Architect for it: keep platform-specific code behind feature tags, use the abstraction points (Input, FileAccess) — porting cost is mostly in the weird corners.

## HDR output (4.7+)

Desktop/mobile HDR displays: enable HDR output (window settings) on Windows/macOS/iOS/Linux-Wayland. Author scenes with AgX tonemap + real HDR emissives; always verify the SDR fallback path since most players are SDR.

## CI recipe sketch (GitHub Actions shape)

1. Container/action with the exact Godot version (e.g. `barichello/godot-ci` or setup action).
2. Cache `.godot/` imported assets between runs (huge time save).
3. `godot --headless --import` → run tests (gdUnit4/GUT headless) → `--export-release` per preset → upload artifacts.
4. Keystores/certs from CI secrets, written to disk in the job, referenced via preset env overrides.
5. itch.io deploys: `butler push build/web user/game:html5`.

## Pitfalls checklist

1. JSON/data files missing in export (non-resource filter not set).
2. Writes to `res://` working in editor, failing in build.
3. Path case mismatch only breaking in exports.
4. Template/editor version mismatch → instant crash or export failure.
5. Web build black screen: threads enabled but headers missing (check browser console first — it says so).
6. Android release crash but debug fine: usually missing arch, plugin misconfig, or ProGuard-ish Gradle settings — `adb logcat` before guessing.
7. Shipping with `OS.is_debug_build()` branches assuming release, but exporting debug preset.
8. Save-breaking updates: version your save format (see godot-architecture).
9. Untested Compatibility renderer differences (no glow HDR2D subtleties, shader feature gaps) discovered on launch day — run the web/low-end build routinely.
10. macOS "damaged app" reports from users = not notarized.
