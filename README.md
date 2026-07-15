[![CI_CD](https://github.com/docked-titan-foundation/public-pool/actions/workflows/pipeline.yml/badge.svg)](https://github.com/docked-titan-foundation/public-pool/actions/workflows/pipeline.yml)
![Release](https://img.shields.io/github/v/release/docked-titan-foundation/public-pool)
[![Renovate](https://img.shields.io/badge/renovate-enabled-brightgreen.svg)](https://renovatebot.com)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
![Stars](https://img.shields.io/github/stars/docked-titan-foundation/public-pool?style=social)

## 📝 Description

A hardened, signed, SBOM-attested container image for
[Public Pool](https://github.com/benjamin-wilson/public-pool) — the solo Bitcoin
mining stratum server used by Bitaxe, NerdQAxe and similar miners.

Upstream publishes **no releases and no official image**, and its own Dockerfile
runs the process as `root` and ships the full build tree (source and
devDependencies) into the final image. This repository exists to fix that.

> **Why this matters.** In solo mining, the pool builds the block template's
> coinbase output — the transaction that pays out a found block. Whatever image
> you run decides where that money goes. Running an unpinned, unsigned image
> from an anonymous registry means trusting a stranger with the payout. This
> image is built from a pinned upstream commit, in public CI, signed with
> Cosign, and shipped with an SBOM and SLSA provenance so you can verify exactly
> what you are running.

## ✨ What this image does differently

| | Upstream | This image |
|---|---|---|
| Runs as | `root` | non-root (`node`, uid 1000) |
| Contents | full build tree + devDependencies | `dist/` + production deps only |
| Base image | floating tag | pinned by SHA256 digest |
| Source | whatever `master` is at build time | pinned upstream commit |
| Signature | none | Cosign keyless (Sigstore) |
| SBOM | none | SPDX, attested to the image |
| Provenance | none | SLSA build provenance |
| CVE scanning | none | Trivy on every build + weekly rebuild |
| Init | bare node process | `tini` (signal forwarding, zombie reaping) |

## 📋 Version Matrix

The image version tracks *this* repository's releases. `Upstream commit` is the
public-pool revision baked into it.

### Stable Releases

| Version | Upstream commit | Node | Date |
|---------|-----------------|------|------|

### Beta Releases

| Version | Upstream commit | Node | Date |
|---------|-----------------|------|------|
| 1.0.0-beta.1 (latest beta) | `96a9202c11de` | 24.16.0-bookworm-slim | 2026-07-15 |

## 🚀 Usage

```bash
docker run -d --name public-pool \
  -p 3333:3333 \
  -p 3334:3334 \
  -e API_PORT=3334 \
  -e STRATUM_PORT=3333 \
  -e NETWORK=mainnet \
  -e BITCOIN_RPC_URL=http://your-bitcoin-node \
  -e BITCOIN_RPC_PORT=8332 \
  -e BITCOIN_RPC_USER=bitcoin \
  -e BITCOIN_RPC_PASSWORD=... \
  -e BITCOIN_RPC_TIMEOUT=10000 \
  -e BITCOIN_ZMQ_HOST=tcp://your-bitcoin-node:28332 \
  -v public-pool-db:/public-pool/DB \
  ghcr.io/docked-titan-foundation/public-pool:latest
```

Point your miner's stratum URL at `stratum+tcp://<host>:3333` and use your
**Bitcoin address as the stratum username** — that is the address a found block
pays out to.

`API_PORT` is mandatory: public-pool exits at startup if it is unset.

### Bitcoin node requirements

- **Not pruned.** The node must be able to serve full block templates.
- **Fully synced.** `getblocktemplate` refuses to serve while
  `initialblockdownload` is true, so the pool cannot hand out work until the
  chain has caught up.
- **ZMQ enabled** (recommended) so the pool learns about new blocks immediately
  instead of polling:
  ```
  zmqpubrawblock=tcp://0.0.0.0:28332
  zmqpubhashblock=tcp://0.0.0.0:28333
  ```

## 🔐 Verifying the image

Every published image is signed with Cosign keyless signing, so you can prove it
came from this repository's CI and not from someone else:

```bash
cosign verify \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity-regexp "https://github.com/docked-titan-foundation/public-pool" \
  ghcr.io/docked-titan-foundation/public-pool:latest
```

Verify the SBOM attestation:

```bash
cosign verify-attestation \
  --type spdxjson \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity-regexp "https://github.com/docked-titan-foundation/public-pool" \
  ghcr.io/docked-titan-foundation/public-pool:latest
```

Inspect which upstream commit is baked in:

```bash
docker inspect ghcr.io/docked-titan-foundation/public-pool:latest \
  --format '{{index .Config.Labels "org.opencontainers.image.upstream.revision"}}'
```

## 🛠️ Development

Tooling is pinned in `.mise.toml`; [mise](https://mise.jdx.dev) installs it and
runs the tasks.

```bash
mise install          # install the pinned toolchain
mise tasks            # list every task

mise run build        # build the image locally
mise run test         # build, then boot it and assert non-root + stratum + API
mise run lint         # hadolint + shellcheck
mise run precommit
```

Upstream bumps arrive as Renovate PRs that move `ARG PUBLIC_POOL_COMMIT` in the
`Dockerfile`. They are never auto-merged — read the upstream diff first.

## 📄 License

GPL-3.0, matching upstream public-pool.
