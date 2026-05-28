# Issue 00001: Split conlyopts/cxxopts for mixed-language third_party targets

## Problem

Several third_party libraries vendored in `third_party/` are pure C (notably
`third_party/zlib/`, the BoringSSL assembly compile units, libunwind) but the
SDK-wide GN configs apply C++-only flags via the shared `cflags` / `cflags_cc`
blocks without splitting them out as `cflags_c` for C-only targets. Flags like
`-std=c++20`, `-fno-rtti`, `-fvisibility-inlines-hidden`, and
`-Wheader-hygiene` end up on `.c` compile commands.

Clang silently ignores most of these for C files, but `-std=c++20` produces
`'-std=c++20' not allowed with 'C/ObjC'` style warnings that the build then
suppresses via broad `-Wno-*` masks. The compile DB
(`compile_commands.json`) records the wrong flags, and IDE integrations
(clangd, VS Code C/C++ extension) report phantom errors on C files.

## Why this is an improvement on its own

- Compile databases become accurate; IDE/clangd stops surfacing phantom
  diagnostics on `.c` files.
- The build no longer needs broad `-Wno-*` masks whose only purpose is hiding
  language-mismatch warnings.
- Intent is explicit: a flag in `cflags_c` is a deliberate C choice, one in
  `cflags_cc` is C++. Reviewer can tell from the GN file.
- `grep -n cflags_c` becomes a meaningful way to find C-language flag
  customization across the tree.

## How it makes Bazel (and any other non-GN build) easier

Bazel's `cc_library` exposes `conlyopts` (C-only) vs `cxxopts` (C++-only) vs
`copts` (both) as separate attributes. A translator consuming `gn desc` output
sees only a single `cflags` list per target and has to split it heuristically
(or worse, apply C++ flags to C files and hope nothing breaks). With the GN
side split, the translation is mechanical.

## Affected code

- `build/config/compiler/BUILD.gn` — `compiler` config (around line 55), where
  `cflags`/`cflags_cc` are populated for all targets.
- `build/config/compiler/BUILD.gn:569` — `runtime_library` config, same shape.
- `third_party/zlib/BUILD.gn` — pure C target getting C++ flags.
- BoringSSL assembly compile blocks in `third_party/boringssl/BUILD.gn`.

## Notes

Discovered during the Bazel migration — `zlib` was being compiled with
`-std=c++20` and `-fno-rtti`, and the Bazel translator had to manually strip
C++-only flags from the C target's `copts`. See M5 hand-off memory
(`project-m3-handoff`) bucket discussions.
