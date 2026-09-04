#!/usr/bin/env bash
# Sync crDroid changes into SilkXotic, preserving our customizations.
#
# Why NOT `git merge upstream/16.0`:
#   * Our base is a RE-ROOTED snapshot of crDroid (no shared history), and
#   * crDroid REBASES their 16.0 branch, so the upstream tip has no usable
#     merge-base with us. A plain merge would either drag in crDroid's entire
#     history (multi-GB) or conflict-storm on essentially every file.
#
# What this does instead:
#   1. Shallow-fetches ONLY the upstream tip (no history download).
#   2. Reads the upstream commit we're currently synced to from the ref
#        refs/silkxotic/upstream-base
#   3. 3-way merges  base .. new-tip  onto HEAD in a scratch index (git objects
#      only — the working tree, our WIP, untracked files and the pile of
#      git-ignored kernel build artifacts on disk are all left alone).
#
# Our customizations live on a disjoint set of paths: silkxotic/, the
# vendor/silkxotic-*.config + buildhost-lowram.config fragments, SILKXOTIC.md,
# .gitignore, plus these in-tree patched files (keep this list current — it is
# the set the collision check below actually protects):
#
#     drivers/block/zram/zram_drv.c
#     arch/arm64/boot/dts/qcom/sdmmagpie.dtsi      (v1.1 EAS energy model)
#     drivers/kernelsu/manager/throne_tracker.c    (v1.1.2 ABBA deadlock fix)
#     drivers/kernelsu/policy/allowlist.c          (v1.2.0 pre-v4 profile migration)
#     drivers/kernelsu/policy/allowlist.h          (v1.2.0 pre-v4 profile migration)
#     drivers/kernelsu/supercall/dispatch.c        (v1.2.0 pre-v4 profile migration)
#     drivers/cpufreq/cpu-boost.c                  (v1.2.0 compiled-in boost default)
#     drivers/cpufreq/Kconfig                      (v1.2.0 compiled-in boost default)
#
# so the merge is normally conflict-free. If upstream ever edits a file we also
# patched, the script STOPS and lists it rather than silently clobbering our change.
#
# Usage:  silkxotic/sync-upstream.sh [branch]        (branch defaults to 16.0)
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BRANCH="${1:-16.0}"
UPSTREAM_URL="https://github.com/crdroidandroid/android_kernel_xiaomi_sm6150"
BASE_REF="refs/silkxotic/upstream-base"

git remote get-url upstream >/dev/null 2>&1 || git remote add upstream "$UPSTREAM_URL"

echo ">>> shallow-fetching upstream/$BRANCH (tip only — no full history)"
git fetch --depth=1 upstream "$BRANCH"
NEW=$(git rev-parse FETCH_HEAD)

if ! git rev-parse --verify --quiet "$BASE_REF" >/dev/null; then
  cat <<EOF
!! $BASE_REF is not set — the script can't tell which upstream state our tree
   currently matches. Point it at the crDroid commit we're synced to, then
   re-run. (If you've never diverged, that's the SHA in the newest
   "Sync crDroid $BRANCH @ ..." / snapshot commit message.)

       git update-ref $BASE_REF <upstream-sha-we-are-synced-to>
EOF
  exit 1
fi
BASE=$(git rev-parse "$BASE_REF")

if [ "$BASE" = "$NEW" ]; then
  echo ">>> already in sync with upstream/$BRANCH ($NEW). Nothing to do."
  exit 0
fi

echo ">>> upstream delta ${BASE:0:7}..${NEW:0:7}:"
git diff --shortstat "$BASE" "$NEW"

# 3-way merge into a scratch index. --aggressive auto-resolves every path that
# only one side touched (upstream-only -> take upstream; ours-only -> keep ours).
SCRATCH="$(git rev-parse --git-dir)/silkxotic-sync-index"
rm -f "$SCRATCH"
GIT_INDEX_FILE="$SCRATCH" git read-tree -m -i --aggressive "$BASE" HEAD "$NEW"

# Anything left unmerged = upstream changed a file we also patched.
CONFLICTS=$(GIT_INDEX_FILE="$SCRATCH" git ls-files -u | awk '{print $4}' | sort -u || true)
if [ -n "$CONFLICTS" ]; then
  echo "!! COLLISION — upstream changed file(s) we also customize:"
  echo "$CONFLICTS" | sed 's/^/     /'
  echo "   Merge these by hand (our edit vs upstream's), commit, then"
  echo "   'git update-ref $BASE_REF $NEW'. Aborting auto-sync."
  rm -f "$SCRATCH"
  exit 1
fi

TREE=$(GIT_INDEX_FILE="$SCRATCH" git write-tree)
rm -f "$SCRATCH"

COMMIT=$(git commit-tree "$TREE" -p HEAD \
  -m "Sync crDroid $BRANCH @ ${NEW:0:7} (keep SilkXotic customizations)")
git update-ref HEAD "$COMMIT"
git update-ref "$BASE_REF" "$NEW"

# Bring the working tree in line for the changed paths only. Leaves WIP,
# untracked files, and our customizations (all on other paths) untouched.
git diff --name-only "$BASE" "$NEW" -z | xargs -0 --no-run-if-empty git checkout HEAD --

echo ">>> synced to ${NEW:0:7}; $BASE_REF updated. Review:  git show --stat HEAD"
echo ">>> push when ready:  git push origin $BRANCH"
