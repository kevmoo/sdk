# Issue 00010: `runtime/bin/BUILD.gn` uses "snapshot" to mean three different things without documentation

## Problem

`runtime/bin/BUILD.gn` defines three families of snapshot embeddings,
each producing a different `.bin`/`.S`/symbol triple, and the naming
is hard to disambiguate from the source alone:

| Symbol | Target | Used by | Source |
| --- | --- | --- | --- |
| `kDartCoreSnapshotData` / `kDartCoreSnapshotText` | `core_snapshot_data_linkable` / `core_snapshot_text_linkable` | `dartvm` (JIT) | `gen_snapshot --snapshot_kind=core` |
| `kDartVmSnapshotData` / `kDartVmSnapshotInstructions` | `vm_snapshot_data_linkable` / `vm_snapshot_instructions_linkable` | AOT product loaders | `gen_snapshot --snapshot_kind=vm-aot` |
| `kIsolateSnapshotData` / `kIsolateSnapshotInstructions` | `isolate_snapshot_data_linkable` / `isolate_snapshot_instructions_linkable` | AOT product loaders | `gen_snapshot --snapshot_kind=app-aot-blobs` |

A reader walking `runtime/bin/BUILD.gn` for the first time sees five
`bin_to_linkable` targets named `core_snapshot_*`, `vm_snapshot_*`,
`isolate_snapshot_*` and has no signal that:

- `core` is JIT-only, `vm`/`isolate` are AOT-only, and these are
  produced by *different* `gen_snapshot` invocations with different
  `--snapshot_kind` flags;
- the executable a developer is building (`dartvm` vs `dart` vs
  `dartaotruntime`) determines *which subset* of these artifacts gn
  needs to produce; a gn build that targets `dart` will never
  generate `core_snapshot_data.bin`, even though the file is what
  `dartvm` needs to boot;
- `snapshot_empty.cc` (a third "no snapshot" mode that links nullptr
  pointers for `kDartCoreSnapshotData/Text`) is selected for `dart`
  and `dartaotruntime` but not `dartvm`, and there is no comment in
  BUILD.gn or the .cc file explaining *why* dartvm is the odd one out.

## Why this is an improvement on its own

A new contributor reading `runtime/bin/BUILD.gn` cannot tell from the
target names alone:

1. Which snapshot family a given executable consumes.
2. Why three families exist (JIT vs AOT-vm-level vs AOT-isolate-level).
3. Why `snapshot_empty.cc` exists, when it's substituted, and what
   runtime fallback path it relies on.

Today this knowledge lives in commit messages, the `gen_snapshot --help`
output, and the VM's snapshot deserializer source. A `runtime/bin/`
README that names the three snapshot kinds, lists which executables
consume which, and points at `snapshot_empty.cc` as the JIT-fallback
escape hatch would let a contributor reason about
`runtime/bin/BUILD.gn` without reverse-engineering it.

## How it makes Bazel (and any other non-GN build) easier

The Bazel migration spent significant time discovering that:

- The gn `out/ReleaseX64/` directory available on disk did not contain
  `core_snapshot_data.bin` — because that gn build was for the AOT
  `dart` target, not `dartvm`. A Bazel cc_binary translation of
  `:dartvm` cannot use `out/` as a source of pre-built blobs without
  first realizing it is missing the JIT-specific snapshots.
- The `kKernelServiceDill` + `kPlatformDill` symbols (also embedded
  via `bin_to_linkable`) follow a totally different recipe than the
  three snapshot families: they wrap a CFE-produced `.dill` directly,
  not a `gen_snapshot` output. This is invisible from the BUILD.gn
  target naming — they sit next to `core_snapshot_data_linkable` and
  look like cousins, but the production pipeline is unrelated.

A docs/ README would let downstream build systems map executable →
required artifacts → producer in one place instead of by inspection.

## Proposed change

Add `runtime/bin/snapshots.md` (or extend an existing doc) with:

1. A table mapping symbol → producer → consumer (the table above is a
   starting point).
2. A short prose explanation: "dartvm is JIT and uses core snapshots;
   dart/dartaotruntime are AOT and use vm+isolate snapshots; in
   AOT-mode `snapshot_empty.cc` substitutes nullptr for the JIT
   symbols because the AOT product loader path does not consult
   them."
3. A pointer to `gen_snapshot --help` and the `--snapshot_kind` flag
   as the authority on what each `.bin` actually is.

Optionally, add a one-line comment above each `bin_to_linkable`
invocation in BUILD.gn pointing at the doc.

## Affected code

- `runtime/bin/BUILD.gn:622-789` — the `gen_snapshot_action` and
  `bin_to_linkable` blocks producing the five snapshot families.
- `runtime/bin/snapshot_empty.cc` — the JIT-fallback nullptr stubs.
- `runtime/bin/main_impl.cc:52-53` — the `core_snapshot_data` pointer
  assignment that consumes the JIT snapshots.

## Notes

Discovered during the Bazel migration M5 Path-1.5 work that embedded
real `kKernelServiceDill` and `kPlatformDill` from `out/` prebuilts.
The same chunk of work also tried to wire up `kDartCoreSnapshotData`
and `kDartCoreSnapshotText` from `out/` and discovered that those
files don't exist in a gn build whose target was `dart` (rather than
`dartvm`). The chain — "the user picked target X, so artifact Y is
missing, so dartvm can't be wired up the way you'd guess from looking
at BUILD.gn" — is the kind of indirection a docs page resolves
cheaply. See M5 hand-off memory and [[issue_00009_icudtl_path_exists_dual_layout]]
on the related theme of "runtime/bin's data embedding has implicit
layout/build-mode coupling."
