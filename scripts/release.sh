#!/usr/bin/env bash
#
# Release Daisy to GitHub: build, sign, notarize, publish a GitHub release, and
# update the Sparkle appcast on the gh-pages branch (GitHub Pages).
#
# Usage:
#   scripts/release.sh                    Use version + build from Version.xcconfig
#   scripts/release.sh --version 0.0.2    Set marketing version (and bump build)
#   scripts/release.sh --version 0.0.2 --build 7
#   scripts/release.sh --beta             Appcast beta channel + GH prerelease
#   scripts/release.sh --draft            Build, sign, notarize only; publish nothing
#   scripts/release.sh --skip-github      Same as --draft
#
# Source of truth:
#   - Version.xcconfig  → MARKETING_VERSION, CURRENT_PROJECT_VERSION
#   - CHANGELOG.md      → release notes (## [X.Y.Z] – YYYY-MM-DD)
#
# Environment (all optional):
#   DAISY_TEAM_ID     Apple team used to sign (default: DEVELOPMENT_TEAM in the project)
#   NOTARY_PROFILE    notarytool keychain profile (default: md-preview-notary)
#   SPARKLE_BIN       Sparkle bin dir holding sign_update / generate_keys
#   SPARKLE_KEY_FILE  EdDSA private key file for sign_update (default: login Keychain)
#
# Requires: gh, jq, python3, Xcode, a Developer ID Application certificate for
# the team, a notarytool keychain profile, and Pages enabled on the gh-pages
# branch. Pages serves the appcast; Info.plist's SUFeedURL must point at it.
#
# The official homebrew/cask cask (markdown-preview) is autobumped by
# Homebrew from the GitHub release — no manual cask update needed.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"
VERSION_CONFIG="$PROJECT_ROOT/Version.xcconfig"
CHANGELOG="$PROJECT_ROOT/CHANGELOG.md"
PBXPROJ="$PROJECT_ROOT/daisy.xcodeproj/project.pbxproj"
INFO_PLIST="$PROJECT_ROOT/Info.plist"
SCHEME="daisy"
APP_NAME="Daisy"
PAGES_BRANCH="gh-pages"

VERSION_OVERRIDE=""
BUILD_OVERRIDE=""
BETA_FLAG=""
PUBLISH=true

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION_OVERRIDE="$2"; shift 2;;
        --build)   BUILD_OVERRIDE="$2";   shift 2;;
        --draft|--skip-github) PUBLISH=false; shift;;
        --beta)    BETA_FLAG="--beta";    shift;;
        -h|--help) sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# //;s/^#//'; exit 0;;
        *) echo "Unknown option: $1" >&2; exit 2;;
    esac
done

read_xcconfig() {
    grep "^$1" "$VERSION_CONFIG" | sed -E 's/^[A-Z_]+ *= *//'
}

write_xcconfig() {
    /usr/bin/sed -i '' -E "s|^$1 *=.*|$1 = $2|" "$VERSION_CONFIG"
}

extract_notes() {
    awk -v ver="$1" '
        $0 ~ "^## \\[" ver "\\]" { flag=1; next }
        flag && /^## \[/         { exit }
        flag                     { print }
    ' "$CHANGELOG" | awk 'NF{found=1} found' | sed -E '$ { /^[[:space:]]*$/d; }'
}

find_sparkle_bin() {
    if [[ -n "${SPARKLE_BIN:-}" ]]; then echo "$SPARKLE_BIN"; return; fi
    local dir
    for dir in "$HOME"/Library/Developer/Xcode/DerivedData/daisy-*/SourcePackages/artifacts/sparkle/Sparkle/bin; do
        [[ -x "$dir/sign_update" ]] && { echo "$dir"; return; }
    done
    return 1
}

# ── Resolve version ────────────────────────────────────────────────────────
if [[ -n "$VERSION_OVERRIDE" ]]; then
    VERSION="$VERSION_OVERRIDE"
else
    VERSION="$(read_xcconfig MARKETING_VERSION)"
fi

if [[ -n "$BUILD_OVERRIDE" ]]; then
    BUILD="$BUILD_OVERRIDE"
else
    CURRENT_BUILD="$(read_xcconfig CURRENT_PROJECT_VERSION)"
    if [[ -n "$VERSION_OVERRIDE" && "$VERSION_OVERRIDE" != "$(read_xcconfig MARKETING_VERSION)" ]]; then
        BUILD=$((CURRENT_BUILD + 1))
    else
        BUILD="$CURRENT_BUILD"
    fi
fi

[[ -z "$VERSION" ]] && { echo "error: could not resolve version" >&2; exit 1; }
[[ -z "$BUILD"   ]] && { echo "error: could not resolve build number" >&2; exit 1; }

TAG="v$VERSION"
TEAM_ID="${DAISY_TEAM_ID:-$(grep -m1 'DEVELOPMENT_TEAM = ' "$PBXPROJ" | sed -E 's/.*= *([A-Z0-9]+);.*/\1/')}"
NOTARY_PROFILE="${NOTARY_PROFILE:-md-preview-notary}"

echo "▸ Releasing $VERSION (build $BUILD)"

# ── Preflight ──────────────────────────────────────────────────────────────
echo "▸ Preflight checks"

git update-index --refresh >/dev/null 2>&1 || true
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    echo "  ✗ working tree is dirty — commit or stash first"
    git status --short
    exit 1
fi
echo "  ✓ working tree clean"

if ! grep -q "^## \[$VERSION\]" "$CHANGELOG"; then
    echo "  ✗ no CHANGELOG.md entry for [$VERSION]"
    echo "    add a section like:  ## [$VERSION] – $(date +%Y-%m-%d)"
    exit 1
fi
echo "  ✓ CHANGELOG.md entry found for $VERSION"

for tool in jq python3; do
    command -v "$tool" >/dev/null || { echo "  ✗ $tool not installed — brew install $tool"; exit 1; }
done

if ! SPARKLE_DIR="$(find_sparkle_bin)"; then
    echo "  ✗ Sparkle tools not found — build once in Xcode or set SPARKLE_BIN"
    exit 1
fi
echo "  ✓ Sparkle tools: $SPARKLE_DIR"

if [[ -z "$TEAM_ID" ]]; then
    echo "  ✗ no team id — set DAISY_TEAM_ID"
    exit 1
fi
SIGN_ID="$(security find-identity -v -p codesigning | grep "Developer ID Application:.*($TEAM_ID)" | head -1 | awk '{print $2}' || true)"
if [[ -z "$SIGN_ID" ]]; then
    echo "  ✗ no 'Developer ID Application' certificate for team $TEAM_ID in the keychain"
    echo "    (set DAISY_TEAM_ID to a team you hold a Developer ID certificate for)"
    exit 1
fi
echo "  ✓ Developer ID certificate for team $TEAM_ID"

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "  ✗ notarytool profile '$NOTARY_PROFILE' not usable"
    echo "    create it with: xcrun notarytool store-credentials $NOTARY_PROFILE"
    exit 1
fi
echo "  ✓ notarytool profile $NOTARY_PROFILE"

PLIST_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$INFO_PLIST" 2>/dev/null || true)"
if [[ -z "${SPARKLE_KEY_FILE:-}" ]]; then
    KEYCHAIN_KEY="$("$SPARKLE_DIR/generate_keys" -p 2>/dev/null || true)"
    if [[ -z "$KEYCHAIN_KEY" || "$KEYCHAIN_KEY" != "$PLIST_KEY" ]]; then
        echo "  ✗ Keychain EdDSA key does not match SUPublicEDKey in Info.plist"
        echo "    updates signed with it would be rejected by installed apps"
        exit 1
    fi
    echo "  ✓ Sparkle EdDSA key matches SUPublicEDKey"
else
    [[ -f "$SPARKLE_KEY_FILE" ]] || { echo "  ✗ SPARKLE_KEY_FILE not found"; exit 1; }
    echo "  ✓ using Sparkle key file (SUPublicEDKey match not checked)"
fi

if $PUBLISH; then
    command -v gh >/dev/null || { echo "  ✗ gh CLI not installed — brew install gh, or pass --draft"; exit 1; }
    gh auth status >/dev/null 2>&1 || { echo "  ✗ gh not authenticated — run: gh auth login"; exit 1; }
    git remote get-url origin >/dev/null 2>&1 || { echo "  ✗ no git remote 'origin'"; exit 1; }
    REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
    OWNER="${REPO%%/*}"; REPO_NAME="${REPO##*/}"
    FEED_URL="https://$OWNER.github.io/$REPO_NAME/appcast.xml"
    PLIST_FEED="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$INFO_PLIST" 2>/dev/null || true)"
    if [[ "$PLIST_FEED" != "$FEED_URL" ]]; then
        echo "  ⚠ Info.plist SUFeedURL is $PLIST_FEED"
        echo "    installed apps will not see this release until it is $FEED_URL"
    fi
    if gh release view "$TAG" >/dev/null 2>&1; then
        echo "  ✗ GitHub release $TAG already exists — roll it back first"
        exit 1
    fi
    echo "  ✓ gh ready ($REPO)"
fi

# ── Sync Version.xcconfig ──────────────────────────────────────────────────
CURRENT_VERSION="$(read_xcconfig MARKETING_VERSION)"
CURRENT_BUILD="$(read_xcconfig CURRENT_PROJECT_VERSION)"

if [[ "$CURRENT_VERSION" != "$VERSION" || "$CURRENT_BUILD" != "$BUILD" ]]; then
    echo "▸ Updating Version.xcconfig: $CURRENT_VERSION ($CURRENT_BUILD) → $VERSION ($BUILD)"
    write_xcconfig MARKETING_VERSION "$VERSION"
    write_xcconfig CURRENT_PROJECT_VERSION "$BUILD"
    git add "$VERSION_CONFIG"
    git commit -m "Release $VERSION ($BUILD)" >/dev/null
    echo "  ✓ committed Version.xcconfig"
fi

# ── Extract release notes ──────────────────────────────────────────────────
NOTES="$(extract_notes "$VERSION")"
if [[ -z "$NOTES" ]]; then
    echo "error: empty CHANGELOG.md body for [$VERSION]" >&2
    exit 1
fi
WORK="$(mktemp -d)"
printf '%s\n' "$NOTES" > "$WORK/notes.md"

# ── Archive + export (Developer ID) ────────────────────────────────────────
# DEVELOPMENT_TEAM is overridden on the command line only; project.pbxproj is
# never rewritten.
echo "▸ Archiving"
xcodebuild -project daisy.xcodeproj -scheme "$SCHEME" -configuration Release \
    -archivePath "$WORK/$APP_NAME.xcarchive" DEVELOPMENT_TEAM="$TEAM_ID" \
    -quiet archive

cat > "$WORK/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>$TEAM_ID</string>
    <key>signingStyle</key><string>automatic</string>
</dict></plist>
PLIST

echo "▸ Exporting"
xcodebuild -exportArchive -archivePath "$WORK/$APP_NAME.xcarchive" \
    -exportOptionsPlist "$WORK/ExportOptions.plist" -exportPath "$WORK/export" -quiet
APP="$WORK/export/$APP_NAME.app"
MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist")"

# ── DMG, sign, notarize, staple ────────────────────────────────────────────
DMG="$WORK/$APP_NAME-$VERSION.dmg"
echo "▸ Building DMG"
STAGE="$WORK/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
codesign --force --sign "$SIGN_ID" --timestamp "$DMG"

echo "▸ Notarizing (this can take a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

# ── Sparkle signature ──────────────────────────────────────────────────────
echo "▸ Signing update with Sparkle"
SIGN_ARGS=()
[[ -n "${SPARKLE_KEY_FILE:-}" ]] && SIGN_ARGS=(-f "$SPARKLE_KEY_FILE")
SIGN_OUTPUT="$("$SPARKLE_DIR/sign_update" ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} "$DMG")"
SIGNATURE="$(sed -nE 's/.*sparkle:edSignature="([^"]+)".*/\1/p' <<<"$SIGN_OUTPUT")"
LENGTH="$(stat -f%z "$DMG")"
[[ -n "$SIGNATURE" ]] || { echo "✗ could not parse sign_update output: $SIGN_OUTPUT" >&2; exit 1; }

if ! $PUBLISH; then
    echo "✓ Built $VERSION ($BUILD). Nothing published."
    echo "  DMG: $DMG"
    exit 0
fi

# ── GitHub release (before the appcast, so the feed never 404s) ────────────
echo "▸ Creating tag $TAG"
if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "  ⚠ tag $TAG already exists locally — reusing"
else
    git tag -a "$TAG" -m "Release $VERSION ($BUILD)"
fi
git push origin "$TAG"

PRERELEASE_FLAG=()
[[ -n "$BETA_FLAG" ]] && PRERELEASE_FLAG=(--prerelease)
echo "▸ Creating GitHub release $TAG"
gh release create "$TAG" "$DMG" \
    --title "$APP_NAME $VERSION" \
    --notes-file "$WORK/notes.md" \
    ${PRERELEASE_FLAG[@]+"${PRERELEASE_FLAG[@]}"}
DMG_URL="https://github.com/$REPO/releases/download/$TAG/$APP_NAME-$VERSION.dmg"

# ── Appcast on gh-pages ────────────────────────────────────────────────────
echo "▸ Updating appcast on $PAGES_BRANCH"
PAGES="$WORK/pages"
if git ls-remote --exit-code --heads origin "$PAGES_BRANCH" >/dev/null 2>&1; then
    git clone --quiet --branch "$PAGES_BRANCH" --single-branch "$(git remote get-url origin)" "$PAGES"
else
    mkdir -p "$PAGES"
    git -C "$PAGES" init --quiet -b "$PAGES_BRANCH"
    git -C "$PAGES" remote add origin "$(git remote get-url origin)"
    touch "$PAGES/.nojekyll"
fi

"$PROJECT_ROOT/scripts/appcast.py" add "$PAGES/appcast.xml" \
    --version "$VERSION" --build "$BUILD" --url "$DMG_URL" \
    --length "$LENGTH" --signature "$SIGNATURE" --min-os "$MIN_OS" \
    --notes-file "$WORK/notes.md" --feed-title "$APP_NAME" \
    --feed-link "https://github.com/$REPO" $BETA_FLAG

git -C "$PAGES" add -A
git -C "$PAGES" commit --quiet -m "Appcast: $VERSION ($BUILD)"
git -C "$PAGES" push --quiet origin "$PAGES_BRANCH"

echo "✓ Released $VERSION ($BUILD)"
echo "  GitHub:  https://github.com/$REPO/releases/tag/$TAG"
echo "  Appcast: $FEED_URL"
echo "  (Pages must be enabled for the $PAGES_BRANCH branch — repo Settings → Pages)"
