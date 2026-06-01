# Issue 00006: ICU data headers are excluded by upstream :headers but used by Dart

## Problem

The upstream ICU Bazel file at
`third_party/icu/source/common/BUILD.bazel` defines a `:headers` `cc_library`
that **excludes** a specific set of files via a glob exclude:

```python
hdrs = glob(
    [
        "unicode/*.h",  # public
        "*.h",          # internal
    ],
    # Instead of using these checked-in files, our Bazel build process
    # regenerates them and then uses the new versions.
    exclude = ["norm2_nfc_data.h", "propname_data.h", "*_props_data.h"],
),
```

These are precompiled Unicode data tables. The upstream rationale, stated in
the comment, is that the upstream ICU Bazel build regenerates them.

**Dart uses the checked-in versions** — there is no regeneration step in
Dart's build. The files exist on disk in `third_party/icu/source/common/`
(verified: `norm2_nfc_data.h`, `propname_data.h`, `ubidi_props_data.h`,
`ucase_props_data.h`, `uchar_props_data.h`, plus `localefallback_data.h` and
`ucol_data.h`), and ICU source files `#include` them, but they are not
surfaced via any build target.

In GN this works only because every ICU `.cpp` file that needs them is
compiled with `-Ithird_party/icu/source/common`, which lets the compiler
resolve the include via direct filesystem lookup. There is no
build-system-tracked header dependency.

Consequences:

- If a data table is updated (e.g., during an ICU roll), nothing in the
  build graph knows to invalidate the `.o` files that include it. Incremental
  rebuilds may use stale objects.
- Anyone wiring ICU into a build system that doesn't replicate the
  `-Ithird_party/icu/source/common` magic gets silent compile failures.
- The disconnect between upstream's "regenerate" assumption and Dart's "use
  checked-in" practice is undocumented anywhere a future reviewer would
  notice.

## Why this is an improvement on its own

- Dependency tracking becomes correct: editing one of the data headers
  triggers rebuild of every TU that includes it, in every build system.
- Documents Dart's actual position (we use checked-in data tables, not
  regenerated ones) somewhere a future reviewer can find it.
- Prevents subtle skew during ICU rolls.

## How it makes Bazel (and any other non-GN build) easier

Bazel respects declared `hdrs` for dependency tracking and visibility. With
the data tables excluded from `:headers`, any Bazel target that depends on
`:icuuc` cannot compile sources that include them — even though they exist on
disk. The Bazel migration had to list every excluded data header explicitly
in `srcs` of its icuuc shim. Any other build system has the same problem.

## Proposed change

Pick one (Dart side decides which):

- **(a) Follow upstream's assumption.** Add a build step (GN action or
  similar) that regenerates the data tables, matching upstream ICU's Bazel
  build. The `exclude` then becomes correct for Dart too.
- **(b) Document the divergence and expose the tables.** Add a Dart-side
  comment in `third_party/icu/BUILD.gn` (or a vendored `.gni`) stating
  "Dart uses checked-in data tables." Add a header target — or extend the
  existing one — that explicitly includes the excluded files.

Either is fine; the goal is to remove the silent reliance on filesystem
lookup.

## Affected code

- `third_party/icu/source/common/BUILD.bazel` — the `exclude = [...]` block
- `third_party/icu/BUILD.gn` — where Dart applies ICU configs
- Any consumer of ICU that adds `-Ithird_party/icu/source/common` to its
  compile path

## Notes

Discovered during the Bazel migration. The icuuc shim had to list every data
header explicitly in `srcs` to make compiles succeed. See M5 hand-off memory
bucket #2 / ICU section for the workaround.
