#!/bin/bash
# The version lives in the VERSION file at the repo root and nowhere else.
#   scripts/version.sh                prints the current version
#   scripts/version.sh set 0.2.0      sets it (0.2.0-rc.1 for a test build)
#   scripts/version.sh bump minor     0.1.0 -> 0.2.0 (new features)
#   scripts/version.sh bump patch     0.2.0 -> 0.2.1 (fixes only)
set -euo pipefail
cd "$(dirname "$0")/.."

valid='^[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$'
current="$(cat VERSION)"

case "${1:-}" in
  "")
    echo "$current"
    ;;
  set)
    [[ "${2:-}" =~ $valid ]] || { echo "Version must look like 0.2.0 or 0.2.0-rc.1" >&2; exit 2; }
    echo "$2" > VERSION
    echo "$2"
    ;;
  bump)
    base="${current%%-*}"
    IFS=. read -r major minor patch <<< "$base"
    case "${2:-}" in
      minor) next="$major.$((minor + 1)).0" ;;
      patch) next="$major.$minor.$((patch + 1))" ;;
      *) echo "Usage: version.sh bump minor|patch" >&2; exit 2 ;;
    esac
    echo "$next" > VERSION
    echo "$next"
    ;;
  *)
    echo "Usage: version.sh [set <version> | bump minor|patch]" >&2
    exit 2
    ;;
esac
