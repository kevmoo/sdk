#!/usr/bin/env bash
#
# restore.sh — re-apply the Dart Bazel migration's out-of-band working-tree state.
#
# WHY THIS EXISTS
#   A large amount of load-bearing state for the Bazel build cannot live in the
#   SDK's own git history: it sits inside depot_tools/gclient-managed nested
#   clones (third_party/icu, /zlib, /boringssl, /perfetto, /pkg/native,
#   /pkg/tools) that the outer SDK repo treats as opaque, plus a handful of files
#   under the gitignored out/ tree and the gitignored .dart_tool/package_config.json.
#   Two routine operations silently wipe this state:
#     1. `gclient sync`                 — resets the nested subrepos.
#     2. re-running the GN->Bazel translator (tools/bazel/translate_gn_desc.py).
#
#   This script makes that state reproducible: run it after either operation to
#   put everything back, then `bazel build //runtime/bin:dartvm`.
#
# SCOPE
#   Restores SOURCE / CONFIG state only (the fragile, hand-authored bits).
#   Heavy BUILD ARTIFACTS (dills, snapshot blobs) are build outputs, not source;
#   this script only *verifies* they exist and prints the regen recipe if not.
#   See README.md for the full threat model and the artifact regen recipes.
#
# IDEMPOTENT: safe to run repeatedly. Each step is a no-op if already applied.

set -euo pipefail

# --- locate the SDK root from this script's location ----------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SDK_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SNAP="$SCRIPT_DIR/snapshot"
cd "$SDK_ROOT"

# Nested gclient-managed subrepos that must sit at a specific upstream revision
# for their package APIs to match current SDK source (DEPS pins; see README).
#   pkg/native — record_use API (DefinitionWithInstances etc.); rebuilds kernel_service.dill.
#   pkg/tools  — package:unified_analytics API (DashEnvVar / ideName /
#                areAnalyticsSuppressed); needed by dartdev + analysis_server.
SUBREPO_PINS=(
  "third_party/pkg/native:b814f5393753e0cd752ce3ad733f5e66dd5949ce"
  "third_party/pkg/tools:6a7dd15748e63db7d41cfee8294c54636b668f41"
)

DISABLED_SUFFIX=".disabled-for-dart-bazel-migration"

# Files that block our glob()s / pull in unavailable Bazel deps; renamed aside.
RENAMES=(
  "third_party/boringssl/src/BUILD.bazel"
  "third_party/perfetto/src/WORKSPACE"
  "third_party/perfetto/src/BUILD"
  "third_party/perfetto/src/bazel/BUILD"
  "third_party/perfetto/src/python/BUILD"
)

# Build artifacts this script does NOT produce but the build needs (see README).
ARTIFACTS=(
  "out/ReleaseX64/vm_platform.dill"
  "out/ReleaseX64/vm_platform_stripped.dill"
  "out/ReleaseX64/gen/kernel_service.dill"
  "out/ReleaseX64/gen/runtime/bin/core_snapshot_data.bin"
  "out/ReleaseX64/gen/runtime/bin/core_snapshot_text.bin"
)

green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
say() { printf '  %s\n' "$*"; }

changed=0
note_change() { changed=$((changed + 1)); }

echo "=== Dart Bazel out-of-band restore ==="
echo "SDK root: $SDK_ROOT"
echo

# --------------------------------------------------------------------------
# 1. Verbatim files (wholly ours): every *.snap under snapshot/ maps to the
#    same path with the snapshot/ prefix and .snap suffix removed.
# --------------------------------------------------------------------------
echo "[1/7] Verbatim files (.snap)"
while IFS= read -r -d '' src; do
  rel="${src#"$SNAP"/}"          # e.g. third_party/icu/BUILD.bazel.snap
  dest="${rel%.snap}"           # e.g. third_party/icu/BUILD.bazel
  mkdir -p "$(dirname "$dest")"
  if [ -f "$dest" ] && cmp -s "$src" "$dest"; then
    say "ok       $dest"
  else
    cp "$src" "$dest"
    say "restored $dest"
    note_change
  fi
done < <(find "$SNAP" -type f -name '*.snap' -print0)
echo

# --------------------------------------------------------------------------
# 2. Append blocks: every *.append appends a "# Dart Bazel M5:" marked block
#    to an upstream file. Idempotent via the marker.
# --------------------------------------------------------------------------
echo "[2/7] Append blocks (.append)"
while IFS= read -r -d '' src; do
  rel="${src#"$SNAP"/}"          # third_party/icu/source/common/BUILD.bazel.append
  dest="${rel%.append}"         # third_party/icu/source/common/BUILD.bazel
  if [ ! -f "$dest" ]; then
    yellow "  MISSING upstream file: $dest (skipping append — investigate)"
    continue
  fi
  if grep -q "Dart Bazel M5" "$dest"; then
    say "ok       $dest (marker present)"
  else
    cat "$src" >> "$dest"
    say "appended $dest"
    note_change
  fi
done < <(find "$SNAP" -type f -name '*.append' -print0)
echo

# --------------------------------------------------------------------------
# 3. Disabling renames (move blocking upstream BUILD/WORKSPACE files aside).
# --------------------------------------------------------------------------
echo "[3/7] Disabling renames"
for f in "${RENAMES[@]}"; do
  disabled="${f}${DISABLED_SUFFIX}"
  if [ -e "$disabled" ]; then
    say "ok       $f (already disabled)"
  elif [ -e "$f" ]; then
    mv "$f" "$disabled"
    say "disabled $f"
    note_change
  else
    yellow "  ABSENT   $f and its .disabled form — upstream layout may have changed; investigate"
  fi
done
echo

# --------------------------------------------------------------------------
# 4. GN args flips (sdk_hash determinism — see README "SDK hash discipline").
# --------------------------------------------------------------------------
echo "[4/7] out/ReleaseX64/args.gn flags"
ARGS_GN="out/ReleaseX64/args.gn"
set_gn_false() {
  local key="$1"
  if [ ! -f "$ARGS_GN" ]; then return; fi
  if grep -qE "^${key} = false$" "$ARGS_GN"; then
    say "ok       ${key} = false"
  elif grep -qE "^${key} = " "$ARGS_GN"; then
    sed -i -E "s/^${key} = .*/${key} = false/" "$ARGS_GN"
    say "set      ${key} = false"
    note_change
  else
    printf '%s = false\n' "$key" >> "$ARGS_GN"
    say "added    ${key} = false"
    note_change
  fi
}
if [ -f "$ARGS_GN" ]; then
  set_gn_false "verify_sdk_hash"
  set_gn_false "dart_version_git_info"
else
  yellow "  $ARGS_GN absent — skipping (run gn gen first if you need a bazel-interop out/)"
fi
echo

# --------------------------------------------------------------------------
# 5. Nested-subrepo DEPS pins (package APIs must match current SDK source).
# --------------------------------------------------------------------------
echo "[5/7] Nested-subrepo DEPS pins"
for entry in "${SUBREPO_PINS[@]}"; do
  path="${entry%%:*}"
  pin="${entry#*:}"
  if [ -d "$path/.git" ]; then
    cur="$(git -C "$path" rev-parse HEAD)"
    if [ "$cur" = "$pin" ]; then
      say "ok       $path at pin ${pin:0:12}"
    else
      say "rolling  $path ${cur:0:12} -> ${pin:0:12}"
      if ! git -C "$path" checkout -q "$pin" 2>/dev/null; then
        git -C "$path" fetch -q origin "$pin" 2>/dev/null || \
          git -C "$path" fetch -q origin
        git -C "$path" checkout -q "$pin"
      fi
      note_change
    fi
  else
    yellow "  $path is not a git checkout — skipping"
  fi
done
echo

# --------------------------------------------------------------------------
# 6. Regenerate .dart_tool/package_config.json (gitignored; deterministic).
#    Runs the checked-in prebuilt SDK over the workspace pubspecs — the same
#    mechanism `gclient runhooks` uses. Must come AFTER the pin rolls above so
#    it resolves against the correct subrepo revisions. This replaces any stale
#    or hand-hacked config (e.g. the historical uniform-3.12 languageVersion).
# --------------------------------------------------------------------------
echo "[6/7] .dart_tool/package_config.json"
if [ -x "tools/sdks/dart-sdk/bin/dart" ]; then
  before=""
  [ -f ".dart_tool/package_config.json" ] && before="$(cat .dart_tool/package_config.json)"
  python3 tools/generate_package_config.py >/dev/null
  if [ "$before" != "$(cat .dart_tool/package_config.json)" ]; then
    say "regenerated .dart_tool/package_config.json"
    note_change
  else
    say "ok       .dart_tool/package_config.json (unchanged)"
  fi
else
  yellow "  tools/sdks/dart-sdk/bin/dart absent — run gclient sync/CIPD first; skipping"
fi
echo

# --------------------------------------------------------------------------
# 7. Verify heavy artifacts (NOT produced here — see README for regen recipes).
# --------------------------------------------------------------------------
echo "[7/7] Build artifacts (verify only)"
missing=0
for a in "${ARTIFACTS[@]}"; do
  if [ -f "$a" ]; then
    say "present  $a"
  else
    yellow "  MISSING  $a"
    missing=$((missing + 1))
  fi
done
echo

# --- summary --------------------------------------------------------------
if [ "$changed" -eq 0 ]; then
  green "Source/config state: already fully in place (no changes)."
else
  green "Source/config state: restored ($changed item(s) changed)."
fi

if [ "$missing" -gt 0 ]; then
  echo
  yellow "$missing build artifact(s) missing. The bazel build will fail until they exist."
  yellow "Regen recipes are in tools/bazel/out_of_band/README.md ('Build artifacts')."
  echo
fi

echo "Next: /home/linuxbrew/.linuxbrew/bin/bazelisk build //runtime/bin:dartvm"
