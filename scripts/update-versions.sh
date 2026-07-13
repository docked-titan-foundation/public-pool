#!/bin/bash
set -euo pipefail

# Called by semantic-release (prepareCmd) to keep the README version matrix and
# the Makefile's local VERSION in step with the release being cut.

DOCKERFILE="Dockerfile"
README="README.md"
MAKEFILE="Makefile"

if [ -z "${1:-}" ]; then
    RELEASE_VERSION=$(git tag --sort=-v:refname | head -1 | sed 's/^v//')
    if [ -z "$RELEASE_VERSION" ]; then
        echo "Error: Could not determine latest version from git tags"
        exit 1
    fi
else
    RELEASE_VERSION="$1"
fi

for f in "$DOCKERFILE" "$README" "$MAKEFILE"; do
    [ -f "$f" ] || { echo "Error: $f not found"; exit 1; }
done

# The three inputs that define what is actually inside the image.
PUBLIC_POOL_COMMIT=$(grep -m1 'ARG PUBLIC_POOL_COMMIT=' "$DOCKERFILE" | sed 's/.*=\([^ ]*\).*/\1/')
NODE_BASE=$(grep -m1 'ARG NODE_BASE=' "$DOCKERFILE" | sed 's/^ARG NODE_BASE=//')
NODE_VERSION=$(echo "$NODE_BASE" | sed 's/^node:\([^@]*\).*/\1/')

for var in PUBLIC_POOL_COMMIT NODE_VERSION; do
    [ -n "${!var}" ] || { echo "Error: could not extract $var from $DOCKERFILE"; exit 1; }
done

SHORT_COMMIT="${PUBLIC_POOL_COMMIT:0:12}"
RELEASE_DATE=$(date +%Y-%m-%d)

if [[ "$RELEASE_VERSION" == *"beta"* ]]; then
    SECTION="### Beta Releases"
    sed -i 's/ (latest beta)//' "$README" || true
    NEW_ROW="| $RELEASE_VERSION (latest beta) | \`$SHORT_COMMIT\` | $NODE_VERSION | $RELEASE_DATE |"
else
    SECTION="### Stable Releases"
    sed -i 's/ (latest)//' "$README" || true
    sed -i 's/ (latest beta)//' "$README" || true
    NEW_ROW="| $RELEASE_VERSION (latest) | \`$SHORT_COMMIT\` | $NODE_VERSION | $RELEASE_DATE |"
fi

# Insert the new row directly under the target section's table header rule.
if awk -v section="$SECTION" -v row="$NEW_ROW" '
    $0 == section { found=1 }
    found && /^\|[- |]+\|$/ {
        print; print row; found=0; next
    }
    { print }
' "$README" > "$README.tmp"; then
    mv "$README.tmp" "$README"
    echo "Updated version matrix in README.md with version $RELEASE_VERSION"
else
    rm -f "$README.tmp"
    echo "Error: failed to update $README"
    exit 1
fi

echo "Updating Makefile VERSION to v${RELEASE_VERSION}.local"
sed -i -E "s/^(VERSION[[:space:]]*:=[[:space:]]*).*/\1v${RELEASE_VERSION}.local/" "$MAKEFILE"

exit 0
