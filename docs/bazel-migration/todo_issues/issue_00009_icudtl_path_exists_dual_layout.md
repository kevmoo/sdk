# Issue 00009: `icudtl_linkable` uses `path_exists()` to dual-source between Dart SDK and Flutter engine layouts

> [!NOTE]
> **Upstream Tracking Issue**: https://github.com/dart-lang/sdk/issues/63473

## Problem

`runtime/bin/BUILD.gn:781` defines the `icudtl_linkable` target with a
build-time path probe to pick one of two locations for `icudtl.dat`:

```gn
bin_to_linkable("icudtl_linkable") {
  deps = []
  if (path_exists("//third_party/icu/flutter/icudtl.dat")) {
    input = "//third_party/icu/flutter/icudtl.dat"
  } else {
    input = "//flutter/third_party/icu/flutter/icudtl.dat"
  }
  symbol = "kIcuData"
  executable = false
}
```

The two branches reflect two source-tree layouts:

- **Dart SDK standalone checkout** — the source root is the Dart SDK; ICU is
  at `//third_party/icu/flutter/icudtl.dat`.
- **Flutter engine checkout** — the source root is the Flutter engine; ICU is
  at `//flutter/third_party/icu/flutter/icudtl.dat` (because the engine
  vendors a different ICU tree at a different path).

`path_exists()` is a GN built-in that runs at *gen* time and silently picks
whichever path is present on disk. There is no comment, no `assert`, and no
configuration variable — the layout is selected by filesystem inspection.

Consequences:

- A future contributor reading this BUILD.gn has no signal that two embedder
  contexts (standalone Dart vs. Flutter engine) are being supported here. The
  layouts are equally plausible siblings; nothing distinguishes them as
  "primary" vs. "fallback."
- The two paths happen to embed *different* `icudtl.dat` files in practice
  (the Dart SDK's `third_party/icu/flutter/icudtl.dat` is the 862 KB
  flutter-pruned copy; the Flutter engine vendors its own copy of the same).
  The build silently picks whichever is present, so the choice of `kIcuData`
  contents is implicitly tied to the checkout shape rather than declared.
- Any build system that doesn't replicate `path_exists()` semantics (Bazel
  doesn't have a direct equivalent that runs at analysis time) has to encode
  the layout assumption out of band, and lose the auto-fallback behavior.

## Why this is an improvement on its own

- Documents the implicit coupling between Dart's `runtime/bin/BUILD.gn` and
  the Flutter engine's source layout. Today this coupling is invisible to a
  reader who hasn't seen the Flutter engine checkout.
- Makes the choice explicit: a configuration variable or `import()`ed
  per-checkout `.gni` would put the "which layout is this?" decision in one
  named place, instead of inferring it from filesystem state.
- Removes a silent failure mode where a partial checkout (e.g., missing
  `third_party/icu/flutter/icudtl.dat`) silently picks up an unexpected ICU
  blob from the fallback path, instead of erroring out.

## How it makes Bazel (and any other non-GN build) easier

Bazel's analysis phase resolves labels statically — there is no equivalent of
GN's `path_exists()` build-time probe. The Bazel migration had to hard-code
the Dart-SDK-checkout path (`//third_party/icu/flutter:icudtl.dat`) because
that's the only path it can resolve. The Flutter engine layout would require
a separate Bazel `MODULE.bazel` configuration. If the GN target had a named
config variable, the Bazel side could mirror it; today it has to silently
diverge.

## Proposed change

Replace the `path_exists()` probe with an explicit GN argument or import:

- **(a) `declare_args { dart_icudtl_dat = "//third_party/icu/flutter/icudtl.dat" }`**
  with each embedder overriding the default. The argument's default value
  documents what the standalone Dart SDK expects; the Flutter engine sets it
  via `args.gn`.
- **(b) `import("//flutter/build/icu_data.gni")` in Flutter-engine-aware
  builds, defaulting to the SDK-local path otherwise.** The import line
  serves as the documentation handle.

Either approach makes the layout choice explicit and named.

## Affected code

- `runtime/bin/BUILD.gn:781` — the `icudtl_linkable` target with the
  `path_exists()` branch
- Any Flutter-engine-side build config that today depends on the implicit
  fallback

## Notes

Discovered during the Bazel migration M5 Path-1.5 work that embedded a real
`icudtl.dat` (replacing the empty `kIcuData` stub). The Bazel genrule had to
hard-code `//third_party/icu/flutter:icudtl.dat` since Bazel has no
equivalent of GN's `path_exists()` probe. See M5 hand-off memory for the
genrule wiring. Cross-references [[issue_00006_icu_data_headers_inconsistency]]
on the broader theme of "Dart's ICU vendoring carries undocumented assumptions."
