#!/bin/bash
set -euo pipefail

# Integration test for the public-pool image.
#
# Runs on the host (not inside the image) because what we care about is the
# container's externally observable behaviour: does it boot, does it drop root,
# does it bind stratum, does the API answer.
#
# By default (WITH_REGTEST=1) it also boots a throwaway `bitcoind -regtest`
# sidecar and drives the full mining path end to end. Set WITH_REGTEST=0 for
# the lean, no-bitcoind smoke test: public-pool then logs `getmininginfo
# ECONNREFUSED` and carries on, and the RPC assertions are skipped.

IMAGE="${IMAGE:?IMAGE must be set (e.g. IMAGE=public-pool:v0.0.0.local)}"
DEBUG="${DEBUG:-0}"

# Bitcoin RPC target. Defaults point at a deliberately-dead RPC so the suite
# needs no bitcoind (public-pool logs `getmininginfo ECONNREFUSED` and carries
# on). Override these to aim the container at a real/public node, e.g.
#   BITCOIN_RPC_URL=https://btc.example BITCOIN_RPC_PORT=443 \
#   BITCOIN_RPC_USER=key BITCOIN_RPC_PASSWORD=secret ./tests/integration/test-public-pool.sh
BITCOIN_RPC_URL="${BITCOIN_RPC_URL:-http://127.0.0.1}"
BITCOIN_RPC_PORT="${BITCOIN_RPC_PORT:-8332}"
BITCOIN_RPC_USER="${BITCOIN_RPC_USER:-itest}"
BITCOIN_RPC_PASSWORD="${BITCOIN_RPC_PASSWORD:-itest}"

# WITH_REGTEST=1 (the default) boots a throwaway `bitcoind -regtest` sidecar and
# points public-pool at it. regtest is a private, empty chain — no network sync —
# so getmininginfo/getblocktemplate answer immediately, exercising the real RPC
# path end to end. Set WITH_REGTEST=0 to skip the sidecar (lean smoke test).
WITH_REGTEST="${WITH_REGTEST:-1}"
BITCOIND_IMAGE="${BITCOIND_IMAGE:-lncm/bitcoind:v27.0}"
POOL_NETWORK=mainnet
DOCKER_NETWORK=""
BITCOIND=""

CONTAINER="public-pool-itest-$$"
STRATUM_PORT=3333
API_PORT=3334

failures=0

cleanup() {
    if [ "$DEBUG" = "1" ]; then
        echo "── container logs ──"
        docker logs "$CONTAINER" 2>&1 | tail -20 || true
        [ -n "$BITCOIND" ] && { echo "── bitcoind logs ──"; docker logs "$BITCOIND" 2>&1 | tail -10 || true; }
    fi
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
    [ -n "$BITCOIND" ] && docker rm -f "$BITCOIND" >/dev/null 2>&1 || true
    [ -n "$DOCKER_NETWORK" ] && docker network rm "$DOCKER_NETWORK" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# ── Optional regtest sidecar ──────────────────────────────────────────────────
if [ "$WITH_REGTEST" = "1" ]; then
    echo "🧱 Booting regtest bitcoind (${BITCOIND_IMAGE})"
    DOCKER_NETWORK="pp-itest-net-$$"
    BITCOIND="bitcoind-itest-$$"
    docker network create "$DOCKER_NETWORK" >/dev/null

    docker run -d --name "$BITCOIND" --network "$DOCKER_NETWORK" \
        --entrypoint bitcoind "$BITCOIND_IMAGE" \
        -regtest -server -rpcbind=0.0.0.0 -rpcallowip=0.0.0.0/0 \
        -rpcuser=itest -rpcpassword=itest -fallbackfee=0.0002 -listen=0 >/dev/null

    btc_cli() { docker exec "$BITCOIND" bitcoin-cli -regtest -rpcuser=itest -rpcpassword=itest "$@"; }

    for _ in $(seq 1 30); do
        btc_cli getblockchaininfo >/dev/null 2>&1 && break
        sleep 1
    done

    # A wallet is needed only to hold the coinbase; mine a bit past maturity so
    # getmininginfo reports a non-zero height like a real node would.
    btc_cli createwallet itest >/dev/null 2>&1 || btc_cli loadwallet itest >/dev/null 2>&1 || true
    REGTEST_ADDR="$(btc_cli getnewaddress)"
    btc_cli generatetoaddress 101 "$REGTEST_ADDR" >/dev/null

    BITCOIN_RPC_URL="http://${BITCOIND}"
    BITCOIN_RPC_PORT=18443
    BITCOIN_RPC_USER=itest
    BITCOIN_RPC_PASSWORD=itest
    POOL_NETWORK=regtest
fi

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
    ${DOCKER_NETWORK:+--network "$DOCKER_NETWORK"} \
    -e API_PORT="$API_PORT" \
    -e STRATUM_PORT="$STRATUM_PORT" \
    -e NETWORK="$POOL_NETWORK" \
    -e BITCOIN_RPC_URL="$BITCOIN_RPC_URL" \
    -e BITCOIN_RPC_PORT="$BITCOIN_RPC_PORT" \
    -e BITCOIN_RPC_USER="$BITCOIN_RPC_USER" \
    -e BITCOIN_RPC_PASSWORD="$BITCOIN_RPC_PASSWORD" \
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

is_running() {
    [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER")" = "true" ]
}

container_uid() {
    docker exec "$CONTAINER" id -u
}

stratum_listening() {
    docker logs "$CONTAINER" 2>&1 |
        grep -q "Stratum server is listening on port ${STRATUM_PORT}"
}

# The container must be alive; a crash-on-boot is the failure we most care about.
check "container is running" is_running

# Upstream's Dockerfile runs as root. Ours must not — this is the single most
# important regression to catch if the Dockerfile is ever refactored.
runs_as_node() { [ "$(container_uid)" = "1000" ]; }
not_root()     { [ "$(container_uid)" != "0" ]; }

check "runs as non-root (uid 1000)" runs_as_node
check "does not run as root" not_root

# Stratum is the whole point of the image: if this port never binds, miners
# cannot connect no matter how healthy everything else looks.
check "stratum listener bound on ${STRATUM_PORT}" stratum_listening

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

# With a real (regtest) node behind it, exercise the full mining path. The pool
# only calls getblocktemplate once a miner subscribes, so we run a minimal
# stratum handshake and assert we get a mining.notify job back — which the pool
# can only build from a successful getblocktemplate.
if [ "$WITH_REGTEST" = "1" ]; then
    rpc_connected() { docker logs "$CONTAINER" 2>&1 | grep -q "Bitcoin RPC connected"; }
    no_rpc_refused() { ! docker logs "$CONTAINER" 2>&1 | grep -q "ECONNREFUSED"; }

    receives_mining_job() {
        docker exec -e ADDR="$REGTEST_ADDR" -e PORT="$STRATUM_PORT" "$CONTAINER" node -e '
            const net = require("net");
            const s = net.connect(+process.env.PORT, "127.0.0.1");
            let buf = "", done = false;
            const fail = () => process.exit(1);
            const timer = setTimeout(fail, 15000);
            s.on("connect", () => {
                s.write(JSON.stringify({id:1,method:"mining.subscribe",params:["itest"]}) + "\n");
                s.write(JSON.stringify({id:2,method:"mining.authorize",params:[process.env.ADDR,"x"]}) + "\n");
            });
            s.on("data", d => {
                buf += d;
                if (!done && buf.includes("mining.notify")) {
                    done = true;
                    clearTimeout(timer);
                    // Close gracefully: half-close with FIN (not destroy/RST) and
                    // keep reading so the pool never hits EPIPE mid-write, then
                    // exit once its writes have drained.
                    s.end();
                    setTimeout(() => process.exit(0), 500);
                }
            });
            // Ignore post-handshake read errors; success is already latched.
            s.on("error", () => { if (!done) fail(); });
        '
    }

    check "bitcoin RPC connected (getmininginfo)" rpc_connected
    check "miner receives job (getblocktemplate → mining.notify)" receives_mining_job
    check "no getmininginfo ECONNREFUSED against regtest node" no_rpc_refused
fi

echo
if [ "$failures" -gt 0 ]; then
    echo "❌ ${failures} check(s) failed"
    exit 1
fi
echo "✅ All checks passed"
