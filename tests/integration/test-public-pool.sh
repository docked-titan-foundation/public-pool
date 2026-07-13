#!/bin/bash
set -euo pipefail

# Integration test for the public-pool image.
#
# Runs on the host (not inside the image) because what we care about is the
# container's externally observable behaviour: does it boot, does it drop root,
# does it bind stratum, does the API answer. Bitcoin RPC is deliberately NOT
# provided — public-pool logs `getmininginfo ECONNREFUSED` and carries on, so
# these assertions hold without needing a full bitcoind in CI.

IMAGE="${IMAGE:?IMAGE must be set (e.g. IMAGE=public-pool:v0.0.0.local)}"
DEBUG="${DEBUG:-0}"

CONTAINER="public-pool-itest-$$"
STRATUM_PORT=3333
API_PORT=3334

failures=0

cleanup() {
    if [ "$DEBUG" = "1" ]; then
        echo "── container logs ──"
        docker logs "$CONTAINER" 2>&1 | tail -20 || true
    fi
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT

check() {
    local name="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "✅ PASS  $name"
    else
        echo "❌ FAIL  $name"
        failures=$((failures + 1))
    fi
}

echo "🧪 Testing ${IMAGE}"

docker run -d --name "$CONTAINER" \
    -e API_PORT="$API_PORT" \
    -e STRATUM_PORT="$STRATUM_PORT" \
    -e NETWORK=mainnet \
    -e BITCOIN_RPC_URL=http://127.0.0.1 \
    -e BITCOIN_RPC_PORT=8332 \
    -e BITCOIN_RPC_USER=itest \
    -e BITCOIN_RPC_PASSWORD=itest \
    -e BITCOIN_RPC_TIMEOUT=10000 \
    -e API_SECURE=false \
    -e POOL_IDENTIFIER=itest \
    "$IMAGE" >/dev/null

# Wait for the stratum listener, which is the last thing to come up.
for _ in $(seq 1 30); do
    if docker logs "$CONTAINER" 2>&1 | grep -q "Stratum server is listening"; then
        break
    fi
    sleep 1
done

# ── Assertions ────────────────────────────────────────────────────────────────

# The container must be alive; a crash-on-boot is the failure we most care about.
check "container is running" \
    bash -c '[ "$(docker inspect -f "{{.State.Running}}" '"$CONTAINER"')" = "true" ]'

# Upstream's Dockerfile runs as root. Ours must not — this is the single most
# important regression to catch if the Dockerfile is ever refactored.
check "runs as non-root (uid 1000)" \
    bash -c '[ "$(docker exec '"$CONTAINER"' id -u)" = "1000" ]'

check "does not run as root" \
    bash -c '[ "$(docker exec '"$CONTAINER"' id -u)" != "0" ]'

# Stratum is the whole point of the image: if this port never binds, miners
# cannot connect no matter how healthy everything else looks.
check "stratum listener bound on ${STRATUM_PORT}" \
    bash -c 'docker logs '"$CONTAINER"' 2>&1 | grep -q "Stratum server is listening on port '"$STRATUM_PORT"'"'

check "stratum port accepts TCP" \
    docker exec "$CONTAINER" node -e "
        const net = require('net');
        const s = net.connect(${STRATUM_PORT}, '127.0.0.1');
        s.on('connect', () => { s.end(); process.exit(0); });
        s.on('error', () => process.exit(1));
        setTimeout(() => process.exit(1), 5000);
    "

# NestJS sets a global 'api' prefix; /api/info is the pool's status endpoint and
# is what the Dockerfile HEALTHCHECK probes.
check "API /api/info returns 200 JSON" \
    docker exec "$CONTAINER" node -e "
        fetch('http://127.0.0.1:${API_PORT}/api/info')
            .then(r => r.ok ? r.json() : Promise.reject(new Error('HTTP ' + r.status)))
            .then(() => process.exit(0))
            .catch(() => process.exit(1));
    "

# The image must ship only production dependencies; a devDependency landing in
# the runtime layer means the prune step regressed.
check "no devDependencies in runtime image" \
    bash -c '! docker exec '"$CONTAINER"' test -d /public-pool/node_modules/@nestjs/cli'

# DB/ is the SQLite share store and must be writable by the unprivileged user.
check "DB directory is writable by node" \
    docker exec "$CONTAINER" test -w /public-pool/DB

echo
if [ "$failures" -gt 0 ]; then
    echo "❌ ${failures} check(s) failed"
    exit 1
fi
echo "✅ All checks passed"
