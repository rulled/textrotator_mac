#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

APP_NAME="TextRotator"
BUILD_DIR="${ROOT_DIR}/build"

# Version and build number resolution
VERSION="${1:-${VERSION:-}}"
BUILD_NUMBER="${2:-${BUILD_NUMBER:-}}"
TARGET_ARCH="${3:-${ARCH:-arm64}}"

# If version is empty, extract from git or Info.plist
if [ -z "${VERSION}" ]; then
    GIT_TAG=$(git describe --tags --abbrev=0 2>/dev/null || true)
    if [ -n "${GIT_TAG}" ]; then
        VERSION="${GIT_TAG#v}"
    else
        VERSION=$(defaults read "${ROOT_DIR}/Resources/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "1.0.0")
    fi
fi

if [ -z "${BUILD_NUMBER}" ]; then
    GIT_COUNT=$(git rev-list --count HEAD 2>/dev/null || true)
    if [ -n "${GIT_COUNT}" ] && [ "${GIT_COUNT}" -gt 0 ]; then
        BUILD_NUMBER="${GIT_COUNT}"
    else
        BUILD_NUMBER=$(defaults read "${ROOT_DIR}/Resources/Info.plist" CFBundleVersion 2>/dev/null || echo "1")
    fi
fi

echo "=========================================================="
echo "🚀 Starting Full Packaging Pipeline for ${APP_NAME}"
echo "   Target Version:      ${VERSION}"
echo "   Target Build Number: ${BUILD_NUMBER}"
echo "   Architecture:        ${TARGET_ARCH}"
echo "=========================================================="

# 1. Build .app bundle
"${ROOT_DIR}/scripts/build_app.sh" "${VERSION}" "${BUILD_NUMBER}" "${TARGET_ARCH}"

# 2. Package DMG installer
"${ROOT_DIR}/scripts/package_dmg.sh" "${VERSION}"

# 3. Package Zip archives (for in-app updater)
"${ROOT_DIR}/scripts/package_zip.sh" "${VERSION}"

# 4. Summary & Checksums
DMG_FILE="${BUILD_DIR}/${APP_NAME}-${VERSION}.dmg"
ZIP_FILE="${BUILD_DIR}/${APP_NAME}-${VERSION}.zip"
APP_ZIP_FILE="${BUILD_DIR}/${APP_NAME}.app.zip"

echo ""
echo "=========================================================="
echo "🎉 Packaging Complete! Release Artifacts Summary:"
echo "=========================================================="
printf "%-35s %-10s %s\n" "Artifact" "Size" "SHA-256"
printf "%-35s %-10s %s\n" "-----------------------------------" "----------" "----------------------------------------------------------------"

for FILE in "${DMG_FILE}" "${ZIP_FILE}" "${APP_ZIP_FILE}"; do
    if [ -f "${FILE}" ]; then
        F_NAME=$(basename "${FILE}")
        F_SIZE=$(ls -lh "${FILE}" | awk '{print $5}')
        F_SHA=$(shasum -a 256 "${FILE}" | awk '{print $1}')
        printf "%-35s %-10s %s\n" "${F_NAME}" "${F_SIZE}" "${F_SHA}"
    fi
done

echo "=========================================================="
echo "All distribution artifacts are ready in: ${BUILD_DIR}/"
echo "=========================================================="
