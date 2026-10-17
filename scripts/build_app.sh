#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

APP_NAME="TextRotator"
BUNDLE_DIR="${ROOT_DIR}/build/${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
ENTITLEMENTS="${ROOT_DIR}/Resources/TextRotator.entitlements"

# -----------------------------------------------------------------------------
# 1. Version and Architecture Resolution
# -----------------------------------------------------------------------------
# Marketing version (e.g. 1.0.1)
if [ -n "${1:-}" ]; then
    VERSION="${1}"
elif [ -n "${VERSION:-}" ]; then
    VERSION="${VERSION}"
else
    # Try latest git tag, or fallback to current Info.plist version, or 1.0.0
    GIT_TAG=$(git describe --tags --abbrev=0 2>/dev/null || true)
    if [ -n "${GIT_TAG}" ]; then
        VERSION="${GIT_TAG#v}"
    else
        VERSION=$(defaults read "${ROOT_DIR}/Resources/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "1.0.0")
    fi
fi

# Build number (e.g. 42 or commit count)
if [ -n "${2:-}" ]; then
    BUILD_NUMBER="${2}"
elif [ -n "${BUILD_NUMBER:-}" ]; then
    BUILD_NUMBER="${BUILD_NUMBER}"
else
    # Try git commit count, or fallback to Info.plist build number, or 1
    GIT_COUNT=$(git rev-list --count HEAD 2>/dev/null || true)
    if [ -n "${GIT_COUNT}" ] && [ "${GIT_COUNT}" -gt 0 ]; then
        BUILD_NUMBER="${GIT_COUNT}"
    else
        BUILD_NUMBER=$(defaults read "${ROOT_DIR}/Resources/Info.plist" CFBundleVersion 2>/dev/null || echo "1")
    fi
fi

# Target architecture: "arm64" (default) or "universal"
TARGET_ARCH="${3:-${ARCH:-arm64}}"

# Signing identity: "Developer ID Application: ..." or "-" for ad-hoc
SIGNING_IDENTITY="${SIGNING_IDENTITY:-${DEVELOPER_ID_APPLICATION:--}}"

echo "=========================================================="
echo "🏗️  Building ${APP_NAME}"
echo "   Marketing Version (CFBundleShortVersionString): ${VERSION}"
echo "   Build Number      (CFBundleVersion):            ${BUILD_NUMBER}"
echo "   Target Arch:                                    ${TARGET_ARCH}"
echo "   Signing Identity:                               ${SIGNING_IDENTITY}"
echo "=========================================================="

# -----------------------------------------------------------------------------
# 2. Compile Swift Executable
# -----------------------------------------------------------------------------
mkdir -p "${ROOT_DIR}/build"

if [ "${TARGET_ARCH}" = "universal" ]; then
    echo "🔨 Building universal binary (arm64 + x86_64)..."
    swift build -c release --triple arm64-apple-macosx
    swift build -c release --triple x86_64-apple-macosx
    TMP_EXEC="${ROOT_DIR}/build/${APP_NAME}_universal"
    lipo -create -output "${TMP_EXEC}" \
        ".build/arm64-apple-macosx/release/${APP_NAME}" \
        ".build/x86_64-apple-macosx/release/${APP_NAME}"
else
    echo "🔨 Building release binary (${TARGET_ARCH})..."
    swift build -c release
    TMP_EXEC=".build/release/${APP_NAME}"
fi

# -----------------------------------------------------------------------------
# 3. Assemble macOS Application Bundle
# -----------------------------------------------------------------------------
echo "📦 Assembling bundle: ${BUNDLE_DIR}..."
rm -rf "${BUNDLE_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# Binary
cp "${TMP_EXEC}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"
if [ "${TARGET_ARCH}" = "universal" ] && [ -f "${ROOT_DIR}/build/${APP_NAME}_universal" ]; then
    rm -f "${ROOT_DIR}/build/${APP_NAME}_universal"
fi

# Info.plist
cp "Resources/Info.plist" "${CONTENTS_DIR}/Info.plist"

# Inject dynamic versions into Info.plist
plutil -replace CFBundleShortVersionString -string "${VERSION}" "${CONTENTS_DIR}/Info.plist"
plutil -replace CFBundleVersion -string "${BUILD_NUMBER}" "${CONTENTS_DIR}/Info.plist"

# PkgInfo (Standard 8-byte file for macOS APPL bundles)
printf 'APPL????' > "${CONTENTS_DIR}/PkgInfo"

# App Icon
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

# -----------------------------------------------------------------------------
# 4. Code Signing
# -----------------------------------------------------------------------------
SIGN_ARGS=("--force" "--deep")

if [ -f "${ENTITLEMENTS}" ]; then
    SIGN_ARGS+=("--entitlements" "${ENTITLEMENTS}")
fi

if [ "${SIGNING_IDENTITY}" = "-" ]; then
    echo "✍️  Ad-hoc codesigning with stable Designated Requirement..."
    # Pin designated requirement to bundle identifier so TCC / Accessibility
    # permissions persist across version updates
    codesign "${SIGN_ARGS[@]}" -s - -r='designated => identifier "com.rulled.textrotator"' "${BUNDLE_DIR}"
else
    echo "✍️  Codesigning with Developer ID: ${SIGNING_IDENTITY}..."
    codesign "${SIGN_ARGS[@]}" --options runtime --timestamp -s "${SIGNING_IDENTITY}" "${BUNDLE_DIR}"
fi

# -----------------------------------------------------------------------------
# 5. Verification
# -----------------------------------------------------------------------------
echo "🔍 Verifying bundle signature and architecture..."
codesign --verify --deep --strict "${BUNDLE_DIR}"
file "${MACOS_DIR}/${APP_NAME}"

ACTUAL_VERSION=$(defaults read "${CONTENTS_DIR}/Info.plist" CFBundleShortVersionString)
ACTUAL_BUILD=$(defaults read "${CONTENTS_DIR}/Info.plist" CFBundleVersion)

echo "=========================================================="
echo "✅ Successfully built ${BUNDLE_DIR}"
echo "   Version: ${ACTUAL_VERSION} (${ACTUAL_BUILD})"
echo "   Binary:  $(file "${MACOS_DIR}/${APP_NAME}" | cut -d: -f2-)"
echo "   To launch:  open ${BUNDLE_DIR}"
echo "   To install: cp -R ${BUNDLE_DIR} /Applications/"
echo "=========================================================="
