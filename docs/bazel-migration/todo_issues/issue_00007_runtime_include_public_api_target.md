# Issue 00007: No GN target demarcates Dart's public VM embedding C API

> [!NOTE]
> **Upstream Tracking Issue**: https://github.com/dart-lang/sdk/issues/63474

## Problem

Dart exposes a public C API for embedders (Flutter, jaspr, custom hosts)
consisting of:

- `runtime/include/dart_api.h`
- `runtime/include/dart_native_api.h`
- `runtime/include/dart_tools_api.h`
- `runtime/include/analyze_snapshot_api.h`

This is the *contract* between the Dart VM and its embedders. Changes to
these headers are ABI/API-visible to every downstream consumer.

But `runtime/include/BUILD.gn` defines only a `copy_headers` action — there
is no `source_set` / `group` / `static_library` target that names this
contract. Internal code reaches these headers via the implicit
`-Iruntime/include` directory set in `runtime/BUILD.gn`'s
`dart_public_config`. Internal-but-VM-private headers (like
`dart_version.h`) live in the same directory without distinction.

Consequences:

- A reader looking at `runtime/include/BUILD.gn` cannot tell "this is the
  public embedding API"; the files look like a flat list to be copied.
- There is no machine-readable way to answer "what headers do embedders
  see?" — important for changelog generation, ABI audits, doc tooling.
- Adding, removing, or changing a public header is a structural change with
  no build-graph signal: no ABI gate, no test, no review checklist trigger.
- Public and private headers are co-located without a clear boundary.

## Why this is an improvement on its own

- Explicit boundary for the embedding API surface. Future PRs that change a
  public header become reviewable as "ABI-affecting" by virtue of touching
  this target.
- Could be paired with an ABI/API stability test (e.g., diff the exported
  symbol set against a checked-in baseline).
- Documentation tools can introspect the target to enumerate the public API.
- Refactoring the embedder API surface becomes a structural change with a
  build-graph footprint instead of a `git mv`.

## How it makes Bazel (and any other non-GN build) easier

In Bazel, a `cc_library(name = "public_api_headers", hdrs = [...])` lets
consumers depend on the API explicitly via `deps = [...]` rather than via
hidden `-I` flags. The current Bazel translation had to hand-write a
`runtime/include:headers` `cc_library` because there was no GN target to
reflect. Any future ABI tooling would benefit from the same explicitness on
the GN side.

## Proposed change (sketch)

In `runtime/include/BUILD.gn`:

```gn
source_set("public_api_headers") {
  # Header-only.
  sources = [
    "analyze_snapshot_api.h",
    "dart_api.h",
    "dart_native_api.h",
    "dart_tools_api.h",
  ]
  # Visibility could be restricted: embedders only, plus the internal
  # libraries that need to compile against the API.
}
```

Then have `:libdart_jit` etc. `public_deps` this target, and consider
visibility rules that keep purely-internal targets away from it.

## Affected code

- `runtime/include/BUILD.gn` — currently just a `copy_headers` action
- `runtime/BUILD.gn` `dart_public_config` — the implicit `-Iruntime/include`
- `runtime/include/dart_version.h` — internal-only; should NOT be in the
  public set
- All embedders and external consumers (long-term consideration for ABI
  stability tooling)

## Notes

Discovered during the Bazel migration — had to hand-write a
`runtime/include:headers` cc_library because there was no existing target to
depend on. See M5 hand-off memory. The same root pattern (no explicit "this
directory's headers" target, contents reached via implicit include paths) is
the subject of [[issue_00002_runtime_lib_no_gn_target]]; this issue is
narrower and specifically about the *public API* aspect.
