#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

APP_NAME="TextRotator"
BUILD_DIR="${ROOT_DIR}/build"
BUNDLE_DIR="${BUILD_DIR}/${APP_NAME}.app"
VOLUME_NAME="${APP_NAME}"

# -----------------------------------------------------------------------------
# 1. Version Resolution
# -----------------------------------------------------------------------------
if [ -n "${1:-}" ]; then
    VERSION="${1}"
elif [ -n "${VERSION:-}" ]; then
    VERSION="${VERSION}"
elif [ -f "${BUNDLE_DIR}/Contents/Info.plist" ]; then
    VERSION=$(defaults read "${BUNDLE_DIR}/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "1.0.0")
else
    GIT_TAG=$(git describe --tags --abbrev=0 2>/dev/null || true)
    if [ -n "${GIT_TAG}" ]; then
        VERSION="${GIT_TAG#v}"
    else
        VERSION="1.0.0"
    fi
fi

# Ensure app is built
if [ ! -d "${BUNDLE_DIR}" ]; then
    echo "⚠️  App bundle not found at ${BUNDLE_DIR}. Building it first..."
    "${ROOT_DIR}/scripts/build_app.sh" "${VERSION}"
fi

FINAL_DMG="${BUILD_DIR}/${APP_NAME}-${VERSION}.dmg"

echo "=========================================================="
echo "💿 Packaging macOS Disk Image (DMG)"
echo "   App:         ${BUNDLE_DIR}"
echo "   Version:     ${VERSION}"
echo "   Volume Name: ${VOLUME_NAME}"
echo "   Output:      ${FINAL_DMG}"
echo "=========================================================="

rm -f "${FINAL_DMG}"

# Determine whether GUI layout styling via Finder AppleScript can be used
USE_GUI=true
if [ "${CI:-false}" = "true" ] || [ "${GITHUB_ACTIONS:-false}" = "true" ] || ! pgrep -x "Finder" >/dev/null 2>&1; then
    USE_GUI=false
fi

TEMP_DIR=$(mktemp -d -t "textrotator_dmg_XXXXXX")
trap 'rm -rf "${TEMP_DIR}"' EXIT

STAGING_DIR="${TEMP_DIR}/staging"
mkdir -p "${STAGING_DIR}"

# Stage bundle and Applications symlink
echo "📁 Staging application bundle and /Applications symlink..."
cp -R "${BUNDLE_DIR}" "${STAGING_DIR}/${APP_NAME}.app"
ln -s /Applications "${STAGING_DIR}/Applications"

if [ "${USE_GUI}" = "true" ]; then
    echo "🎨 Configuring Finder window layout via AppleScript..."
    DMG_RW="${TEMP_DIR}/rw_temp.dmg"
    hdiutil create -size 80m -fs HFS+ -volname "${VOLUME_NAME}" -ov "${DMG_RW}" >/dev/null
    
    # Mount RW image
    MOUNT_OUTPUT=$(hdiutil attach -nobrowse -noverify -noautoopen "${DMG_RW}")
    MOUNT_DIR=$(echo "${MOUNT_OUTPUT}" | grep -E '/Volumes/' | awk -F'\t' '{print $NF}' | sed 's/^[ \t]*//')
    
    if [ -z "${MOUNT_DIR}" ] || [ ! -d "${MOUNT_DIR}" ]; then
        # Fallback parsing
        MOUNT_DIR="/Volumes/${VOLUME_NAME}"
    fi

    # Copy contents into mounted RW disk
    cp -R "${STAGING_DIR}/${APP_NAME}.app" "${MOUNT_DIR}/"
    ln -s /Applications "${MOUNT_DIR}/Applications"

    # AppleScript Finder layout
    set +e
    osascript <<APPLESCRIPT >/dev/null 2>&1
tell application "Finder"
    tell disk "${VOLUME_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {400, 150, 940, 470}
        set theViewOptions to the icon view options of container window
        set icon size of theViewOptions to 128
        set arrangement of theViewOptions to not arranged
        set position of item "${APP_NAME}.app" of container window to {130, 160}
        set position of item "Applications" of container window to {410, 160}
        close
        open
        update without registering applications
        delay 1
    end tell
end tell
APPLESCRIPT
    LAYOUT_STATUS=$?
    set -e

    if [ ${LAYOUT_STATUS} -ne 0 ]; then
        echo "ℹ️  Note: Finder layout script skipped or window server inactive."
    fi

    # Detach RW image safely
    sync
    sleep 1
    hdiutil detach "${MOUNT_DIR}" -quiet -force 2>/dev/null || (sleep 2 && hdiutil detach "${MOUNT_DIR}" -force)

    # Convert to compressed read-only UDZO image
    echo "🗜️  Converting to compressed UDZO disk image..."
    hdiutil convert "${DMG_RW}" -format UDZO -imagekey zlib-level=9 -o "${FINAL_DMG}" >/dev/null
    rm -f "${DMG_RW}"
else
    # Clean, direct, headless creation (optimal for CI runners)
    echo "🗜️  Creating compressed UDZO disk image directly (headless mode)..."
    hdiutil create \
        -volname "${VOLUME_NAME}" \
        -srcfolder "${STAGING_DIR}" \
        -ov \
        -format UDZO \
        -imagekey zlib-level=9 \
        "${FINAL_DMG}" >/dev/null
fi

# Optional code signing of the DMG if SIGNING_IDENTITY is provided
SIGNING_IDENTITY="${SIGNING_IDENTITY:-${DEVELOPER_ID_APPLICATION:--}}"
if [ "${SIGNING_IDENTITY}" != "-" ]; then
    echo "✍️  Signing disk image with Developer ID: ${SIGNING_IDENTITY}..."
    codesign --force --sign "${SIGNING_IDENTITY}" "${FINAL_DMG}"
fi

# Compute SHA256 & Size
SHA256=$(shasum -a 256 "${FINAL_DMG}" | awk '{print $1}')
FILE_SIZE=$(ls -lh "${FINAL_DMG}" | awk '{print $5}')

echo "=========================================================="
echo "✅ DMG successfully created!"
echo "   File:   ${FINAL_DMG} (${FILE_SIZE})"
echo "   SHA256: ${SHA256}"
echo "=========================================================="
