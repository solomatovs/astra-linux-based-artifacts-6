#!/usr/bin/env bash
# Commit all pending artifact changes and push them to the current branch in
# size-bounded batches, so no single push exceeds GitHub's ~2 GB push limit.
#
#   ./scripts/push-artifacts.sh
#   BATCH_MB=1000 ./scripts/push-artifacts.sh
#
# Re-runnable: only not-yet-pushed changes are processed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
BRANCH="${BRANCH:-$(git symbolic-ref --short HEAD)}"
LIMIT=$(( ${BATCH_MB:-1200} * 1024 * 1024 ))

# collect pending paths (untracked + modified + deleted). Paths here contain no
# spaces; -z keeps them safe regardless.
mapfile -d '' PENDING < <(git status --porcelain=v1 -z -uall | \
  while IFS= read -r -d '' entry; do printf '%s\0' "${entry:3}"; done)

# on a freshly cloned empty repo there is nothing to push until the first commit.
# must return 0 in that case, or `set -e` aborts the caller.
push_existing() {
  git rev-parse --verify -q HEAD >/dev/null || return 0
  git push origin "$BRANCH"
}

if [ "${#PENDING[@]}" -eq 0 ]; then
  echo "nothing to commit."
  # still make sure remote has our commits
  push_existing
  exit 0
fi

# flush any commit left unpushed by an interrupted earlier run (at most one batch,
# since we push after every commit) so batches never accumulate past the limit.
push_existing

batch=0; acc=0; staged=0
flush() {
  [ "$staged" -gt 0 ] || return 0
  batch=$((batch+1))
  git commit -q -m "artifacts: batch $batch"
  echo ">> pushing batch $batch ($(numfmt --to=iec "$acc"))..."
  git push origin "$BRANCH"
  acc=0; staged=0
}

for p in "${PENDING[@]}"; do
  [ -n "$p" ] || continue
  # tolerate already-staged deletions (file gone from disk, deletion already in index)
  git add -A -- "$p" 2>/dev/null || true
  if [ -f "$p" ]; then sz=$(stat -c %s "$p"); else sz=0; fi
  # if a single file plus current batch would exceed the limit, flush first
  if [ "$staged" -gt 0 ] && [ $((acc + sz)) -gt "$LIMIT" ]; then
    flush
  fi
  acc=$((acc + sz)); staged=$((staged + 1))
done
flush

echo "done: $batch batch(es) pushed."
