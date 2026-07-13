#!/bin/bash
set -e

# Integration test driver. Boots the image and asserts it is actually usable,
# rather than merely built. Delegates to tests/integration/test-public-pool.sh,
# which is also what CI runs against the pushed image.

DEBUG="${DEBUG:-0}"
IMAGE_NAME="${IMAGE_NAME:-public-pool}"
VERSION="${VERSION:-v0.0.0.local}"

IMAGE="${IMAGE:-${IMAGE_NAME}:${VERSION}}"

export IMAGE DEBUG

exec "$(dirname "$(realpath "$0")")/../tests/integration/test-public-pool.sh"
