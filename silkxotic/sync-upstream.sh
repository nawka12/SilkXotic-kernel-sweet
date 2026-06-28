#!/usr/bin/env bash
# Pull crDroid changes into SilkXotic.
# This repo's base is a RE-ROOTED snapshot of crDroid 16.0 @ 731658b (not crDroid's actual
# commit), so the first integration needs --allow-unrelated-histories; after that the
# histories are connected and normal merges apply. Pass --rebase to rebase instead of merge.
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BRANCH="${1:-16.0}"
UPSTREAM_URL="https://github.com/crdroidandroid/android_kernel_xiaomi_sm6150"

git remote get-url upstream >/dev/null 2>&1 || git remote add upstream "$UPSTREAM_URL"

echo ">>> fetching upstream/$BRANCH (this downloads crDroid history; large the first time)"
git fetch upstream "$BRANCH"

# Has the unrelated-history bridge already been done? (do the upstream commits share history?)
if git merge-base HEAD "upstream/$BRANCH" >/dev/null 2>&1; then
  echo ">>> histories connected — normal merge:"
  echo "      git merge upstream/$BRANCH        # or: git rebase upstream/$BRANCH"
else
  cat <<EOF
>>> FIRST sync (unrelated histories — base is a re-rooted snapshot). Run:

      git merge upstream/$BRANCH --allow-unrelated-histories

    Git will merge the trees; resolve any conflicts (our changes are confined to
    arch/arm64/configs/vendor/silkxotic-*.config, .gitignore, SILKXOTIC.md, silkxotic/).
    After this one-time merge, future syncs are just:  git merge upstream/$BRANCH
EOF
fi
