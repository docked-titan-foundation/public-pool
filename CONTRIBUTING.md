# Contributing to Public Pool

Contributions are welcome! Please read this guide to get started.

## Requirements

- Docker 20.10+
- [pre-commit](https://pre-commit.com) (install via `pip install pre-commit` or `brew install pre-commit`)
- [hadolint](https://github.com/hadolint/hadolint) (required for Dockerfile changes; used by mandatory pre-commit hook)

## Development Setup

1. Clone the repository:

   ```bash
   git clone https://github.com/docked-titan-foundation/public-pool.git
   cd public-pool
   ```

2. Install pre-commit hooks:

   ```bash
   pip install pre-commit   # or: brew install pre-commit
   pre-commit install
   ```

3. Install the pinned toolchain (see `.mise.toml`):

   ```bash
   mise install
   ```

4. Build the Docker image locally:

   ```bash
   mise run build
   ```

5. Test the image:

   ```bash
   mise run test
   mise run precommit
   ```

   `mise tasks` lists everything available.

## Ways to Contribute

- Report bugs
- Suggest new features
- Improve documentation
- Submit pull requests

## Pull Request Process

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Make your changes
4. Run pre-commit checks:

   ```bash
   pre-commit run --all-files
   ```

5. Commit your changes (`git commit -m 'Add my feature'`)
6. Push to your fork (`git push origin feature/my-feature`)
7. Open a Pull Request targeting the **`main`** branch

## Prerelease Canaries (on demand)

`main` is the trunk: merging a release-worthy change to `main` cuts a stable
release directly. There is **no permanent `beta` branch**. Every release candidate
is already built, integration-tested, scanned, and signed *before* it is tagged, so
routine dependency bumps do not need a separate prerelease channel.

When a change is risky enough to want a **runnable** prerelease image first — in
practice, an upstream `public-pool` bump, since that code builds the block
template's coinbase output — cut a throwaway prerelease branch:

1. `git switch -c beta main` and push it.
2. Land the risky change on `beta` (merge the Renovate PR into `beta` instead of
   `main`). CI publishes a `X.Y.Z-beta.N` tag and the `beta-latest` image.
3. Canary `beta-latest` for as long as you need.
4. When satisfied, merge `beta` → `main` (which cuts the stable release), then
   delete the branch: `git push origin --delete beta`.

Recreate `beta` the same way next time. Because it never lives longer than a
canary cycle, it cannot accumulate release commits or drift from `main`.

## Semantic Release (SR) Process

This project uses [Semantic Release](https://semantic-release.gitbook.io/) for automated
versioning and package publishing. The release process follows conventional commit
standards with Angular-style formatting.

### Branch Strategy

- **`main` branch**: the trunk and the only permanent branch. Stable releases are
  cut from here. Direct pushes are restricted; changes land via PR (the release
  bot bypasses the restriction to push tags).
- **`beta` branch**: **ephemeral**, created on demand only to canary a risky bump,
  and deleted after promotion. See *Prerelease Canaries* above. Renovate does not
  target it — it opens PRs against `main`.

### Versioning

Version bumps are tied to changes in the Docker image's inputs, enforced by the
`releaseRules` in `release.config.js` (only the `public-pool` and `dependencies` scopes
release):

- **Patch release** (`1.0.X`): a Dockerfile dependency bump, e.g. the Node base
  image (`fix(dependencies): bump NODE_BASE …`)
- **Minor release** (`1.X.0`): an upstream public-pool source bump
  (`feat(public-pool): …`)
- **Major release** (`X.0.0`): a `BREAKING CHANGE:` footer on either of those
  scopes (the `!` shorthand is not recognised — see *Conventional Commits*)

Prerelease canaries use pre-release tags (e.g., `1.5.0-beta.0`, `1.5.0-beta.1`)
while a `beta` branch exists.

### Conventional Commits

All commits must follow the [Conventional Commits](https://www.conventionalcommits.org/)
specification with Angular-style formatting:

- Format: `<type>(<scope>): <description>`
- Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `chore`, `ci`, `build`, `revert`
- Scope indicates the affected pipeline/tool (e.g., `pipeline`, `docker`, `helm`, etc.)
- Breaking changes must be indicated with a `BREAKING CHANGE:` footer. The Angular
  preset in use does **not** recognise the `!` shorthand — a `feat(x)!:` header is
  parsed as an ordinary commit and will **not** trigger a major release.
- Example: `fix(dependencies): bump NODE_BASE to 24.16.1`

### Commit Types and Release Rules

Commits are categorized into two groups for release triggering. **Release
triggering is scope-gated** (enforced by `releaseRules` in `release.config.js`): only the
`public-pool` and `dependencies` scopes can produce a release. A `feat`/`fix`/`perf`
on any other scope — or with no scope — is treated as a non-release commit, no
matter its type.

**Version-bumping commits** — Only these two forms trigger a release:

- `feat(public-pool): ...` — an upstream public-pool source bump → **minor**
- `fix(dependencies): ...` — a Dockerfile dependency bump, e.g. the Node base
  image (`ARG NODE_BASE`) → **patch**
- A `BREAKING CHANGE:` footer on either of those scopes → **major**
  (the `!` shorthand does not work — see Conventional Commits above)

**Non-release commits** — These improve the project without triggering a release. Use for:

- `chore` — maintenance tasks, dependency updates (non-sub-tool), CI/CD config
- `refactor` — code restructuring without functional changes
- `docs` — documentation updates
- `style` — formatting, lint fixes
- `test` — test additions/updates
- `ci` — CI configuration updates
- `build` — build system changes

### Release Triggers

- A new release is triggered automatically on push to `main` (or an on-demand
  `beta` canary branch)
- `semantic-release` analyzes commits since the last tag to determine the version bump
- **Commit-back is `main`-only.** On `main`, `@semantic-release/git` commits the
  release artifacts back — `CHANGELOG.md`, the README version matrix and the
  `.mise.toml` `VERSION` — as a single `[skip ci]` commit. This is configured in
  `release.config.js`, which adds the commit-back plugins (`changelog` + `exec` +
  `git`) only when the release runs on `main`.
- The ephemeral **`beta` canary commits nothing** (those plugins are omitted for
  it), so it never accumulates release commits and merges back into `main` cleanly.
  With no permanent second branch and a commit-free canary, `main` cannot diverge.
- Docker images are built, tested, scanned, signed, and pushed to GitHub Container Registry
- SBOM (Software Bill of Materials) is generated and signed for each release

### Automated Dependency Updates (Renovate)

This project uses [Renovate](https://docs.renovatebot.com/) for automated dependency
management. Renovate opens PRs against the **`beta`** branch when new versions are
available. The commit type is chosen per update level:

| Update type | Commit produced | Release triggered |
|-------------|-----------------|-------------------|
| Upstream **public-pool commit** (`ARG PUBLIC_POOL_COMMIT`) | `feat(public-pool): ...` | minor |
| **Node base image** digest (`ARG NODE_BASE`) | `fix(dependencies): ...` | patch |
| GitHub Actions / npm | `chore(dependencies): ...` | none |

No manual version bumping is required; merge the Renovate PR after CI passes —
**except for upstream public-pool bumps**. Those are never auto-merged and carry
a `review-required` label, because that code constructs the block template's
coinbase output: it decides where a found block's reward is paid. Read the
upstream diff before merging one.

## Checksum Verification Process

All binary downloads must have their SHA256 verified.
Obtain checksums from the official release page, never from third-party sources.

## Coding Standards

- All files must pass pre-commit hooks
- Dockerfile should pass hadolint validation
- Must pass integration test
- The image must build correctly
- Use Alpine Linux as the base image
- Specify explicit versions for binaries
- Keep the image size minimal

## Pipeline Flow

The Public Pool project uses a gated pipeline for quality and security:

```text
lint
 └─▶ release
       └─▶ build (local only)
             └─▶ test (versions, plugins, non-root)
                   └─▶ security scan (CRITICAL/HIGH = fail)
                         └─▶ SBOM generation
                               └─▶ push (first public appearance)
                                     └─▶ sign
                                           └─▶ attach + sign SBOM
```

| Gate | Description |
|------|-------------|
| **Lint** | Dockerfile, YAML, and Markdown linting |
| **Release** | Semantic versioning on main branch (GPG signed commits) |
| **Build** | Docker image built locally (no push) |
| **Test** | Version validation (Helm, Helmfile, kubectl, SOPS), plugin checks (diff, secrets), non-root user |
| **Security Scan** | Trivy vulnerability scanner (CRITICAL/HIGH = fail) |
| **SBOM Generation** | SPDX JSON Software Bill of Materials |
| **Push** | First public appearance to GitHub Container Registry |
| **Sign** | Cosign image signing |
| **Attach + Sign SBOM** | Attach and sign SBOM with Cosign |

## License

By contributing, you agree that your contributions will be licensed under the
GNU General Public License v3.0.
