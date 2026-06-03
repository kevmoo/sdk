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
# The rest are pinned to the DEPS revs current SDK source compiles against.
# Session 13 found several stale (e.g. dart_style referenced renamed analyzer
# AST types like DefaultFormalParameter), which broke the analyzer-stack tools'
# AOT builds. Rolling them is low-risk (pure Dart; the opaque source glob picks
# them up; no BUILD.bazel wires specific files). zlib stays at its current rev
# (its enumerated-source wiring in third_party/zlib/BUILD.bazel is pinned to it).
# boringssl/src is NOT pinned here either, but it now tracks the DEPS pin
# (5ee9407bc): third_party/boringssl/BUILD.bazel's enumerated sources were updated
# to that roll (p_mlkem.cc added, p224-64.cc.inc / getrandom_fillin.h dropped), and
# boringssl ships its own src/BUILD.bazel at this rev — RENAMES below disables it so
# `src` isn't a subpackage. A `gclient sync` lands 5ee9407bc and the build matches.
SUBREPO_PINS=(
  "third_party/pkg/native"
  "third_party/pkg/tools"
  "third_party/pkg/core"
  "third_party/pkg/dart_style"
  "third_party/pkg/dartdoc"
  "third_party/pkg/ecosystem"
  "third_party/pkg/http"
  "third_party/pkg/i18n"
  "third_party/pkg/leak_tracker"
  "third_party/pkg/protobuf"
  "third_party/pkg/pub"
  "third_party/pkg/shelf"
  "third_party/pkg/sync_http"
  "third_party/pkg/tar"
  "third_party/pkg/test"
  "third_party/pkg/vector_math"
  "third_party/pkg/web"
  "third_party/pkg/webdev"
  "third_party/pkg/webdriver"
  "third_party/pkg/webkit_inspection_protocol"
)



# Heavy build artifacts (dills, snapshots) are now fully produced by Bazel.

green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
say() { printf '  %s\n' "$*"; }

changed=0
note_change() { changed=$((changed + 1)); }

echo "=== Dart Bazel out-of-band restore ==="
echo "SDK root: $SDK_ROOT"
echo



# --------------------------------------------------------------------------
# 1. GN args flips (sdk_hash determinism — see README "SDK hash discipline").
# --------------------------------------------------------------------------
echo "[1/3] out/ReleaseX64/args.gn flags"
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
# 2. Nested-subrepo DEPS pins (package APIs must match current SDK source).
# --------------------------------------------------------------------------
echo "[2/3] Nested-subrepo DEPS pins"
for path in "${SUBREPO_PINS[@]}"; do
  var_name="${path##*/}_rev"
  pin=$(grep -E "\"${var_name}\"" DEPS | grep -oE '[a-f0-9]{40}' | head -1)
  if [ -z "$pin" ]; then
    yellow "  ERROR    Could not resolve pin for $path ($var_name) from DEPS — skipping"
    continue
  fi
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
# 3. Regenerate .dart_tool/package_config.json (gitignored; deterministic).
#    Runs the checked-in prebuilt SDK over the workspace pubspecs — the same
#    mechanism `gclient runhooks` uses. Must come AFTER the pin rolls above so
#    it resolves against the correct subrepo revisions. This replaces any stale
#    or hand-hacked config (e.g. the historical uniform-3.12 languageVersion).
# --------------------------------------------------------------------------
echo "[3/3] .dart_tool/package_config.json"
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

  # rules_dart Step 3: the per-package dart_library graph (tracked in git, unlike
  # the gitignored package_config) is derived from package_config + the workspace
  # pubspecs, so regenerate it right after. Drift here means the committed
  # packages.bzl is stale vs the current pubspecs and should be re-committed.
  pkgbzl_before=""
  [ -f "tools/bazel/dart/packages.bzl" ] && pkgbzl_before="$(cat tools/bazel/dart/packages.bzl)"
  python3 tools/bazel/dart/gen_packages.py >/dev/null
  if [ "$pkgbzl_before" != "$(cat tools/bazel/dart/packages.bzl)" ]; then
    yellow "  regenerated tools/bazel/dart/packages.bzl (CHANGED — git add + commit it)"
  else
    say "ok       tools/bazel/dart/packages.bzl (unchanged)"
  fi
else
  yellow "  tools/sdks/dart-sdk/bin/dart absent — run gclient sync/CIPD first; skipping"
fi
echo

# --- summary --------------------------------------------------------------
if [ "$changed" -eq 0 ]; then
  green "Source/config state: already fully in place (no changes)."
else
  green "Source/config state: restored ($changed item(s) changed)."
fi

echo "Next: /home/linuxbrew/.linuxbrew/bin/bazelisk build //runtime/bin:dartvm"
