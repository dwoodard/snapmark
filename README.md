# Snapmark

A menu bar app for macOS that replaces the built-in screenshot shortcuts with something you can actually work with.
Capture a window, a screen or any area, mark it up, blur what shouldn't be seen, crop it, or record a video with
sound. No account, no network, everything stays on your Mac.

| Shortcut | What it does |
|---|---|
| **⌘⇧4** | Quick capture: pick a window or area, it goes to the clipboard and a file. No window. |
| **⌘⇧5** | Pick a window or area, then **Edit Screenshot** or **Record Video** (with sound and microphone switches). |
| **⌘⇧3** | Full screen, straight to the clipboard and a file. |

Snapmark takes over those three shortcuts while it runs. Turn any of them off in Settings and macOS gets the key back.

## Install

Requires **macOS 15.2 or later**. Apple silicon and Intel.

### Option 1: one command (no warning from macOS)

Paste this into Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/dwoodard/snapmark/HEAD/scripts/install.sh | bash
```

It downloads the latest release, checks it against the published checksum, checks the app's signature, installs
**Snapmark** to `/Applications` (or `~/Applications` if that isn't writable), and opens it. It needs no `sudo` and
touches nothing else. You can read it first: [scripts/install.sh](scripts/install.sh). Running it is you choosing to
trust Snapmark.

Why this avoids the macOS warning: Snapmark is not notarized, and macOS blocks unnotarized apps that were downloaded
by a browser. Files downloaded with `curl` aren't marked that way, so there is nothing to block. To install an older
version, run `SNAPMARK_VERSION=0.1.1 bash` in place of `bash`, for example
`curl -fsSL ... | SNAPMARK_VERSION=0.1.1 bash`. To uninstall, delete `Snapmark.app`.

### Option 2: download the DMG

1. Download the DMG from the [latest release](https://github.com/dwoodard/snapmark/releases/latest).
2. Open it and drag **Snapmark** onto **Applications**. Eject the DMG, and run the app from Applications, not from the DMG.
3. Open Snapmark. macOS will say *"Apple could not verify Snapmark is free of malware"*. This is a one-time step:
   - Click **Done** (not Move to Trash).
   - Open **System Settings > Privacy & Security**, scroll to **Security**, and click **Open Anyway** next to Snapmark.
   - Or run `xattr -dr com.apple.quarantine /Applications/Snapmark.app` in Terminal.

   On macOS 15 and later, right-click > Open does not work for unnotarized apps.

You can check a download against `SHA256SUMS.txt` on the release page: `shasum -a 256 -c SHA256SUMS.txt`.

After either option, a camera icon appears in the menu bar. If it looks dimmed, a permission is still missing, and it
wakes up within a couple of seconds of you granting it.

### Permissions

macOS needs your approval, once per Mac. They are listed in **System Settings > Privacy & Security**.

| Permission | Why |
|---|---|
| Accessibility | Lets Snapmark take over the ⌘⇧3/4/5 shortcuts. |
| Input Monitoring | Same, the key listener needs it. |
| Screen Recording | Taking screenshots and recording. macOS asks on your first capture, then relaunch Snapmark once. |
| Microphone | Only if you turn on Mic when recording. |

## Using it

**Picking what to capture** (⌘⇧4 and ⌘⇧5): hover a window to highlight it and click to capture it. Click and drag to
choose your own area, and hold **Space** while dragging to move the selection. Hover empty desktop, or the **Full Screen**
pill at the top of each display, and click to capture the whole screen. Press **Esc** to cancel. A line at the bottom
always says what a click will do. Settings can lock the area to a ratio such as 1:1 or 16:9, or snap to the nearest one.

**Editor** (⌘⇧5 > Edit Screenshot):

| Tool | Key | Notes |
|---|---|---|
| Arrow, Rectangle, Highlight | A, R, H | Shift snaps arrows to 45 degrees and boxes to squares. |
| Text | T | Click, type, press Return. |
| Blur | B | Drag over what you want hidden. |
| Crop | C | Draw a box, drag the handles or the middle to adjust it. Double-click inside to shrink the view to it. |

⌘Z undoes. **Copy** (⌘C or Return) puts the result on the clipboard. **Save** (⌘S) writes a file. The folder button
(⌘O) opens the save folder, and **Open in PhotoCraft** (⌘E) opens the image in another app you choose. The trash button
(⌘⌫) throws the capture away.

**Recording**: choose **Record Video**. The menu bar icon turns into a red stop button. Click it, or press any capture
shortcut, to stop. The video opens in a viewer where you can **Trim** it (replace the original or save a copy),
**Show in Finder**, **Copy File** or **Delete** it. Computer sound and microphone are mixed into one audio track.

**Recent captures**: the menu bar menu shows your latest screenshots and videos as thumbnails. Click a screenshot to
reopen it in the editor with your marks still editable. Click a video to open it in the viewer.

Files go to `~/Pictures/Screenshots` (or your system screenshot folder if you set one). Change it, the format
(PNG or JPEG), video quality, frame rate and more in **Settings** (⌘, from the menu).

## Troubleshooting

| Problem | Fix |
|---|---|
| Menu bar icon is dimmed | Accessibility or Input Monitoring is not granted. Switch Snapmark on in Privacy & Security. |
| A permission toggle is on but nothing works | The entry is stale. Remove Snapmark from that list with **−**, add `/Applications/Snapmark.app` again, or run `tccutil reset Accessibility com.dustinwoodard.snapmark`. |
| The system screenshot tool still appears | Turn off the shortcuts in System Settings > Keyboard > Keyboard Shortcuts > Screenshots. |
| macOS asks for permissions again after an update | Each release must be signed with the same certificate. See [Signing](#signing). |
| Want to know if there is a newer version | Settings > General > **Check for Updates**. Snapmark also checks once at launch (you can turn that off). To update, run the install command again. |
| Screenshots or recordings fail | Screen Recording is off. Turn it on, then quit and reopen Snapmark. |
| No sound in a recording | Turn on Computer sound or Mic on the ⌘⇧5 bar, or under Settings > Video. |

## Build from source

Nothing to install except Apple's tools. Snapmark has **no third-party dependencies**: it only uses frameworks that
ship with macOS (AppKit, ScreenCaptureKit, AVFoundation, AVKit, CoreImage, ServiceManagement).

| Need | Why |
|---|---|
| macOS 15.2 or later | `SCScreenshotManager.captureImage(in:)` needs it |
| Xcode (Swift 6.2 toolchain) | Built and tested with Xcode 26.2. No Xcode project, only Swift Package Manager |

Optional tools: [`gh`](https://cli.github.com) to publish releases, [ImageMagick](https://imagemagick.org) only to
regenerate the DMG background.

```sh
git clone https://github.com/dwoodard/snapmark.git
cd snapmark
swift build                         # compile check
./scripts/build-app.sh --install    # builds build/Snapmark.app and copies it to /Applications
open /Applications/Snapmark.app
```

A clean clone builds in under a minute. Then grant the permissions above. Because the first build is signed ad hoc,
macOS will ask again after each rebuild until you set up stable signing.

### Signing

macOS ties Accessibility, Input Monitoring and Screen Recording to the app's signing identity. An ad-hoc signature changes
on every build, so you would re-grant everything each time. One free, local fix is a self-signed certificate:

```sh
T=$(mktemp -d) && cd "$T"
cat > cert.cnf <<'EOF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = Snapmark Local Signing
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 3650 -config cert.cnf
/usr/bin/openssl pkcs12 -export -inkey key.pem -in cert.pem -out cert.p12 -passout pass:snapmark
security import cert.p12 -k ~/Library/Keychains/login.keychain-db -P snapmark -T /usr/bin/codesign
cd / && rm -rf "$T"
```

`scripts/build-app.sh` uses a certificate named **Snapmark Local Signing** automatically. To use another identity,
set `SIGN_ID`. Release builds on other machines would need the same certificate, or they get a different identity.

### Releasing

The version lives in the `VERSION` file only. New features bump the minor version, fixes bump the patch, and a published
version is never changed. Releases are built as drafts, checked, then published by hand. The full process, the DMG and the
CI workflow are in [docs/releasing.md](docs/releasing.md).

```sh
scripts/version.sh bump minor    # or: patch, or: set 0.2.0-rc.1
scripts/release.sh --dry-run     # build and package into dist/ without touching GitHub
scripts/release.sh               # same, then create a draft GitHub release
```

### Project layout

```
Sources/Snapmark/     the app (about 2,700 lines of Swift)
scripts/              build-app.sh, version.sh, release.sh, make-dmg.sh
packaging/dmg/        the DMG window background
docs/releasing.md     how releases are cut
VERSION               the one place the version lives
CLAUDE.md             notes for working on this project with Claude Code
```

`CLAUDE.md` has the code map, the decisions behind it, and the lessons learned along the way.

## Privacy

Snapmark collects nothing and has no account. Its only network request is an optional update check at launch: it asks GitHub's public releases page which version is newest, and sends no personal data. Turn it off in Settings > General, or run the check by hand there. Captures live in your save folder. The editor's history
(original images and marks for recent screenshots) is stored in `~/Library/Application Support/Snapmark/History`, and the
Recent Captures menu can clear it.

## Status

Early (0.1.x). The app is not notarized, and there is no license file yet, so all rights are reserved until one is added.
