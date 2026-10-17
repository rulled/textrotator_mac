#!/usr/bin/env bash
# ==============================================================================
# scripts/release.sh
#
# Dual-Mode Unified Release Orchestrator for TextRotator macOS
#
# Modes:
#   1. CI Mode (Default):
#      - Validates CHANGELOG.md for the requested version
#      - Runs swift test suite
#      - Bumps version and build number in Resources/Info.plist
#      - Commits and creates annotated git tag (vX.Y.Z)
#      - Pushes commit and tag to GitHub origin
#      - GitHub Actions (.github/workflows/release.yml) compiles release binary,
#        builds DMG and Zip, extracts release notes, and publishes the release.
#
#   2. Local Mode (--local-build / -l):
#      - Performs all validations and tagging as in CI Mode
#      - Compiles and packages TextRotator.app, TextRotator-<ver>.dmg,
#        TextRotator-<ver>.zip, and TextRotator.app.zip locally via scripts/package.sh
#      - Calculates SHA-256 checksums
#      - Extracts release notes from CHANGELOG.md
#      - Publishes GitHub Release immediately via GitHub CLI (gh release create)
#      - Pushes commit and tag to origin
#
# Usage:
#   ./scripts/release.sh <version> [options]
#   ./scripts/release.sh 1.0.1
#   ./scripts/release.sh 1.0.1 --local-build
#   ./scripts/release.sh 1.0.1 --dry-run
# ==============================================================================

set -euo pipefail

# --- Color Formatting ---
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    BOLD=''
    RESET=''
fi

log_info()    { printf "${BLUE}ℹ️  %s${RESET}\n" "$1"; }
log_success() { printf "${GREEN}✅ %s${RESET}\n" "$1"; }
log_warn()    { printf "${YELLOW}⚠️  %s${RESET}\n" "$1"; }
log_step()    { printf "\n${CYAN}${BOLD}▶ %s${RESET}\n" "$1"; }
log_error()   { printf "${RED}${BOLD}❌ ERROR: %s${RESET}\n" "$1" >&2; }

# --- Directories ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

# --- Usage Banner ---
usage() {
    cat <<EOF
${BOLD}TextRotator Release Orchestrator${RESET}

${BOLD}USAGE:${RESET}
  ./scripts/release.sh <version> [options]

${BOLD}ARGUMENTS:${RESET}
  <version>               Semantic release version (e.g. 1.0.1 or v1.0.1)

${BOLD}OPTIONS:${RESET}
  -l, --local-build       Compile, package DMG/Zip locally and publish via gh CLI
  -n, --dry-run           Simulate release process without modifying git or GitHub
  -d, --draft             Create release as a draft on GitHub
  -p, --prerelease        Mark release as a pre-release on GitHub
  --no-push               Skip pushing git branch and tag to remote
  --skip-tests            Skip running 'swift test' prior to release
  -f, --force             Bypass working tree cleanliness checks (use with care)
  -h, --help              Show this help message

${BOLD}EXAMPLES:${RESET}
  # Standard CI trigger (recommended for team workflow):
  ./scripts/release.sh 1.0.1

  # Local build & instant GitHub release upload:
  ./scripts/release.sh 1.0.1 --local-build

  # Dry run to preview actions:
  ./scripts/release.sh 1.0.1 --dry-run
EOF
}

# --- Parse Arguments ---
RAW_VERSION=""
LOCAL_BUILD=0
DRY_RUN=0
DRAFT=0
PRERELEASE=0
NO_PUSH=0
SKIP_TESTS=0
FORCE=0

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -l|--local-build)
            LOCAL_BUILD=1
            ;;
        -n|--dry-run)
            DRY_RUN=1
            ;;
        -d|--draft)
            DRAFT=1
            ;;
        -p|--prerelease)
            PRERELEASE=1
            ;;
        --no-push)
            NO_PUSH=1
            ;;
        --skip-tests)
            SKIP_TESTS=1
            ;;
        -f|--force)
            FORCE=1
            ;;
        -*)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            if [ -z "$RAW_VERSION" ]; then
                RAW_VERSION="$1"
            else
                log_error "Unexpected argument: $1"
                usage
                exit 1
            fi
            ;;
    esac
    shift
done

if [ -z "$RAW_VERSION" ]; then
    log_error "Missing version argument."
    usage
    exit 1
fi

# Normalize version (strip leading 'v')
VERSION="${RAW_VERSION#v}"
VERSION="${VERSION#V}"
TAG="v${VERSION}"

# Validate semantic version format (e.g. 1.0.1 or 1.0.1-beta.1)
SEMVER_REGEX='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'
if ! [[ "$VERSION" =~ $SEMVER_REGEX ]]; then
    log_error "Invalid semantic version format: '${VERSION}'. Expected X.Y.Z (e.g. 1.0.1)"
    exit 1
fi

echo "========================================================================"
echo " 🚀 TextRotator Release Pipeline: ${BOLD}${TAG}${RESET} (v${VERSION})"
echo " Mode: $([ "$LOCAL_BUILD" -eq 1 ] && echo "${CYAN}Local Build & Publish${RESET}" || echo "${GREEN}Cloud CI/CD Release${RESET}")"
[ "$DRY_RUN" -eq 1 ] && echo " ${YELLOW}*** DRY RUN MODE: No git or remote modifications will be made ***${RESET}"
echo "========================================================================"

# --- Step 1: Pre-flight Environment Checks ---
log_step "1. Pre-flight Environment Checks"

# Git repository check
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    log_error "Current directory is not a git repository."
    exit 1
fi

CURRENT_BRANCH=$(git branch --show-current || echo "HEAD")
log_info "Current git branch: ${BOLD}${CURRENT_BRANCH}${RESET}"

# Working tree cleanliness
if [ "$FORCE" -eq 0 ]; then
    if ! git diff-index --quiet HEAD -- 2>/dev/null; then
        log_error "Working tree has unstaged or uncommitted changes. Please commit, stash, or pass --force."
        git status --short
        exit 1
    fi
    log_success "Working tree is clean."
else
    log_warn "Force flag enabled: bypassing working tree check."
fi

# Check tag collision
if git rev-parse "${TAG}" >/dev/null 2>&1; then
    log_error "Git tag '${TAG}' already exists locally! Use a new version or delete existing tag first."
    exit 1
fi

# Remote origin check
REMOTE_URL=$(git remote get-url origin 2>/dev/null || true)
if [ -z "$REMOTE_URL" ]; then
    log_warn "No git remote 'origin' configured. Remote push will not be possible until added."
else
    log_success "Git remote origin: ${REMOTE_URL}"
fi

# If local build, verify gh CLI
if [ "$LOCAL_BUILD" -eq 1 ]; then
    if ! command -v gh >/dev/null 2>&1; then
        log_error "GitHub CLI ('gh') is required for --local-build. Please install via 'brew install gh'."
        exit 1
    fi
    if ! gh auth status >/dev/null 2>&1; then
        log_error "GitHub CLI is not authenticated. Please run 'gh auth login' first."
        exit 1
    fi
    log_success "GitHub CLI authenticated."
fi

# --- Step 2: Mandatory Changelog Validation ---
log_step "2. Mandatory Changelog Validation"

if [ -f "${ROOT_DIR}/scripts/check_changelog.sh" ]; then
    chmod +x "${ROOT_DIR}/scripts/check_changelog.sh"
    if ! "${ROOT_DIR}/scripts/check_changelog.sh" "${VERSION}"; then
        log_error "Changelog validation failed for version ${VERSION}!"
        exit 1
    fi
else
    log_warn "scripts/check_changelog.sh not found. Checking CHANGELOG.md directly..."
    if [ ! -f "CHANGELOG.md" ] || ! grep -E "^## \[(v?)${VERSION}\]" CHANGELOG.md >/dev/null 2>&1; then
        log_error "Release aborted: version ${VERSION} entry not found in CHANGELOG.md!"
        exit 1
    fi
    log_success "Changelog entry found in CHANGELOG.md."
fi

# --- Step 3: Run Swift Test Suite ---
log_step "3. Running Test Suite"
if [ "$SKIP_TESTS" -eq 1 ]; then
    log_warn "Skipping tests (--skip-tests specified)."
else
    log_info "Executing 'swift test --parallel'..."
    if [ "$DRY_RUN" -eq 0 ]; then
        swift test --parallel
        log_success "All unit and integration tests passed."
    else
        log_info "[DRY-RUN] Would execute: swift test --parallel"
    fi
fi

# --- Step 4: Version Injection into Info.plist ---
log_step "4. Version & Build Number Synchronization"

PLIST_FILE="${ROOT_DIR}/Resources/Info.plist"
BUILD_NUMBER=$(git rev-list --count HEAD 2>/dev/null || echo "1")
BUILD_NUMBER=$((BUILD_NUMBER + 1))

log_info "Target CFBundleShortVersionString: ${VERSION}"
log_info "Target CFBundleVersion (Build Number): ${BUILD_NUMBER}"

if [ "$DRY_RUN" -eq 0 ]; then
    if [ -f "$PLIST_FILE" ]; then
        plutil -replace CFBundleShortVersionString -string "${VERSION}" "${PLIST_FILE}"
        plutil -replace CFBundleVersion -string "${BUILD_NUMBER}" "${PLIST_FILE}"
        log_success "Updated ${PLIST_FILE} (v${VERSION}, build ${BUILD_NUMBER})."
    else
        log_warn "${PLIST_FILE} not found; skipping Info.plist update."
    fi
else
    log_info "[DRY-RUN] Would update ${PLIST_FILE} to version ${VERSION} (build ${BUILD_NUMBER})"
fi

# --- Step 5: Git Commit & Tag Creation ---
log_step "5. Git Commit & Annotated Tag"

if [ "$DRY_RUN" -eq 0 ]; then
    # Stage Info.plist if modified
    if ! git diff --quiet "${PLIST_FILE}" 2>/dev/null; then
        git add "${PLIST_FILE}"
        git commit -m "chore(release): bump version to ${TAG} [skip ci]"
        log_success "Committed version bump."
    fi

    # Create annotated tag
    git tag -a "${TAG}" -m "TextRotator ${TAG} Release"
    log_success "Created annotated tag: ${BOLD}${TAG}${RESET}"
else
    log_info "[DRY-RUN] Would commit version bump: 'chore(release): bump version to ${TAG}'"
    log_info "[DRY-RUN] Would create annotated tag: ${TAG}"
fi

# --- Step 6: Extract Release Notes ---
log_step "6. Preparing Release Notes"

NOTES_FILE="${ROOT_DIR}/build/release_notes_${VERSION}.md"
mkdir -p "${ROOT_DIR}/build"

if [ -f "${ROOT_DIR}/scripts/extract_changelog.sh" ]; then
    chmod +x "${ROOT_DIR}/scripts/extract_changelog.sh"
    "${ROOT_DIR}/scripts/extract_changelog.sh" "${VERSION}" "${NOTES_FILE}"
else
    awk -v ver="${VERSION}" '
        BEGIN { in_section = 0; found = 0 }
        $0 ~ "^## \\[(v?)" ver "\\]" { in_section = 1; found = 1; next }
        in_section && ($0 ~ "^## " || $0 ~ "^\\[[a-zA-Z0-9._-]+\\]:") { in_section = 0 }
        in_section { print }
    ' "${ROOT_DIR}/CHANGELOG.md" > "${NOTES_FILE}"
fi
log_success "Release notes extracted to ${NOTES_FILE}."

# --- Step 7: Execution Path (Local Build vs Cloud CI) ---
if [ "$LOCAL_BUILD" -eq 1 ]; then
    log_step "7. Local Build & Packaging"

    if [ "$DRY_RUN" -eq 0 ]; then
        if [ -f "${ROOT_DIR}/scripts/package.sh" ]; then
            chmod +x "${ROOT_DIR}/scripts/package.sh"
            "${ROOT_DIR}/scripts/package.sh" "${VERSION}" "${BUILD_NUMBER}"
        else
            chmod +x "${ROOT_DIR}/scripts/build_app.sh"
            "${ROOT_DIR}/scripts/build_app.sh" "${VERSION}" "${BUILD_NUMBER}"
            if [ -f "${ROOT_DIR}/scripts/package_dmg.sh" ]; then
                chmod +x "${ROOT_DIR}/scripts/package_dmg.sh"
                "${ROOT_DIR}/scripts/package_dmg.sh" "${VERSION}"
            fi
            if [ -f "${ROOT_DIR}/scripts/package_zip.sh" ]; then
                chmod +x "${ROOT_DIR}/scripts/package_zip.sh"
                "${ROOT_DIR}/scripts/package_zip.sh" "${VERSION}"
            fi
        fi

        # Generate checksums
        cd "${ROOT_DIR}/build"
        shasum -a 256 *.dmg *.zip > checksums.txt
        cat checksums.txt
        cd "${ROOT_DIR}"

        # Append checksums to release notes
        echo "" >> "${NOTES_FILE}"
        echo "### Checksums (SHA-256)" >> "${NOTES_FILE}"
        echo '```' >> "${NOTES_FILE}"
        cat "${ROOT_DIR}/build/checksums.txt" >> "${NOTES_FILE}"
        echo '```' >> "${NOTES_FILE}"

        log_step "8. Publishing GitHub Release (gh CLI)"
        GH_CMD=("gh" "release" "create" "${TAG}")
        [ -f "build/TextRotator-${VERSION}.dmg" ] && GH_CMD+=("build/TextRotator-${VERSION}.dmg")
        [ -f "build/TextRotator-${VERSION}.zip" ] && GH_CMD+=("build/TextRotator-${VERSION}.zip")
        [ -f "build/TextRotator.app.zip" ] && GH_CMD+=("build/TextRotator.app.zip")
        [ -f "build/checksums.txt" ] && GH_CMD+=("build/checksums.txt")
        GH_CMD+=("--title" "TextRotator ${TAG}" "--notes-file" "${NOTES_FILE}")
        [ "$DRAFT" -eq 1 ] && GH_CMD+=("--draft")
        [ "$PRERELEASE" -eq 1 ] && GH_CMD+=("--prerelease")

        "${GH_CMD[@]}"
        log_success "GitHub Release ${TAG} published successfully!"
    else
        log_info "[DRY-RUN] Would compile and package DMG/Zip"
        log_info "[DRY-RUN] Would create GitHub Release via: gh release create ${TAG}"
    fi

    # Push to origin
    if [ "$NO_PUSH" -eq 0 ] && [ -n "$REMOTE_URL" ]; then
        log_step "9. Pushing Commits and Tags to Remote"
        if [ "$DRY_RUN" -eq 0 ]; then
            git push origin "${CURRENT_BRANCH}"
            git push origin "${TAG}"
            log_success "Pushed branch and tag to origin."
        else
            log_info "[DRY-RUN] Would execute: git push origin ${CURRENT_BRANCH} && git push origin ${TAG}"
        fi
    fi

else
    # CI Mode
    log_step "7. Pushing to GitHub (Triggering Cloud CI/CD)"

    if [ "$NO_PUSH" -eq 0 ]; then
        if [ -n "$REMOTE_URL" ]; then
            if [ "$DRY_RUN" -eq 0 ]; then
                log_info "Pushing commit on ${CURRENT_BRANCH}..."
                git push origin "${CURRENT_BRANCH}"
                log_info "Pushing tag ${TAG}..."
                git push origin "${TAG}"
                log_success "Tag ${TAG} pushed to origin!"
            else
                log_info "[DRY-RUN] Would execute: git push origin ${CURRENT_BRANCH} && git push origin ${TAG}"
            fi
        else
            log_warn "Remote 'origin' is not set. Tag created locally. To push later:"
            log_warn "  git remote add origin https://github.com/rulled/textrotator_mac.git"
            log_warn "  git push -u origin ${CURRENT_BRANCH}"
            log_warn "  git push origin ${TAG}"
        fi
    else
        log_warn "--no-push specified. Tag created locally. Push manually with:"
        log_warn "  git push origin ${TAG}"
    fi
fi

echo ""
echo "========================================================================"
echo "${GREEN}${BOLD}🎉 RELEASE PROCESS COMPLETE FOR ${TAG}!${RESET}"
echo "========================================================================"
if [ "$LOCAL_BUILD" -eq 1 ]; then
    echo "Release published directly to GitHub via gh CLI."
else
    echo "Cloud CI/CD (.github/workflows/release.yml) will build and release automatically."
    echo "Track GitHub Actions: https://github.com/rulled/textrotator_mac/actions"
fi
echo "GitHub Releases:      https://github.com/rulled/textrotator_mac/releases/tag/${TAG}"
echo "========================================================================"
