#!/bin/bash
set -e

# Build script for the public-pool image
# Usage: `mise run build`, which supplies DEBUG, IMAGE_NAME and VERSION from
# the [env] block in .mise.toml.

DEBUG="${DEBUG:-0}"
IMAGE_NAME="${IMAGE_NAME:-public-pool}"
VERSION="${VERSION:-v0.0.0.local}"

build_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
vcs_ref=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

image_tag="${IMAGE_NAME}:${VERSION}"

build_args=(
    --target runtime
    --build-arg "BUILD_DATE=${build_date}"
    --build-arg "VCS_REF=${vcs_ref}"
    --build-arg "APP_VERSION=${VERSION}"
    -t "${image_tag}"
    .
)

if [ "$DEBUG" = "1" ]; then
    echo "📦 Building ${image_tag}..."
    if docker build "${build_args[@]}"; then
        echo "✅ PASS"
    else
        echo "❌ FAIL"
        exit 1
    fi
else
    echo -n "📦 Building ${image_tag}... "
    if docker build "${build_args[@]}" > /dev/null 2>&1; then
        echo "✅ PASS"
    else
        echo "❌ FAIL"
        exit 1
    fi
fi
