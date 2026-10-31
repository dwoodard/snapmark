#!/bin/bash
# Installs the latest Snapmark release from the terminal:
#
#   curl -fsSL https://raw.githubusercontent.com/dwoodard/snapmark/HEAD/scripts/install.sh | bash
#
# Why a script: files downloaded with curl are not quarantined, so macOS does not show the
# "Apple could not verify..." block that a browser download triggers for an unnotarized app.
# Running this is you choosing to trust Snapmark, so read it first if you like. It:
#   1. finds the latest release (or SNAPMARK_VERSION=0.1.2 to pin one)
#   2. downloads the zip and checks it against the release's SHA256SUMS.txt
#   3. checks the app's code signature
#   4. quits a running Snapmark, replaces /Applications/Snapmark.app (or ~/Applications if that is not writable)
#   5. opens it
# No sudo, nothing else is touched. To uninstall, delete Snapmark.app.
set -euo pipefail

REPO="dwoodard/snapmark"
TMP=""

die() { echo "error: $*" >&2; exit 1; }
cleanup() { [[ -n "$TMP" ]] && rm -rf "$TMP"; return 0; }

# true when version $1 is at least $2
version_ge() { [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" == "$2" ]]; }

main() {
    [[ "$(uname -s)" == "Darwin" ]] || die "Snapmark is for macOS."
    local os
    os="$(sw_vers -productVersion)"
    version_ge "$os" 15.2 || die "Snapmark needs macOS 15.2 or later (this Mac has $os)."
    for tool in curl shasum ditto codesign; do
        command -v "$tool" >/dev/null || die "$tool is required but was not found."
    done

    local tag version
    if [[ -n "${SNAPMARK_VERSION:-}" ]]; then
        version="${SNAPMARK_VERSION#v}"
        tag="v$version"
    else
        # /releases/latest redirects to /releases/tag/<tag>. No API call, so no rate limit or token.
        tag="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest")" \
            || die "Could not reach GitHub."
        tag="${tag##*/}"
        version="${tag#v}"
    fi
    [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$ ]] || die "Could not find a Snapmark release."

    TMP="$(mktemp -d)"
    trap cleanup EXIT
    local base="https://github.com/$REPO/releases/download/$tag"
    local zip="snapmark-$version-macos-universal.zip"

    echo "Downloading Snapmark $version..."
    curl -fsSL -o "$TMP/$zip" "$base/$zip" || die "Could not download $zip."
    curl -fsSL -o "$TMP/SHA256SUMS.txt" "$base/SHA256SUMS.txt" || die "Could not download SHA256SUMS.txt."

    (cd "$TMP" && grep " $zip\$" SHA256SUMS.txt | shasum -a 256 -c - >/dev/null 2>&1) \
        || die "Checksum does not match. Not installing."
    echo "Checksum ok."

    ditto -x -k "$TMP/$zip" "$TMP/out"
    codesign -v "$TMP/out/Snapmark.app" 2>/dev/null || die "The app's signature is invalid. Not installing."

    local dest="${SNAPMARK_DIR:-/Applications}"
    if [[ ! -w "$dest" ]]; then
        dest="$HOME/Applications"
        mkdir -p "$dest"
    fi

    if pgrep -qx Snapmark; then
        echo "Quitting the running Snapmark..."
        pkill -x Snapmark || true
        sleep 1
    fi

    rm -rf "$dest/Snapmark.app"
    ditto "$TMP/out/Snapmark.app" "$dest/Snapmark.app"
    xattr -dr com.apple.quarantine "$dest/Snapmark.app" 2>/dev/null || true
    echo "Installed $dest/Snapmark.app ($version)."

    open "$dest/Snapmark.app"
    cat <<MSG

Snapmark is running (look for the camera icon in the menu bar).
Grant Accessibility and Input Monitoring in System Settings > Privacy & Security when asked.
Screen Recording is requested on your first capture, then reopen Snapmark once.
MSG
}

# Everything is inside main, so a download cut off halfway through can never run half a script.
main "$@"
