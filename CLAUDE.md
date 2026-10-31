# Snapmark

@~/.agents/me/

A macOS menu bar app that replaces the system screenshot hotkeys (Cmd-Shift-3/4/5) with a better capture,
annotation and screen recording tool. Swift 6.2, AppKit, SwiftPM, no Xcode project. Started from the idea
behind `~/projects/vocal` (event tap that takes over a hotkey), rebuilt natively in Swift.

Repo: github.com/dwoodard/snapmark (public). Releases: v0.1.0, v0.1.1 (latest).

## How I (Dustin) work with this project

- Small steps, I own the decisions. Match the global rules in `~/.agents/me/`.
- Work on `feature/capture-editor-settings`. **Never push or merge `main`.** `main` does not exist on GitHub, so the
  default branch is currently the feature branch. Never add a co-author to commits.
- Commit style: conventional commits (`feat:`, `fix:`, `docs:`, `chore:`).
- After a code change, rebuild and relaunch so I can try it:
  `pkill -x Snapmark; ./scripts/build-app.sh --install; open /Applications/Snapmark.app`
- I cannot click through the UI from here. Say what was verified (build, a rendered test, a file inspected) and what was
  not. Do not claim a UI behavior works unless it was seen.

## Build, run, release

| Task | Command |
|---|---|
| Fast compile check | `swift build` |
| Build the app (host arch) | `./scripts/build-app.sh` |
| Build and install to `/Applications` | `./scripts/build-app.sh --install` |
| Universal build (releases) | `./scripts/build-app.sh --universal` |
| Show / set / bump version | `scripts/version.sh`, `scripts/version.sh set 0.2.0`, `scripts/version.sh bump minor\|patch` |
| Package without GitHub | `scripts/release.sh --dry-run` (writes `dist/`) |
| Draft a GitHub release | `scripts/release.sh` (HEAD must be pushed; creates a DRAFT) |
| Publish a draft | `gh release edit vX.Y.Z --draft=false --latest` |

`docs/releasing.md` is the full process. It is modeled on PhotoCraft (github.com/storytold/photocraft):

- One version source, the `VERSION` file. Tags are `v0.MINOR.PATCH`. New features bump minor, fixes only bump patch,
  test builds use `-rc.N` and are marked pre-release.
- `scripts/install.sh` is the curl-based installer from the README (no browser download, so no quarantine flag and no
  Gatekeeper block). It installs the latest release and checks the checksum and signature. It is served from the default
  branch, not attached to releases. Verified: a curl download has no quarantine flag.
- A **published version is never changed** (assets or tag). Fix forward with the next version. Editing release notes
  text is fine.
- Releases are created as drafts, checked, then published by hand. Publishing creates the tag.
- Assets: `snapmark-<v>-macos-universal.dmg`, the same app as `.zip`, and `SHA256SUMS.txt`.
- `.github/workflows/release.yml` (push to a `release` branch) mirrors this on CI. **It has never run.** Do not push a
  `release` branch without meaning to spend macOS runner minutes.

## Signing and permissions (the part that bites)

- No Apple Developer ID. The app is **not notarized**. A downloaded copy shows "Apple could not verify..." once.
  On macOS 15+ right-click > Open does NOT work. Use System Settings > Privacy & Security > Open Anyway, or
  `xattr -dr com.apple.quarantine /Applications/Snapmark.app`. Clicking Move to Trash on that dialog deletes the app.
- Builds are signed with a self-signed certificate named **Snapmark Local Signing** in Dustin's login keychain.
  `build-app.sh` finds it automatically (or use `SIGN_ID`). Its designated requirement is the bundle id plus the
  certificate hash, so macOS keeps the Accessibility, Input Monitoring and Screen Recording grants across rebuilds.
  An ad-hoc signature changes every build and re-prompts every time. The certificate exists only on this Mac.
  A release built anywhere else (CI without the `SIGNING_CERTIFICATE` secrets) would reset everyone's permissions.
- If a toggle looks on but does nothing, the entry is stale. `tccutil reset <Accessibility|ListenEvent|ScreenCapture>
  com.dustinwoodard.snapmark`, then grant again.
- Open question for Dustin: pay for Apple Developer ID (99 USD/yr) and notarize, or keep Open Anyway.

## Behavior (what the app does today)

- **Cmd-Shift-4** quick region: copies to clipboard and saves a file (both are settings). **Cmd-Shift-5** region, then a
  small bar: Edit Screenshot / Record Video / audio toggles. **Cmd-Shift-3** full screen. Each hotkey can be turned off
  in Settings, which passes the key back to macOS. The event tap swallows the keys, so the system tool never appears.
- **Picker** (`RegionSelector`): hover highlights the window under the cursor, a click captures it. Empty desktop or the
  "Full Screen" pill at the top captures the screen. Drag selects an area. Space while dragging moves the selection.
  Region ratio setting: free, smart snap, or fixed (1:1, 16:9, ...).
- **Editor**: arrow, rectangle, highlight, text, blur, crop (handles, move, double-click to shrink the view), undo, Copy,
  Save, open folder, Open in PhotoCraft (setting), delete (moves saved files to the Trash). Keys: A R H T B C, Cmd-Z,
  Cmd-C, Cmd-S, Cmd-E, Cmd-O, Cmd-Delete.
- **Recording**: H.264 `.mp4` through `AVAssetWriter` with an explicit bitrate (the system recorder's bitrate was far
  too low). Computer sound and microphone are mixed into one AAC track (`AudioMixer` in `Recorder.swift`). Stops from
  the red menu bar icon or any capture hotkey, then opens the in-app viewer. Viewer: trim (replace the original or save
  a copy), Show in Finder, Copy File, Delete.
- **Recents**: menu bar shows two thumbnail strips (screenshots, videos) plus an All Recent Captures submenu. Stored in
  `~/Library/Application Support/Snapmark/History` with the original image and annotations, so a capture can be
  re-edited. Videos are not copied there, only referenced.
- Save folder defaults to `~/Pictures/Screenshots`. All settings are in `Settings.swift` (UserDefaults, domain
  `com.dustinwoodard.snapmark`) and the five-tab window in `SettingsController.swift`.
- Snapmark's own windows are excluded from every capture (`Capture.prepare` excludes the app).

## Code map (`Sources/Snapmark/`)

| File | Role |
|---|---|
| `main.swift`, `AppDelegate.swift` | Entry, menu bar item and menu, hotkey handling, recording state, recents menu |
| `HotkeyTap.swift` | Quartz event tap for Cmd-Shift-3/4/5 |
| `RegionSelector.swift` | Overlay windows, hover/click/drag picker, ratio constraint |
| `CaptureActionBar.swift` | The Edit / Record / audio bar and the selection outline |
| `Capture.swift` | ScreenCaptureKit display, filter, config shared by screenshots and video |
| `Recorder.swift` | Stream to `AVAssetWriter`, `AudioMixer`, `VideoQuality` |
| `EditorController.swift`, `CanvasView.swift`, `Annotation.swift` | Editor window, drawing and hit testing, model plus `Renderer` (also used for export) |
| `VideoViewerController.swift` | In-app video playback, trim, delete |
| `History.swift`, `RecentBarView.swift` | Recents storage and the thumbnail strip |
| `Settings.swift`, `SettingsController.swift`, `AspectRatios.swift` | Preferences and UI |
| `UpdateChecker.swift` | Latest-release check and version comparison |
| `Output.swift`, `Permissions.swift`, `LaunchAtLogin.swift` | Small helpers |

Other: `scripts/` (build, version, release, DMG), `packaging/dmg/` (window background, regenerate with
`make-background.sh`, needs ImageMagick), `docs/releasing.md`, `VERSION`.

## Lessons learned (do not relearn these)

- Since macOS 14, `NSView` does **not** clip drawing to its bounds. `CanvasView` sets `clipsToBounds = true`, otherwise a
  zoomed crop painted over the toolbar. `NSView.visibleRect` already exists, so the canvas uses `shownRect`.
- `NSWindow.setFrame` takes a frame, but sizes are usually content sizes. Use `frameRect(forContentRect:)` or the title
  bar eats the toolbar.
- `SCScreenshotManager.captureImage(in:)` returns point-resolution images on Retina. Use a filter with
  `sourceRect` and an explicit pixel size (`Capture.prepare`).
- `SCRecordingOutput` gave ~140 kbps video and no bitrate control. That is why `Recorder` uses `AVAssetWriter`.
- macOS `sed` has no `\b`. Use `perl -pi -e` for word-boundary renames.
- Floating window levels cover the app you just opened (PhotoCraft, Finder). The editor is a normal window.
- Unhandled keys passed to `super.keyDown` cause the system beep. Swallow them.
- To check UI without a mouse: temporarily add a `--selftest` flag in `main.swift` that builds the window, then dumps
  frames and `cacheDisplay` PNGs to `/tmp`. Set `appearance = .aqua` or labels render invisible. Remove it afterwards
  and make sure it never lands in a commit.
- Verify with evidence, not by reading code. Audio was verified with a headless 4-second recording while `say` played,
  then `ffprobe` for the tracks and `ffmpeg -af volumedetect` for the level. Delete test files you create in my
  screenshots folder.

## State and next steps

- Done and released: capture, picker, editor with crop, recording with audio, viewer, recents, settings, DMG,
  versioned releases (v0.1.2 latest), `scripts/install.sh` installer.
- Built, not yet released (on the feature branch): the update check. Settings > General has **Check for Updates** and a
  launch-time check (on by default, one HEAD request to `github.com/dwoodard/snapmark/releases/latest`, no personal data).
  A newer version adds an "Update Available" line at the top of the menu bar menu. The app does not install updates
  itself: it offers View Release and Copy Install Command (the README one-liner). It only ever counts published stable
  releases, never drafts or `-rc` builds. Logic is in `UpdateChecker.swift`.
- Not built / ideas: a license file for the public repo (README exists); Apple notarization; the editor's Open in button defaulting to Preview when PhotoCraft is missing
  (planned for the next release); delete not trashing the PNG of a reopened quick capture; window-only capture (the picker
  captures the screen area under a window, so overlapping windows show); mic plus computer sound together is untested.
- Untested: `.github/workflows/release.yml`; the microphone path; behavior on a second Mac.
