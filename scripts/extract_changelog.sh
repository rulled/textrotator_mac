#!/usr/bin/env bash
# ==============================================================================
# scripts/extract_changelog.sh
#
# Extracts the exact markdown changelog section for a specific version from
# CHANGELOG.md for use in GitHub Releases, automated release notes, and
# in-app update modals.
#
# Usage:
#   ./scripts/extract_changelog.sh <version> [output_file]
#   ./scripts/extract_changelog.sh 1.0.1
#   ./scripts/extract_changelog.sh v1.0.1 build/release_notes.md
#   ./scripts/extract_changelog.sh 1.0.1 --strip-header
#   ./scripts/extract_changelog.sh 1.0.1 --json
#
# Exit codes:
#   0 - Successfully extracted changelog
#   1 - Version not found or extraction failed
# ==============================================================================

set -euo pipefail

usage() {
    cat <<EOF
Usage: $(basename "$0") <version> [output_file] [options]

Extracts release notes for a specified version from CHANGELOG.md.

Arguments:
  <version>               Version to extract (e.g. "1.0.1" or "v1.0.1")
  [output_file]           Optional file path to write notes to (defaults to stdout)

Options:
  -s, --strip-header      Omit the '## [version] - YYYY-MM-DD' header line
  -j, --json              Output as JSON payload { "version", "date", "notes" }
  -f, --file <path>       Custom path to CHANGELOG.md (default: repo root CHANGELOG.md)
  -h, --help              Show this help message

Examples:
  $(basename "$0") 1.0.1
  $(basename "$0") 1.0.1 release_notes.md
  $(basename "$0") 1.0.1 --strip-header > release_notes.md
  $(basename "$0") 1.0.1 --json
EOF
}

# --- Parse arguments ---
RAW_VERSION=""
OUTPUT_FILE=""
STRIP_HEADER=0
OUTPUT_JSON=0
CHANGELOG_PATH=""

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -s|--strip-header)
            STRIP_HEADER=1
            ;;
        -j|--json)
            OUTPUT_JSON=1
            ;;
        -f|--file)
            shift
            if [ $# -eq 0 ]; then
                echo "Error: Missing value for --file option." >&2
                exit 1
            fi
            CHANGELOG_PATH="$1"
            ;;
        -*)
            echo "Error: Unknown option: $1" >&2
            usage
            exit 1
            ;;
        *)
            if [ -z "$RAW_VERSION" ]; then
                RAW_VERSION="$1"
            elif [ -z "$OUTPUT_FILE" ]; then
                OUTPUT_FILE="$1"
            else
                echo "Error: Unexpected extra argument: $1" >&2
                usage
                exit 1
            fi
            ;;
    esac
    shift
done

if [ -z "$RAW_VERSION" ]; then
    echo "Error: Version argument is required." >&2
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

if [ ! -f "$CHANGELOG_FILE" ]; then
    echo "Error: CHANGELOG.md not found at ${CHANGELOG_FILE}" >&2
    exit 1
fi

# Normalize version (strip leading v or V and carriage returns)
RAW_VERSION=$(echo "$RAW_VERSION" | tr -d '\r')
VERSION="${RAW_VERSION#v}"
VERSION="${VERSION#V}"

# Escape special regex characters in version
ESCAPED_VER=$(printf '%s\n' "$VERSION" | sed 's/[.[\*^$()+?{|]/\\&/g')

# Extract full section using awk (POSIX compliant, compatible with BSD and GNU awk)
EXTRACTED=$(awk -v ver="$ESCAPED_VER" -v strip_h="$STRIP_HEADER" '
BEGIN {
    in_section = 0;
    found = 0;
    n = 0;
}
$0 ~ "^## \\[(v?)" ver "\\]" {
    in_section = 1;
    found = 1;
    if (strip_h == 0) {
        lines[++n] = $0;
    }
    next;
}
in_section && ($0 ~ "^## " || $0 ~ "^\\[[a-zA-Z0-9._-]+\\]:") {
    in_section = 0;
}
in_section {
    lines[++n] = $0;
}
END {
    if (!found) {
        exit 2;
    }
    # Trim leading empty lines
    start = 1;
    while (start <= n && lines[start] ~ /^[[:space:]]*$/) {
        start++;
    }
    # Trim trailing empty lines
    end = n;
    while (end >= start && lines[end] ~ /^[[:space:]]*$/) {
        end--;
    }
    for (i = start; i <= end; i++) {
        print lines[i];
    }
}
' "$CHANGELOG_FILE") || {
    STATUS=$?
    if [ "$STATUS" -eq 2 ]; then
        echo "Error: Version '${VERSION}' not found in ${CHANGELOG_FILE}" >&2
        exit 1
    else
        echo "Error: Failed to extract changelog for '${VERSION}'" >&2
        exit 1
    fi
}

if [ -z "$EXTRACTED" ]; then
    echo "Error: Extracted notes for version '${VERSION}' are empty." >&2
    exit 1
fi

# Extract release date from CHANGELOG if present
DATE_MATCH=$(grep -E "^## \[(v?)${ESCAPED_VER}\] - [0-9]{4}-[0-9]{2}-[0-9]{2}" "$CHANGELOG_FILE" || true)
if [ -n "$DATE_MATCH" ]; then
    RELEASE_DATE=$(echo "$DATE_MATCH" | sed -E 's/.*- ([0-9]{4}-[0-9]{2}-[0-9]{2})$/\1/')
else
    RELEASE_DATE=""
fi

# Handle JSON output
if [ "$OUTPUT_JSON" -eq 1 ]; then
    # Escape quotes and backslashes for valid JSON string
    JSON_BODY=$(echo "$EXTRACTED" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | awk '{printf "%s\\n", $0}' | sed 's/\\n$//')
    RESULT=$(cat <<EOF
{
  "version": "${VERSION}",
  "date": "${RELEASE_DATE}",
  "title": "TextRotator v${VERSION}",
  "notes": "${JSON_BODY}"
}
EOF
)
else
    RESULT="$EXTRACTED"
fi

# Output to file or stdout
if [ -n "$OUTPUT_FILE" ]; then
    OUT_DIR="$(dirname "$OUTPUT_FILE")"
    if [ -n "$OUT_DIR" ] && [ ! -d "$OUT_DIR" ]; then
        mkdir -p "$OUT_DIR"
    fi
    printf "%s\n" "$RESULT" > "$OUTPUT_FILE"
    echo "Successfully extracted changelog for ${VERSION} to ${OUTPUT_FILE}" >&2
else
    printf "%s\n" "$RESULT"
fi

exit 0
