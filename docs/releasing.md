# Releasing Snapmark

Modeled on how PhotoCraft releases. Every release is a **draft** GitHub Release named
`Snapmark v<version>`. Nobody sees it until you publish it, and publishing creates the tag.

## Versions

The version lives in one place: the `VERSION` file. Never edit it by hand.

```sh
scripts/version.sh               # prints the current version
scripts/version.sh set 0.2.0     # or 0.2.0-rc.1 for a test build
scripts/version.sh bump minor    # 0.1.0 -> 0.2.0
scripts/version.sh bump patch    # 0.2.0 -> 0.2.1
```

Tags are `v0.MINOR.PATCH` while the app is pre-1.0, the same as PhotoCraft:

| Change | Bump | Example |
|---|---|---|
| New features, or anything users will notice | minor | 0.1.0 → 0.2.0 |
| Fixes only | patch | 0.2.0 → 0.2.1 |
| Test build before a release | `-rc.N` suffix, marked pre-release | 0.2.0-rc.1 |

A published version is never rebuilt or replaced. `scripts/release.sh` refuses to touch it,
so bump the version first. 1.0.0 is for when the capture and editor behavior is settled.

The version shows in Settings > General, and in `Info.plist` as `CFBundleShortVersionString`
(plus `SnapmarkBuildCommit`, the short commit the build came from).

## Cutting a release

1. **Bump the version** on your feature branch and commit it:

   ```sh
   scripts/version.sh bump minor
   git commit -am "chore: release 0.2.0"
   ```

2. **Merge to `main`**, then fast-forward `release` to it and push. The push starts
   `.github/workflows/release.yml`. To run the same thing from your Mac instead,
   push the branch and run `scripts/release.sh` (needs `gh` signed in).
3. **Wait for the draft.** It is tagged `v0.2.0` (the tag appears when you publish), with:
   - `snapmark-<version>-macos-universal.zip` (Apple silicon + Intel)
   - `SHA256SUMS.txt`
   - notes generated from the commits, with install steps on top
4. **Check it.** Download the zip, unzip it, open it, and take one screenshot and one recording.
   Check that Settings > General shows the new version.
5. **Publish** the draft in the GitHub UI.

Pushing to `release` again before you publish rebuilds the same draft and replaces its files.

**Test runs:** *Actions > Release > Run workflow* with a `version` such as `0.2.0-rc.1`
overrides `VERSION` for that run only. Locally, `SNAPMARK_VERSION=0.2.0-rc.1 scripts/release.sh`.
`scripts/release.sh --dry-run` builds and packages into `dist/` without touching GitHub.

## Signing

Snapmark is **not notarized** and has no Apple Developer ID. Two consequences:

- **First launch:** downloaders must right-click > Open once (or run
  `xattr -dr com.apple.quarantine /Applications/Snapmark.app`). The release notes say so.
- **Permissions:** macOS keys Accessibility, Input Monitoring and Screen Recording to the
  signing identity. An ad-hoc signature changes every build, so users would be asked again
  after each update. Release builds should be signed with one stable certificate.
  `scripts/build-app.sh` uses `SIGN_ID` if set, else a keychain certificate named
  **Snapmark Local Signing**, else ad-hoc (with a warning).

To sign CI builds with the same certificate as your local ones, add these to the repo's
`release` environment (Settings > Environments > release):

| Secret | Value |
|---|---|
| `SIGNING_CERTIFICATE` | base64 of the certificate exported as `.p12` |
| `SIGNING_CERTIFICATE_PASSWORD` | password for that `.p12` |
| `KEYCHAIN_PASSWORD` | optional, for the temporary CI keychain |

Without them CI still builds, but the app is ad-hoc signed and the run shows a warning.
Notarization would need an Apple Developer ID certificate and an app-specific password,
like PhotoCraft's `APPLE_*` secrets. That is not set up.
