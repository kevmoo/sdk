# Issue 00005: Vendored third_party BUILD files conflict with sibling builds

## Problem

Several vendored `third_party/` trees still contain `BUILD.bazel` / `BUILD` /
`WORKSPACE` files inherited from their upstream Bazel setups, even though
Dart's build does not consume them. Concrete examples found in the tree:

- `third_party/perfetto/src/WORKSPACE`
- `third_party/perfetto/src/BUILD`
- `third_party/perfetto/src/bazel/BUILD`
- `third_party/perfetto/src/python/BUILD`
- `third_party/boringssl/src/BUILD.bazel`

Dart's GN does not reference any of these. They exist solely because the
import / roll scripts don't strip them. This causes concrete problems:

1. **Sibling Bazel-shaped tooling stumbles on them.** Any tool that walks the
   source tree and treats `BUILD*` / `WORKSPACE` as package boundaries (Bazel
   itself, `buildifier`, ide language servers, code search) sees nested
   "packages" that aren't real. The upstream BUILDs reference Bazel modules
   like `@rules_license` that aren't part of Dart's repo at all, so they
   cannot even be loaded — but the file still gates the directory.
2. **Repo grep / code search noise.** `git grep BUILD` and similar searches
   return many matches in vendored third_party that are irrelevant to anyone
   working on Dart.
3. **Vendoring intent is muddied.** A reviewer rolling perfetto can't tell at
   a glance which files in `third_party/perfetto/src/` Dart actually uses vs
   which are just upstream artifacts that came along for the ride.

## Why this is an improvement on its own

- Smaller, cleaner vendored copies. The diff in a perfetto/BoringSSL roll
  becomes "code changes only" instead of "code + irrelevant build-system
  files."
- Code search becomes accurate.
- The principle "import only what you use" is enforced at the file level.
- Reduces risk that some future tool accidentally consumes the upstream BUILD
  and gets a wrong answer.

## How it makes Bazel (and any other non-GN build) easier

In Bazel, a file named `BUILD` / `BUILD.bazel` creates a package boundary.
Globbing `third_party/perfetto/src/**/*.cc` from outside silently skips files
under the nested package. The Bazel migration had to rename the five files
above with a `.disabled-for-dart-bazel-migration` suffix to make `glob()`
descend correctly. A clean prune at vendor time would be permanent.

## Proposed change

When rolling these third_party deps, the import scripts should exclude:

- `**/BUILD.bazel`
- `**/BUILD`
- `**/WORKSPACE`
- `**/MODULE.bazel`

Already-imported stale files should be removed from the vendored copies (or
`.gitignore`d if the roll script can't be modified).

## Affected code

- Per-dep roll scripts (e.g., `tools/copy_tree.py`, manual import processes)
- Existing vendored trees:
  - `third_party/perfetto/src/`
  - `third_party/boringssl/src/`
  - Audit others for the same pattern

## Notes

Discovered during the Bazel migration. The session that found this had to
rename five files with a `.disabled-for-dart-bazel-migration` suffix and
explain the convention in the M5 hand-off memory. See `project-m3-handoff`
"Out-of-band working tree state" section.
