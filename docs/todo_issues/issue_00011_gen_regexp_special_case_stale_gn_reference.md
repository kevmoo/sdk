# Issue 00011: `runtime/vm/BUILD.gn` references a renamed source file; `gen_regexp_special_case` is unbuildable

## Problem

`runtime/vm/BUILD.gn:277` declares:

```gn
executable("gen_regexp_special_case") {
  ...
  sources = [ "regexp/gen_regexp_special_case.cc" ]
  ...
}
```

That file does not exist on disk. Commit `e443b89f238` ([vm] Update
Irregexp to V8 commit 254cc758346f, 2026-02-23) imported the V8 Irregexp
update with the V8 naming convention (kebab-case) — the actual source on
disk today is `runtime/vm/regexp/gen-regexp-special-case.cc`. The GN
`sources` reference was not updated to match the renamed file, leaving
the `gen_regexp_special_case` executable pointing at a non-existent
source. Reproducing:

```
$ ls runtime/vm/regexp/gen*
runtime/vm/regexp/gen-regexp-special-case.cc

$ cd out/ReleaseX64 && ninja -n gen_regexp_special_case
ninja: error: '../../runtime/vm/regexp/gen_regexp_special_case.cc',
  needed by 'obj/runtime/vm/regexp/gen_regexp_special_case.gen_regexp_special_case.o',
  missing and no known rule to make it
```

The target has been silently broken for ~3 months.

## Why this is an improvement on its own

`gen_regexp_special_case` is a build-time tool that emits hard-coded
character-class tables used by Irregexp. Today the executable is
unbuildable, which means:

- Anyone trying to regenerate the special-case tables (e.g., after a
  Unicode-data update) hits a ninja "missing source" error with no
  guidance about which file was renamed.
- The breakage is invisible to CI because nothing in the default build
  graph depends on the executable; it is only invoked manually when the
  tables need regenerating (per `runtime/vm/regexp/README.md` and the
  comments in `gen-regexp-special-case.cc`).
- The GN file says `sources = [ "regexp/gen_regexp_special_case.cc" ]`
  but the only file on disk is `gen-regexp-special-case.cc`. A reader
  cannot tell from the source tree whether the executable was supposed
  to be deleted, the file is meant to be code-generated, or someone
  forgot to update the reference.

The fix is a one-character edit (`s/_/-/g` in two places of the
filename) plus, ideally, a presubmit lint or "tier 0" build that ensures
all GN `sources = [...]` references resolve to files on disk so the next
upstream-style file rename surfaces immediately.

## How it makes Bazel (and any other non-GN build) easier

The Bazel migration discovered this because the translated
`runtime/vm/BUILD.bazel` cc_binary for `gen_regexp_special_case` was
emitted with empty `srcs` (the translator dropped the source list,
likely because `gn desc --format=json` reports it but the file is
missing, or the translator chose to skip missing files). The Bazel side
failed link with "undefined symbol: main", which led to the GN audit
that turned up the stale reference.

Any non-GN build that wants to mirror the GN sources list will trip on
the same issue: it'll either inherit a missing-source error from `gn
desc` output, or silently drop the source and produce an unlinkable
binary. Fixing the GN reference removes the divergence between the GN
declaration and the disk reality.

## Affected code

- `runtime/vm/BUILD.gn:277` — `sources = [ "regexp/gen_regexp_special_case.cc" ]`
  should be `sources = [ "regexp/gen-regexp-special-case.cc" ]`.
- `runtime/vm/regexp/gen-regexp-special-case.cc` — actual source on disk
  since `e443b89f238`.

## Notes

Surfaced during the Bazel M5 follow-up that tried to build the remaining
cc_binaries beyond `dartvm` (session 6, 2026-05-28). The other recent
cc_binary builds (`gen_snapshot`, `gen_snapshot_host_targeting_host`,
`gen_snapshot_product`, `gen_snapshot_product_host_targeting_host`,
`gen_snapshot_product_linux_x64`, `dart`, `dartaotruntime{,_product}`,
`analyze_snapshot`, `run_vm_tests`) all link cleanly; only
`gen_regexp_special_case` failed, and the failure traced to a
missing-from-disk source rather than any Bazel-side wiring.
