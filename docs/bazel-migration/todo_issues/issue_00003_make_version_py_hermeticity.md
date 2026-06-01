# Issue 00003: tools/make_version.py is not hermetic

> [!NOTE]
> **Upstream Tracking Issue**: https://github.com/dart-lang/sdk/issues/63475

## Problem

`tools/make_version.py` resolves several of its inputs implicitly:

- `tools/utils.py:92–93` computes `DART_DIR = abspath(__file__ + '/../..')` and
  `VERSION_FILE = os.path.join(DART_DIR, 'tools', 'VERSION')`.
- `make_version.py` reads `runtime/vm/<file>` for each entry in
  `VM_SNAPSHOT_FILES` (a hardcoded list in the script) to compute the snapshot
  MD5 hash.
- The script shells out to `git` from inside `DART_DIR` for the SDK hash
  unless `--no-git-hash` is passed.

Consequences:

- The script can only run from a checked-out SDK tree at the expected on-disk
  layout. Vendored Dart copies, sandboxed CI builds, and any build system that
  stages inputs into a different directory all need workarounds.
- The script's input set is **not declared** anywhere a build system can read.
  GN today approximates this by listing the snapshot files manually in
  `runtime/BUILD.gn:419–435`'s `inputs = [...]` block. The two lists (the
  Python `VM_SNAPSHOT_FILES` constant and the GN `inputs` array) must stay in
  sync by convention, with no enforcement. They have drifted before and will
  drift again.
- CI builds that want a deterministic version string must work around the
  implicit `git` shell-out (e.g., by clobbering `PATH`).

## Why this is an improvement on its own

- Declarative inputs make incremental rebuilds correct: editing `dart.cc`
  triggers a `version.cc` regeneration regardless of build system.
- The script becomes reusable: vendored Dart, custom embedders, code-search
  indexers, internal CI pipelines all benefit.
- Removes the implicit two-list drift between `VM_SNAPSHOT_FILES` in Python and
  `inputs = [...]` in GN.
- A single source of truth for which files affect snapshot compatibility.

## How it makes Bazel (and any other non-GN build) easier

Bazel `genrule()`s require every input to be declared in `srcs` so the
sandbox can stage it. Matching the staged file set against the Python
`VM_SNAPSHOT_FILES` list is fragile — any new entry on either side breaks the
genrule silently or with a confusing error. With explicit CLI flags, the
genrule passes its declared inputs directly.

## Proposed change (sketch)

Add CLI flags to `make_version.py` and `utils.py`:

- `--dart-dir <path>` — overrides `__file__`-derived DART_DIR
- `--version-file <path>` — overrides `tools/VERSION` lookup (already partially
  threaded through `--version-file`; complete the plumbing)
- `--snapshot-files <list>` — explicit set of files to hash for
  `{{SNAPSHOT_HASH}}`, replacing the hardcoded `VM_SNAPSHOT_FILES` constant
- `--git-hash <hash-or-empty>` — accept the SDK hash explicitly instead of
  shelling out to `git`

Keep current behavior as defaults so existing callers don't break.

## Affected code

- `tools/make_version.py` — input resolution, arg parsing, `VM_SNAPSHOT_FILES`
  constant
- `tools/utils.py:92–93` — `DART_DIR`, `VERSION_FILE` resolution
- `tools/utils.py:362,380,419,439,454,469` — `GetVersion`, `GetChannel`,
  `GetGitRevision`, `GetShortGitHash`, `GetGitTimestamp`,
  `GetGitTimestampForDpkg` — all anchor on `DART_DIR`
- `runtime/BUILD.gn:410–455` — `action("generate_version_cc_file")`, the
  `inputs = [...]` list that has to be kept in sync with `VM_SNAPSHOT_FILES`

## Notes

Discovered when wiring `make_version.py` into a Bazel genrule. The genrule
must declare every input file in `srcs`; matching that list against the
Python-side `VM_SNAPSHOT_FILES` was the only way to know what to declare. See
M5 hand-off memory bucket #4 for the workaround that landed.

## Resolution

On 2026-06-01 (Session ID: `a9fd9edd-2a96-4825-81a3-2b2cbc3bdde0`), the Bazel-side and Python script overrides were fully implemented and plumbed:
- Added and plumbed `--dart-dir`, `--version-file`, `--snapshot-files`, and `--git-hash` into `tools/make_version.py` and `tools/utils.py`.
- Updated `run_single_test.dart` and `test_rules.bzl` to utilize these explicit overrides dynamically inside the sandboxed Bazel sh_test targets.
- Successfully bypassed host-bound git shelling and snapshot file coupling for Bazel-driven dynamic executions.

The issue remains open for resolving the GN-side configuration coupling (`runtime/BUILD.gn`).
