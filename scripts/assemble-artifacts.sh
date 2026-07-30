#!/usr/bin/env bash
# Reassemble split tarballs after `git clone` and verify integrity.
#
# Large tarballs (>100 MB) are stored in git as <file>.part-000, .part-001, …
# (GitHub blocks single files >100 MB). This script concatenates the pieces back
# into the original file and checks every tarball's sha256 against the manifest.
#
#   ./scripts/assemble-artifacts.sh
#
# Re-runnable: files already correct are skipped.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT/artifacts-manifest.tsv"
[ -f "$MANIFEST" ] || { echo "manifest not found: $MANIFEST" >&2; exit 1; }

ok=0; built=0; failed=0
while IFS=$'\t' read -r path size sha parts; do
  [ -n "$path" ] || continue
  dest="$ROOT/$path"
  if [ "${parts:-0}" -gt 0 ]; then
    if [ -f "$dest" ] && [ "$(sha256sum "$dest" | cut -d' ' -f1)" = "$sha" ]; then
      ok=$((ok+1)); continue
    fi
    echo "-> assembling $path ($parts parts)"
    if ! cat "$dest".part-* > "$dest.tmp" 2>/dev/null; then
      echo "   !! missing parts for $path" >&2; rm -f "$dest.tmp"; failed=$((failed+1)); continue
    fi
    mv "$dest.tmp" "$dest"; built=$((built+1))
  fi
  # verify (both assembled and whole tarballs)
  if [ -f "$dest" ] && [ "$(sha256sum "$dest" | cut -d' ' -f1)" = "$sha" ]; then
    [ "${parts:-0}" -gt 0 ] || ok=$((ok+1))
  else
    echo "   !! sha256 mismatch or missing: $path" >&2; failed=$((failed+1))
  fi
done < <(tail -n +2 "$MANIFEST")

echo "done: $ok ok, $built assembled, $failed failed."
[ "$failed" -eq 0 ]
