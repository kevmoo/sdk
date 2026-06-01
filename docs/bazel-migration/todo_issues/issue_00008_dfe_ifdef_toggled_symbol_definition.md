# Issue 00008: runtime/bin/dfe.cc uses ifdef-toggled symbol definitions

## Problem

`runtime/bin/dfe.cc:18–30` contains an `extern "C"` block that switches
between *declaring* external symbols and *defining* nullptr placeholders for
the same names, based on a single build flag:

```cpp
extern "C" {
#if !defined(EXCLUDE_CFE_AND_KERNEL_PLATFORM)
extern const uint8_t kKernelServiceDill[];
extern intptr_t kKernelServiceDillSize;
extern const uint8_t kPlatformDill[];
extern intptr_t kPlatformDillSize;
#else
const uint8_t* kKernelServiceDill = nullptr;
intptr_t kKernelServiceDillSize = 0;
const uint8_t* kPlatformDill = nullptr;
intptr_t kPlatformDillSize = 0;
#endif
}
```

Worth noting: the two branches don't even use compatible C types
(`const uint8_t kFoo[]` vs `const uint8_t* kFoo`). Linkers happen to accept
this in `extern "C"` because both produce a symbol named `kFoo` and the
caller-side code (in `dfe.cc` itself) uses each accordingly. The C++ type
system isn't actually being asked to reconcile them across TUs.

Consequences:

- The set of symbols this TU exports depends on a preprocessor flag. IDEs,
  clangd, and code-search tools struggle to give consistent answers about
  "what does this file define?"
- The two type signatures could cause optimizer surprises if
  `EXCLUDE_CFE_AND_KERNEL_PLATFORM` were ever flipped while a caller
  elsewhere assumed the wrong type.
- The pattern repeats: similar "swap real blob for nullptr stub" branching
  exists across the bin/ tree (see e.g. `snapshot_empty.cc` for a
  cleaner-but-still-not-great variant for the snapshot data symbols).

## Why this is an improvement on its own

- One translation unit, one stable set of exported symbols. Easier to read,
  easier to tool, no preprocessor surprise.
- Build flags govern which `.cc` file is in the build, not which symbols a
  given TU exports.
- Standard "interface + two implementations" pattern, well-understood and
  greppable.
- Removes the latent type-mismatch hazard if the flag is ever flipped.

## Proposed change

Split into three files:

- `dfe.cc` — logic only. Uses the four symbols as `extern` unconditionally.
- `dfe_empty_kernel_stubs.cc` — provides nullptr / zero definitions for the
  four symbols. Linked when `EXCLUDE_CFE_AND_KERNEL_PLATFORM` is set.
- `dfe_real_kernel_stubs.cc` — empty (or a single comment). Linked when
  `EXCLUDE_CFE_AND_KERNEL_PLATFORM` is unset; the real symbols come from the
  generated `kernel_service.dill` / `platform.dill` `.S` files.

`runtime/bin/BUILD.gn` picks which of the two stub files to include based on
the flag. Same pattern as the existing `snapshot_empty.cc` vs generated
`vm_snapshot_data.S` swap, but applied symmetrically.

## Affected code

- `runtime/bin/dfe.cc:18–30` — the ifdef-toggled block
- `runtime/bin/BUILD.gn` — the conditional that defines
  `EXCLUDE_CFE_AND_KERNEL_PLATFORM`
- `runtime/bin/snapshot_empty.cc` — related cleaner-but-still-not-great
  pattern worth auditing in the same refactor

## Notes

Discovered during the Bazel migration — needed to provide nullptr stubs for
the same symbols (see `runtime/bin/bazel_link_stubs.cc`) and ran into the
type-mismatch / C++ const-linkage subtlety. See M5 hand-off memory bucket #6
"snapshot-data genrule outputs."
