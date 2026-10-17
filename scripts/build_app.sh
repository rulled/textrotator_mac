#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

APP_NAME="TextRotator"
BUNDLE_DIR="${ROOT_DIR}/build/${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "🔨 Building ${APP_NAME} in release mode..."
swift build -c release

echo "📦 Assembling macOS Application Bundle: ${BUNDLE_DIR}..."
rm -rf "${BUNDLE_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# 1. Copy release binary
cp ".build/release/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

# 2. Copy Info.plist
cp "Resources/Info.plist" "${CONTENTS_DIR}/Info.plist"

# 3. Copy Icon
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

# 4. Ad-hoc codesign bundle for macOS Gatekeeper and Accessibility
echo "✍️  Codesigning ${BUNDLE_DIR}..."
codesign --force --deep -s - "${BUNDLE_DIR}"

# 5. Verification
echo "🔍 Verifying codesignature..."
codesign --verify --deep --strict "${BUNDLE_DIR}"

echo "✅ Successfully built ${BUNDLE_DIR}"
echo "   To launch: open ${BUNDLE_DIR}"
echo "   To install: cp -R ${BUNDLE_DIR} /Applications/"
