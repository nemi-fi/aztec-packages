#!/usr/bin/env bash
# Start the update of community/v6 to a new upstream v6 release.
#
# usage: community/update-upstream.sh <tag>      # e.g. v6.1.0
#
# Creates branch community/update-<tag> from origin/community/v6 and merges the upstream tag into it, so the
# optimisation commits keep their history and every upstream release is one merge commit. On conflicts the script
# stops with the merge in progress: resolve them (keep upstream's version, re-apply only the part of the optimisation
# that is still missing), `git commit`, and run it again with the same tag to finish. It then records the new
# upstream version, and you push the branch and open a PR into community/v6. Merge that PR with a merge commit,
# not a squash, so the next upstream merge starts from this one.
set -euo pipefail

TAG=${1:?usage: community/update-upstream.sh <tag>}
UPSTREAM_URL=${UPSTREAM_URL:-https://github.com/AztecProtocol/aztec-packages.git}
ROOT=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
VERSION=${TAG#v}
BRANCH=community/update-$TAG
cd "$ROOT"

die() { echo "$*" >&2; exit 1; }

[[ "$VERSION" =~ ^6\.[0-9]+\.[0-9]+$ ]] || die "$TAG is not a v6 release tag"
npm view "@aztec-foundation/bb.js@$VERSION" version >/dev/null 2>&1 ||
  die "@aztec-foundation/bb.js@$VERSION is not on npm: the package is built over the stock tarball of the same version"

git fetch --no-tags "$UPSTREAM_URL" "refs/tags/$TAG:refs/tags/$TAG"
git fetch origin community/v6

current=$(git branch --show-current)
if [[ "$current" != "$BRANCH" ]]; then
  [[ -z "$(git status --porcelain --untracked-files=no)" ]] || die "the working tree has uncommitted changes"
  git checkout -b "$BRANCH" origin/community/v6
fi

# Upstream's workflows need AztecProtocol's infrastructure; this branch keeps only community-release.yml.
drop_upstream_workflows() {
  git ls-files --sparse .github/workflows | grep -vx .github/workflows/community-release.yml |
    xargs -r git rm -q -f --sparse --
}

# The root README describes this build, not upstream.
keep_readme() {
  git checkout -q HEAD -- README.md
}

if ! git merge-base --is-ancestor "$TAG" HEAD; then
  git merge --no-ff --no-commit "$TAG" || true
  git rev-parse -q --verify MERGE_HEAD >/dev/null || die "merging $TAG failed before any conflict resolution"
  drop_upstream_workflows
  keep_readme
  conflicts=$(git diff --name-only --diff-filter=U)
  if [[ -n "$conflicts" ]]; then
    echo "Conflicts merging $TAG. Resolve them, 'git commit', then run: community/update-upstream.sh $TAG" >&2
    echo "$conflicts" >&2
    exit 1
  fi
  git commit -q --no-edit -m "chore(community): merge upstream $TAG"
fi

echo "$VERSION" > community/UPSTREAM_VERSION
git add community/UPSTREAM_VERSION
git diff --cached --quiet || git commit -q -m "chore(community): build on upstream $VERSION"

cat <<EOF
$BRANCH now holds upstream $TAG merged into community/v6.
Next:
  1. Check the merge as community/README.md "Validating" describes (byte-identical proofs with the harness).
  2. Update the series tables in community/README.md if a patch is now upstream.
  3. git push -u origin $BRANCH, then open a PR into community/v6. Its CI builds and checks the package;
     merging it (with a merge commit) publishes @nemi-fi/bb.js@$VERSION-optimise.<n>.
EOF
