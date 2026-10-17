#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

APP_NAME="TextRotator"
BUILD_DIR="${ROOT_DIR}/build"
BUNDLE_DIR="${BUILD_DIR}/${APP_NAME}.app"

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

OUTPUT_VERSIONED_ZIP="${BUILD_DIR}/${APP_NAME}-${VERSION}.zip"
OUTPUT_GENERIC_ZIP="${BUILD_DIR}/${APP_NAME}.app.zip"
OUTPUT_PLAIN_ZIP="${BUILD_DIR}/${APP_NAME}.zip"

echo "=========================================================="
echo "📦 Packaging Zip Archive"
echo "   App:     ${BUNDLE_DIR}"
echo "   Version: ${VERSION}"
echo "   Output:  ${OUTPUT_VERSIONED_ZIP}"
echo "=========================================================="

rm -f "${OUTPUT_VERSIONED_ZIP}" "${OUTPUT_GENERIC_ZIP}" "${OUTPUT_PLAIN_ZIP}"

# Use ditto to preserve macOS metadata, extended attributes, symlinks, and code signature
echo "🗜️  Compressing bundle using /usr/bin/ditto..."
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "${BUNDLE_DIR}" "${OUTPUT_VERSIONED_ZIP}"

# Create convenience copies / links for in-app updaters
cp "${OUTPUT_VERSIONED_ZIP}" "${OUTPUT_GENERIC_ZIP}"
cp "${OUTPUT_VERSIONED_ZIP}" "${OUTPUT_PLAIN_ZIP}"

# Compute SHA256
SHA256=$(shasum -a 256 "${OUTPUT_VERSIONED_ZIP}" | awk '{print $1}')
FILE_SIZE=$(ls -lh "${OUTPUT_VERSIONED_ZIP}" | awk '{print $5}')

echo "=========================================================="
echo "✅ Zip archive successfully created!"
echo "   File:   ${OUTPUT_VERSIONED_ZIP} (${FILE_SIZE})"
echo "   SHA256: ${SHA256}"
echo "   Aliases: ${OUTPUT_GENERIC_ZIP}, ${OUTPUT_PLAIN_ZIP}"
echo "=========================================================="
