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

3. Build the Docker image locally:

   ```bash
   make build
   ```

4. Test the image:

   ```bash
   make precommit
   ```

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
7. Open a Pull Request targeting the **`beta`** branch

## Beta Testing

For pre-release beta testing, all pull requests must target the **beta** branch.
The beta branch receives pre-release versions before changes are merged into the
main branch for stable releases.

- To test beta releases, pull the latest changes from the beta branch
- Beta versions are published with pre-release tags (e.g., `1.5.0-beta.1`)
- All features and fixes intended for the next stable release should first be merged
  into the beta branch for testing
- Once validated, changes will be promoted from beta to main via the release process

## Semantic Release (SR) Process

This project uses [Semantic Release](https://semantic-release.gitbook.io/) for automated
versioning and package publishing. The release process follows conventional commit
standards with Angular-style formatting.

### Branch Strategy

- **`main` branch**: Stable releases only. Direct pushes to main are restricted;
  all changes flow through the beta branch first.
- **`beta` branch**: Pre-release testing ground. Features and fixes are merged here
  for beta testing before promotion to main.

### Versioning

Version bumps are tied to Dockerfile sub-tool version changes. A release only produces
a new version tag when at least one tool version in the Dockerfile has changed:

- **Patch release** (`1.0.X`): Sub-tool patch version changes
  (e.g., `HELM_VERSION` from `4.1.4` → `4.1.5`)
- **Minor release** (`1.X.0`): Sub-tool minor version changes
  (e.g., `KUBECTL_VERSION` from `1.33.9` → `1.34.0`)
- **Major release** (`X.0.0`): Sub-tool major version changes or breaking changes
  (e.g., `HELMFILE_VERSION` from `1.4.4` → `2.0.0`)

Beta releases use pre-release tags (e.g., `1.5.0-beta.0`, `1.5.0-beta.1`).

### Conventional Commits

All commits must follow the [Conventional Commits](https://www.conventionalcommits.org/)
specification with Angular-style formatting:

- Format: `<type>(<scope>): <description>`
- Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `chore`, `ci`, `build`, `revert`
- Scope indicates the affected pipeline/tool (e.g., `pipeline`, `docker`, `helm`, etc.)
- Breaking changes must be indicated with `!` after type/scope or `BREAKING CHANGE:` in footer
- Example: `feat(pipeline): add beta branch support`

### Commit Types and Release Rules

Commits are categorized into two groups for release triggering:

**Version-bumping commits** — These trigger a release based on the sub-tool version change:

- Use `feat` for new sub-tool capabilities or minor version bumps
  (e.g., `feat(docker): bump HELM_VERSION 4.1.4 → 4.1.5` results in
  patch release when only patch level changes)
- Use `fix` for sub-tool bug fixes or patch version bumps
  (e.g., `fix(docker): update KUBECTL_VERSION 1.33.9 → 1.33.10`)
- Use `perf` for sub-tool performance-related updates
- Use `feat!` or `BREAKING CHANGE:` footer for major version bumps
  or breaking changes

**Non-release commits** — These improve the project without triggering a release. Use for:

- `chore` — maintenance tasks, dependency updates (non-sub-tool), CI/CD config
- `refactor` — code restructuring without functional changes
- `docs` — documentation updates
- `style` — formatting, lint fixes
- `test` — test additions/updates
- `ci` — CI configuration updates
- `build` — build system changes

### Release Triggers

- A new release is triggered automatically on push to `main` or `beta` branches
- `semantic-release` analyzes commits since the last tag to determine the version bump
- The version matrix is auto-generated based on Dockerfile sub-tool versions
- Versions in other places (labels, configs, etc.) are updated automatically
- Changelog is auto-generated from commit messages
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
