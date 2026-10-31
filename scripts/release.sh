#!/bin/bash
# Builds a universal, signed Snapmark.app, packages it as a DMG and a zip with a checksum file, and creates or updates
# a DRAFT GitHub release named "Snapmark v<version>". Nothing is public until you publish the draft.
#   --dry-run   build and package into dist/ only, no GitHub calls
# The version comes from the VERSION file. SNAPMARK_VERSION overrides it for a test run.
set -euo pipefail
cd "$(dirname "$0")/.."

DRY=0
[[ "${1:-}" == "--dry-run" ]] && DRY=1

VERSION="${SNAPMARK_VERSION:-$(cat VERSION)}"
TAG="v$VERSION"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$ ]] || { echo "Bad version: $VERSION" >&2; exit 2; }

if [[ "$DRY" == 0 ]]; then
    command -v gh >/dev/null || { echo "gh is required" >&2; exit 1; }
    # A published version is never touched again.
    if [[ "$(gh release view "$TAG" --json isDraft --jq .isDraft 2>/dev/null || true)" == "false" ]]; then
        echo "$TAG is already published. Bump the version first: scripts/version.sh bump minor|patch" >&2
        exit 1
    fi
    # The tag is created from this commit when the draft is published, so GitHub must have it.
    git fetch --quiet origin 2>/dev/null || true
    if [[ -z "$(git branch -r --contains HEAD 2>/dev/null)" ]]; then
        echo "HEAD is not on GitHub yet. Push the branch first." >&2
        exit 1
    fi
fi

SNAPMARK_VERSION="$VERSION" ./scripts/build-app.sh --universal

rm -rf dist
mkdir -p dist
ZIP="snapmark-$VERSION-macos-universal.zip"
DMG="snapmark-$VERSION-macos-universal.dmg"
ditto -c -k --keepParent build/Snapmark.app "dist/$ZIP"
./scripts/make-dmg.sh build/Snapmark.app "dist/$DMG"
(cd dist && shasum -a 256 "$DMG" "$ZIP" > SHA256SUMS.txt)
echo "Packaged dist/$DMG and dist/$ZIP"

if [[ "$DRY" == 1 ]]; then
    echo "Dry run: skipped GitHub."
    exit 0
fi

PRE=()
[[ "$VERSION" == *-* ]] && PRE=(--prerelease)

NOTES="Open the **DMG** and drag **Snapmark** to Applications. (The zip holds the same app.)

Snapmark is not notarized yet, so macOS blocks the first launch (\"Apple could not verify Snapmark is free of malware\"). Open **System Settings > Privacy & Security**, scroll to **Security**, and click **Open Anyway** next to Snapmark. On macOS 15 and later, right-click > Open no longer works. Or run \`xattr -dr com.apple.quarantine /Applications/Snapmark.app\`. Then grant Accessibility, Input Monitoring and Screen Recording when asked. Verify the download against \`SHA256SUMS.txt\`.

Requires macOS 15.2 or later."

if gh release view "$TAG" >/dev/null 2>&1; then
    gh release upload "$TAG" "dist/$DMG" "dist/$ZIP" dist/SHA256SUMS.txt --clobber
    echo "Updated the draft $TAG."
else
    gh release create "$TAG" "dist/$DMG" "dist/$ZIP" dist/SHA256SUMS.txt \
        --draft ${PRE[@]+"${PRE[@]}"} \
        --target "$(git rev-parse HEAD)" \
        --title "Snapmark v$VERSION" \
        --notes "$NOTES" \
        --generate-notes
    echo "Created the draft $TAG. Check it, then publish it on GitHub."
fi
