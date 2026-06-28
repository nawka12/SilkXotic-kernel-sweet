#!/usr/bin/env bash
# Pull crDroid changes into SilkXotic (single-snapshot base).
# Normal case: crDroid adds commits on top of our base 731658b, so the merge base
# is present and rebase/merge works. If crDroid force-pushes 16.0 such that 731658b
# is no longer an ancestor, run:  git fetch --unshallow upstream  first.
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BRANCH="${1:-16.0}"
UPSTREAM_URL="https://github.com/crdroidandroid/android_kernel_xiaomi_sm6150"

git remote get-url upstream >/dev/null 2>&1 || git remote add upstream "$UPSTREAM_URL"

echo ">>> fetching upstream/$BRANCH"
git fetch upstream "$BRANCH"

echo ">>> your commits ahead of base:"
git log --oneline upstream/"$BRANCH"..HEAD || true

cat <<EOF

>>> Choose how to integrate:
    Rebase SilkXotic on top (clean, linear):
        git rebase upstream/$BRANCH
    OR merge (preserves your merge history):
        git merge upstream/$BRANCH

    If you see "refusing to merge unrelated histories" or a missing merge base,
    crDroid likely rewrote the branch — run:
        git fetch --unshallow upstream && git rebase upstream/$BRANCH
EOF
