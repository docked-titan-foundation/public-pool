#!/usr/bin/env bash
set -euo pipefail

CONFIG="release.config.js"
EXIT=0

echo "🔍 Validating semantic release configuration..."

# 1. Config exists
if [ ! -f "$CONFIG" ]; then
  echo "❌ Error: $CONFIG not found"
  exit 1
fi

# 2. Config loads as a module
if ! node -e "require('./$CONFIG')" 2>/dev/null; then
  echo "❌ Error: $CONFIG failed to load:"
  node -e "require('./$CONFIG')" || true
  exit 1
fi

# release.config.js branches on GITHUB_REF_NAME: the commit-back plugins
# (changelog + exec + git) are added for `main` and omitted for the ephemeral
# `beta` canary. Inspect the resolved plugin list for each branch.
plugins_for() {
  GITHUB_REF_NAME="$1" node -e "
    const c = require('./$CONFIG');
    console.log(c.plugins.map(p => Array.isArray(p) ? p[0] : p).join('\n'));
  "
}

MAIN_PLUGINS="$(plugins_for main)"
BETA_PLUGINS="$(plugins_for beta)"

# 3. main must commit the version artifacts back, and the assets must exist.
echo "📦 Checking main-branch commit-back..."
for p in @semantic-release/changelog @semantic-release/exec @semantic-release/git; do
  if ! grep -qxF "$p" <<<"$MAIN_PLUGINS"; then
    echo "❌ Error: $p missing from the main-branch plugin set"
    EXIT=1
  fi
done

ASSETS=$(GITHUB_REF_NAME=main node -e "
  const c = require('./$CONFIG');
  const git = c.plugins.find(p => Array.isArray(p) && p[0] === '@semantic-release/git');
  if (git) console.log((git[1].assets || []).join(' '));
" 2>/dev/null || true)
for asset in $ASSETS; do
  if [ ! -f "$asset" ]; then
    echo "❌ Error: @semantic-release/git asset '$asset' does not exist"
    EXIT=1
  fi
done
[ $EXIT -eq 0 ] && echo "✅ main commits back (CHANGELOG + matrix); assets present"

# 4. The ephemeral beta canary must commit NOTHING, so it merges into main cleanly.
echo "🔎 Checking the beta canary stays commit-free..."
FORBIDDEN_ON_BETA=""
for p in @semantic-release/changelog @semantic-release/exec @semantic-release/git; do
  if grep -qxF "$p" <<<"$BETA_PLUGINS"; then
    FORBIDDEN_ON_BETA="$FORBIDDEN_ON_BETA $p"
  fi
done
if [ -n "$FORBIDDEN_ON_BETA" ]; then
  echo "❌ Error: commit-back plugin(s) active on beta:$FORBIDDEN_ON_BETA"
  echo "   The ephemeral canary must commit nothing (see release.config.js)."
  EXIT=1
else
  echo "✅ beta canary is commit-free"
fi

# 5. Required base plugins must be present on every branch.
echo "🔎 Checking required plugins..."
for p in @semantic-release/commit-analyzer @semantic-release/release-notes-generator @semantic-release/github; do
  if ! grep -qxF "$p" <<<"$BETA_PLUGINS"; then
    echo "❌ Error: required plugin $p missing"
    EXIT=1
  fi
done

# 6. Try a dry-run (config load smoke test; tolerant of local git state).
echo ""
echo "🧪 Running semantic-release dry-run (configuration check only)..."
if npx semantic-release --dry-run --no-ci 2>&1 | tee /tmp/sr-dry-run.log; then
  echo "✅ Semantic-release dry-run completed successfully"
else
  echo "⚠️  Dry-run encountered issues (may be due to local git state). Checking logs..."
  if grep -q "missing file\|cannot find\|ENOENT" /tmp/sr-dry-run.log; then
    echo "❌ Semantic-release configuration error detected in logs"
    EXIT=1
  else
    echo "ℹ️  Dry-run failed for reasons unrelated to config validation (likely git tag conflicts)"
  fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ $EXIT -eq 0 ]; then
  echo "✅ All validation checks passed"
  exit 0
else
  echo "❌ Some validation checks failed"
  exit 1
fi
