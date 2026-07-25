/**
 * semantic-release configuration.
 *
 * Branching model (see CONTRIBUTING.md): `main` is the only permanent branch and
 * the source of stable releases. `beta` is an on-demand, *ephemeral* prerelease
 * branch, spun up only to canary a risky bump and deleted after promotion.
 *
 * Commit-back (@semantic-release/git) runs on `main` ONLY. It writes the release
 * artifacts back into the repo — CHANGELOG.md, the README version matrix and the
 * .mise.toml VERSION — as a single `[skip ci]` commit. The ephemeral `beta` canary
 * deliberately commits NOTHING, so it never accumulates release commits and merges
 * back into main cleanly. Because beta is the only other branch and it is
 * commit-free, `main` can never diverge from it.
 *
 * The branch is detected from GITHUB_REF_NAME (set by GitHub Actions on push
 * events). Off CI, or on any branch other than `main`, the commit-back plugins are
 * omitted — a dry-run/local run stays side-effect-free.
 */
const onMain = (process.env.GITHUB_REF_NAME || '') === 'main';

const plugins = [
  [
    '@semantic-release/commit-analyzer',
    {
      // Release triggering is scope-gated: only `public-pool` (upstream source
      // bumps) and `dependencies` (Dockerfile deps, e.g. the Node base image) can
      // cut a release. Everything else — hand-written feats, unscoped commits — is
      // blocked. Blocks come first; the scoped allows come last so they win.
      releaseRules: [
        { breaking: true, release: false },
        { revert: true, release: false },
        { type: 'feat', release: false },
        { type: 'fix', release: false },
        { type: 'perf', release: false },
        { type: 'feat', scope: 'public-pool', release: 'minor' },
        { type: 'fix', scope: 'dependencies', release: 'patch' },
        { type: 'feat', scope: 'dependencies', release: 'patch' },
        { breaking: true, scope: 'public-pool', release: 'major' },
        { breaking: true, scope: 'dependencies', release: 'major' },
      ],
    },
  ],
  '@semantic-release/release-notes-generator',
  ['@semantic-release/github', { addReleases: 'bottom' }],
];

if (onMain) {
  // NOTE: keep these strings single-quoted — `${nextRelease.version}` etc. are
  // semantic-release template placeholders, not JS template literals.
  plugins.push(
    ['@semantic-release/changelog', { changelogFile: 'CHANGELOG.md' }],
    ['@semantic-release/exec', { prepareCmd: './scripts/update-versions.sh ${nextRelease.version}' }],
    [
      '@semantic-release/git',
      {
        assets: ['CHANGELOG.md', 'package.json', 'README.md', '.mise.toml'],
        message: 'chore(release): ${nextRelease.version} [skip ci]\n\n${nextRelease.notes}',
      },
    ],
  );
}

module.exports = {
  branches: ['main', { name: 'beta', prerelease: true }],
  plugins,
};
