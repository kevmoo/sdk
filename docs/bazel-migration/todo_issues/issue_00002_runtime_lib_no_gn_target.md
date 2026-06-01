# Issue 00002: runtime/lib/ has no GN target — implicit cross-package coupling

## Problem

The `runtime/lib/` directory contains both `.cc` files and `.h` files but has
no `BUILD.gn`. Its contents are reached via two layers of indirection:

1. `.cc` files are sourced into other targets via `*_sources.gni` files in
   sibling packages (e.g., `runtime/vm/lib_sources.gni`).
2. `.h` files are reached via the implicit `-Iruntime` include directory that
   `runtime/BUILD.gn`'s `dart_public_config` propagates to dependents.

A reader trying to understand "what is runtime/lib? who depends on these
headers?" has to trace `*_sources.gni` across packages and decode
`include_dirs = ["."]` magic in `runtime/BUILD.gn`. Tools like `gn refs
runtime/lib:*` return nothing because there is no target to reference.

This is the only directory under `runtime/` without its own `BUILD.gn`.

## Why this is an improvement on its own

- Makes the dependency graph explicit and greppable: `gn refs runtime/lib:lib`
  becomes the obvious way to ask "who uses runtime/lib?"
- A future split, rename, or move of `runtime/lib/` becomes a local refactor
  instead of a cross-package source-list hunt.
- Reduces "magic" — every other directory in `runtime/` has a `BUILD.gn`;
  `lib/` is the outlier and new contributors notice.
- Documents the intended boundary of the directory.

## How it makes Bazel (and any other non-GN build) easier

`gn desc` emits no metadata for directories without targets. The Bazel
translator had to hand-write a `runtime/lib/BUILD.bazel` from scratch with no
GN reference point to translate. Any tool that walks GN's metadata to
understand the build graph has the same blind spot.

## Affected code

- `runtime/lib/` (no `BUILD.gn`)
- `runtime/vm/lib_sources.gni` (cross-package sourcing of the `.cc` files)
- `runtime/BUILD.gn` `dart_public_config` (implicit `-Iruntime` exposes the
  `.h` files)

## Notes

Discovered during the M3 Bazel migration — see hand-off memory note about
`runtime/lib/BUILD.bazel` being hand-written. The same root cause likely
affects other directories whose headers are reached via implicit include
paths rather than explicit deps; this issue covers `runtime/lib/` specifically
but the pattern deserves an audit.

## Resolution

On 2026-06-01 (Session ID: `b9e89cb8-0cfd-483f-b161-ceadc8665400`), the GN target structure for `runtime/lib/` was resolved:
- Created a proper `runtime/lib/BUILD.gn` file.
- Defined the `libdart_lib` target inside `runtime/lib/BUILD.gn` using `library_for_all_configs`, encapsulating all C++ sources in `runtime/lib/` (via importing the local `*_sources.gni` files) and `../vm/bootstrap.cc`.
- Refactored `runtime/vm/BUILD.gn` to remove the redundant imports of `runtime/lib/*_sources.gni` and the `libdart_lib` target definition.
- Updated `runtime/BUILD.gn` to depend on `lib:libdart_lib` instead of `vm:libdart_lib`.
- Verified that the GN build configuration is correct and compiles successfully.
- In Session `4c2ae753-e033-480a-a580-b7fad5393a0d` (current), the Bazel-side resolution was completed:
  - Registered `runtime/lib` as a translated package by adding it to the allowlist in `translate_gn_desc.py`.
  - Hand-authored a clean `runtime/lib/BUILD.bazel` overlay to call the generated `gen_targets()` macro.
  - Cleaned up and excised over 1,600 lines of obsolete/orphaned `libdart_lib_...` targets from `runtime/vm/BUILD.bazel`.
  - Resolved header isolation compiler failures under Bazel's strict sandboxing by adding direct dependencies on `//runtime/platform:libdart_platform` and `//runtime:dart_api` inside `runtime/lib/BUILD.gn`'s `configurable_deps` and `extra_deps`, propagating them cleanly to generated Bazel targets.
  - Fixed cross-compilation target-architecture define clashes by updating the GN-to-Bazel translator to avoid stripping architecture and OS defines for explicit cross-targeting targets (`_linux_arm`, `_linux_arm64`, `_linux_riscv64`, `_linux_x64`) and correctly injecting `//build/config:dart_mode_no_arch` into their dependencies.
  - Fully compiled and validated the final SDK build (`bazel build //sdk:create_sdk`) cleanly with zero errors.

This issue is now fully resolved and closed on both the GN and Bazel build sides.

