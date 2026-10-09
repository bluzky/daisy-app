#!/usr/bin/env bash
#
# Roll back a Daisy release.
#
# Removes the version from the Sparkle appcast on the gh-pages branch (so
# installed apps stop being offered it) and deletes the matching GitHub
# release + tag.
#
# Usage:
#   scripts/rollback-release.sh <version>            Roll back a specific version
#   scripts/rollback-release.sh --latest             Roll back the most recent release
#   scripts/rollback-release.sh 0.0.2 --keep-github  Leave GitHub release in place
#   scripts/rollback-release.sh --latest --yes       Skip confirmation prompt
#
# Apps that already installed the release are not downgraded; ship a newer
# build to supersede it.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"
PAGES_BRANCH="gh-pages"

VERSION=""
USE_LATEST=false
KEEP_GH=false
YES=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --latest)      USE_LATEST=true;  shift;;
        --keep-github) KEEP_GH=true;     shift;;
        --yes|-y)      YES=true;         shift;;
        -h|--help)     sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# //;s/^#//'; exit 0;;
        -*)            echo "unknown flag: $1" >&2; exit 2;;
        *)             VERSION="$1";     shift;;
    esac
done

for tool in gh python3; do
    command -v "$tool" >/dev/null || { echo "✗ $tool not installed" >&2; exit 1; }
done
gh auth status >/dev/null 2>&1 || { echo "✗ gh not authenticated — run: gh auth login" >&2; exit 1; }
git remote get-url origin >/dev/null 2>&1 || { echo "✗ no git remote 'origin'" >&2; exit 1; }
ORIGIN="$(git remote get-url origin)"

if ! git ls-remote --exit-code --heads origin "$PAGES_BRANCH" >/dev/null 2>&1; then
    echo "✗ no $PAGES_BRANCH branch on origin — nothing to roll back" >&2
    exit 1
fi

WORK="$(mktemp -d)"
git clone --quiet --branch "$PAGES_BRANCH" --single-branch "$ORIGIN" "$WORK/pages"
FEED="$WORK/pages/appcast.xml"
[[ -f "$FEED" ]] || { echo "✗ appcast.xml missing on $PAGES_BRANCH" >&2; exit 1; }

# ── Resolve target version ─────────────────────────────────────────────────
# The appcast lists newest first.
VERSIONS="$(sed -nE 's|.*<sparkle:shortVersionString>([^<]+)</sparkle:shortVersionString>.*|\1|p' "$FEED")"
if [[ -z "$VERSIONS" ]]; then
    echo "✗ no releases in the appcast" >&2
    exit 1
fi

if $USE_LATEST; then
    VERSION="$(head -1 <<<"$VERSIONS")"
fi

if [[ -z "$VERSION" ]]; then
    echo "error: pass a version (e.g. 0.0.2) or --latest" >&2
    exit 2
fi

if ! grep -qxF "$VERSION" <<<"$VERSIONS"; then
    echo "✗ no release found for version $VERSION. In the appcast:" >&2
    echo "$VERSIONS" >&2
    exit 1
fi

TAG="v$VERSION"

# ── Confirm ────────────────────────────────────────────────────────────────
echo "▸ Target: $VERSION"
echo "  Action: remove from the appcast on $PAGES_BRANCH"
if ! $KEEP_GH; then
    echo "  Action: delete GitHub release + tag $TAG"
fi
echo ""

if ! $YES; then
    read -rp "Continue? [y/N] " ans
    case "$ans" in [yY]|[yY][eE][sS]) ;; *) echo "aborted"; exit 1;; esac
fi

# ── Roll back the appcast (first, so no one is offered a deleted DMG) ──────
echo "▸ Removing $VERSION from the appcast"
"$PROJECT_ROOT/scripts/appcast.py" remove "$FEED" --version "$VERSION"
git -C "$WORK/pages" add -A
git -C "$WORK/pages" commit --quiet -m "Appcast: remove $VERSION"
git -C "$WORK/pages" push --quiet origin "$PAGES_BRANCH"

# ── Roll back on GitHub ────────────────────────────────────────────────────
if ! $KEEP_GH; then
    if gh release view "$TAG" >/dev/null 2>&1; then
        echo "▸ Deleting GitHub release $TAG"
        gh release delete "$TAG" --yes --cleanup-tag 2>/dev/null \
            || gh release delete "$TAG" --yes
    else
        echo "  ⚠ no GitHub release for $TAG"
    fi
    # Best-effort tag cleanup if --cleanup-tag was unsupported
    if git rev-parse "$TAG" >/dev/null 2>&1; then
        git tag -d "$TAG" >/dev/null
        git push origin ":refs/tags/$TAG" >/dev/null 2>&1 || true
        echo "▸ Removed local + remote tag $TAG"
    fi
fi

echo "✓ Rolled back $VERSION"
