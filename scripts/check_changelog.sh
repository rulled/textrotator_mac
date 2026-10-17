#!/usr/bin/env bash
# ==============================================================================
# scripts/check_changelog.sh
#
# Validates that CHANGELOG.md contains a valid, non-empty release entry for
# the specified version following the Keep a Changelog standard.
#
# Usage:
#   ./scripts/check_changelog.sh <version>
#   ./scripts/check_changelog.sh 1.0.1
#   ./scripts/check_changelog.sh v1.0.1
#
# Exit codes:
#   0 - Changelog is valid for the specified version
#   1 - Validation failed (missing file, missing version, empty notes, etc.)
# ==============================================================================

set -euo pipefail

# --- Color formatting helpers ---
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    BOLD=''
    RESET=''
fi

log_info() {
    printf "${BLUE}ℹ️  %s${RESET}\n" "$1"
}

log_success() {
    printf "${GREEN}✅ %s${RESET}\n" "$1"
}

log_warn() {
    printf "${YELLOW}⚠️  %s${RESET}\n" "$1"
}

log_error() {
    printf "${RED}❌ %s${RESET}\n" "$1" >&2
    if [ "${GITHUB_ACTIONS:-false}" = "true" ]; then
        echo "::error file=CHANGELOG.md::${1}"
    fi
}

usage() {
    cat <<EOF
Usage: $(basename "$0") <version> [options]

Mandatory pre-release validator for CHANGELOG.md.

Arguments:
  <version>               Version to check (e.g. "1.0.1" or "v1.0.1")

Options:
  -f, --file <path>       Path to changelog file (default: CHANGELOG.md in repo root)
  -h, --help              Show this help message

Validation Rules:
  1. CHANGELOG.md must exist in the repository root.
  2. A section header matching '## [<version>] - YYYY-MM-DD' must be present.
  3. Release date must be a valid ISO-8601 date (YYYY-MM-DD).
  4. The release section must not be empty or contain only whitespace.
  5. The section must contain at least one bullet item (- or *).
  6. The section must not contain unfinalized placeholders (TODO, TBD, WIP).

EOF
}

# --- Parse arguments ---
CHANGELOG_PATH=""
RAW_VERSION=""

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -f|--file)
            shift
            if [ $# -eq 0 ]; then
                log_error "Missing value for --file option."
                exit 1
            fi
            CHANGELOG_PATH="$1"
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
                log_error "Unexpected extra argument: $1"
                usage
                exit 1
            fi
            ;;
    esac
    shift
done

if [ -z "$RAW_VERSION" ]; then
    log_error "Version argument is required."
    usage
    exit 1
fi

# Locate repository root and CHANGELOG.md
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [ -z "$CHANGELOG_PATH" ]; then
    CHANGELOG_FILE="${ROOT_DIR}/CHANGELOG.md"
else
    if [[ "$CHANGELOG_PATH" = /* ]]; then
        CHANGELOG_FILE="$CHANGELOG_PATH"
    else
        CHANGELOG_FILE="${ROOT_DIR}/${CHANGELOG_PATH}"
    fi
fi

# Strip leading 'v' or 'V' and carriage returns
RAW_VERSION=$(echo "$RAW_VERSION" | tr -d '\r')
VERSION="${RAW_VERSION#v}"
VERSION="${VERSION#V}"

# Validate semantic version format (e.g., 1.0.0, 1.2.3-beta.1)
SEMVER_REGEX='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'
if ! [[ "$VERSION" =~ $SEMVER_REGEX ]]; then
    log_error "Invalid semantic version format: '${RAW_VERSION}'. Expected format: X.Y.Z or X.Y.Z-prerelease (e.g. 1.0.1 or 1.0.1-beta.1)"
    exit 1
fi

echo "========================================================================"
echo " 📋 Validating CHANGELOG.md for release version: ${BOLD}${VERSION}${RESET}"
echo "========================================================================"

# --- Check 1: File existence ---
if [ ! -f "$CHANGELOG_FILE" ]; then
    log_error "Changelog file not found at: ${CHANGELOG_FILE}"
    exit 1
fi
log_success "Changelog file found: ${CHANGELOG_FILE}"

# --- Check 2: Version header existence ---
# Look for '## [<version>]' or '## [v<version>]'
ESCAPED_VER=$(printf '%s\n' "$VERSION" | sed 's/[.[\*^$()+?{|]/\\&/g')
HEADER_LINE=$(grep -E "^## \[(v?)${ESCAPED_VER}\]" "$CHANGELOG_FILE" | head -n 1 || true)
HEADER_LINE=$(echo "$HEADER_LINE" | tr -d '\r')

if [ -z "$HEADER_LINE" ]; then
    log_error "Version '${VERSION}' not found in ${CHANGELOG_FILE}."
    echo "" >&2
    echo "Expected heading format:" >&2
    echo "  ## [${VERSION}] - $(date +%Y-%m-%d)" >&2
    echo "" >&2
    echo "Please update CHANGELOG.md with release notes for ${VERSION} before releasing." >&2
    exit 1
fi
log_success "Found version header: ${HEADER_LINE}"

# --- Check 3: Release date validation ---
# Must match '## [<version>] - YYYY-MM-DD'
DATE_REGEX="^## \[(v?)${ESCAPED_VER}\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$"
if ! [[ "$HEADER_LINE" =~ $DATE_REGEX ]]; then
    log_error "Invalid version header format: '${HEADER_LINE}'"
    echo "Expected format: '## [${VERSION}] - YYYY-MM-DD' (e.g., '## [${VERSION}] - $(date +%Y-%m-%d)')" >&2
    exit 1
fi

RELEASE_DATE=$(echo "$HEADER_LINE" | sed -E 's/.*- ([0-9]{4}-[0-9]{2}-[0-9]{2})$/\1/')
log_success "Release date verified: ${RELEASE_DATE}"

# --- Check 4: Extract section content and verify not empty ---
# Awk extracts from '## [ver]' line to next '## ' or bottom link reference '[...]:'
SECTION_BODY=$(awk -v ver="$ESCAPED_VER" '
BEGIN { in_section = 0; found = 0 }
$0 ~ "^## \\[(v?)" ver "\\]" {
    in_section = 1; found = 1; next
}
in_section && ($0 ~ "^## " || $0 ~ "^\\[[a-zA-Z0-9._-]+\\]:") {
    in_section = 0
}
in_section { print }
' "$CHANGELOG_FILE")

# Trim leading and trailing whitespace
TRIMMED_BODY=$(echo "$SECTION_BODY" | awk '
BEGIN { start = 0; n = 0 }
{ lines[++n] = $0 }
END {
    start = 1;
    while (start <= n && lines[start] ~ /^[[:space:]]*$/) start++;
    end = n;
    while (end >= start && lines[end] ~ /^[[:space:]]*$/) end--;
    for (i = start; i <= end; i++) print lines[i];
}')

if [ -z "$TRIMMED_BODY" ]; then
    log_error "Release notes section for '${VERSION}' is empty!"
    echo "The changelog section must contain notes describing Added, Changed, Fixed, etc." >&2
    exit 1
fi

# Count bullet points
BULLET_COUNT=$(echo "$TRIMMED_BODY" | grep -c -E '^[[:space:]]*[-*][[:space:]]+' || true)
if [ "$BULLET_COUNT" -eq 0 ]; then
    log_error "No bullet points (- or *) found in release section for '${VERSION}'."
    echo "At least one bullet item detailing user-facing changes is required." >&2
    exit 1
fi
log_success "Release notes content verified: ${BULLET_COUNT} bullet points found"

# --- Check 5: Check for unfinalized placeholder text ---
PLACEHOLDER_REGEX='TODO|TBD|WIP|PLACEHOLDER|NO CHANGES|COMING SOON'
if echo "$TRIMMED_BODY" | grep -i -E "$PLACEHOLDER_REGEX" >/dev/null 2>&1; then
    FOUND_PLACEHOLDER=$(echo "$TRIMMED_BODY" | grep -i -E "$PLACEHOLDER_REGEX" | head -n 3)
    log_error "Changelog contains placeholder text in version '${VERSION}':"
    echo "$FOUND_PLACEHOLDER" >&2
    echo "Please finalize or remove placeholders before releasing." >&2
    exit 1
fi
log_success "No placeholders detected (TODO/TBD/WIP)"

# --- Check 6: Check categories ---
CATEGORIES=$(echo "$TRIMMED_BODY" | grep -E '^###[[:space:]]+' || true)
if [ -n "$CATEGORIES" ]; then
    log_info "Detected release categories:"
    echo "$CATEGORIES" | while read -r cat; do
        printf "     %s\n" "$cat"
    done
fi

# --- Check 7: Bottom link reference check ---
LINK_REF=$(grep -E "^\[(v?)${ESCAPED_VER}\]:" "$CHANGELOG_FILE" || true)
if [ -z "$LINK_REF" ]; then
    log_warn "Notice: Comparison link reference '[${VERSION}]: https://...' was not found at bottom of ${CHANGELOG_FILE}."
    log_warn "Recommended: add '[${VERSION}]: https://github.com/rulled/textrotator_mac/releases/tag/v${VERSION}' at the end of CHANGELOG.md"
else
    log_success "Found comparison link: ${LINK_REF}"
fi

# GitHub Actions step summary if available
if [ -n "${GITHUB_STEP_SUMMARY:-}" ] && [ -w "$GITHUB_STEP_SUMMARY" ]; then
    cat >> "$GITHUB_STEP_SUMMARY" <<EOF
### ✅ Changelog Validation: Passed
- **Version**: \`${VERSION}\`
- **Date**: \`${RELEASE_DATE}\`
- **Bullet items**: \`${BULLET_COUNT}\`
- **File**: \`${CHANGELOG_FILE}\`
EOF
fi

echo ""
echo "${GREEN}${BOLD}🎉 SUCCESS: CHANGELOG.md validation passed for version ${VERSION}!${RESET}"
echo "========================================================================"
exit 0
