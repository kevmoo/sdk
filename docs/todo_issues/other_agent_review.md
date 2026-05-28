# Standalone SDK Review of Surface Improvement Proposals

This review evaluates the nine proposed Dart SDK internal improvements surfaced by the Bazel migration. 

As a **Bazel-skeptical SDK engineer**, my baseline is simple: **If a change exists only to make a non-GN build system (like Bazel) easier, we should reject it.** Every proposal must justify its footprint by making the Dart SDK's build hygiene, IDE experience, maintainability, or safety demonstrably better on its own.

---

## Summary Table

| Issue | Topic | Standalone SDK Benefit | Skeptical Recommendation |
| :--- | :--- | :--- | :--- |
| [Issue 00001](issue_00001_split_conlyopts_cxxopts.md) | Split `conlyopts` and `cxxopts` | **High** — Fixes IDE phantom errors on C files, removes broad warning suppression masks. | **Strong Accept** |
| [Issue 00002](issue_00002_runtime_lib_no_gn_target.md) | Dedicate GN target for `runtime/lib` | **Medium** — Improves dependency graph explicitness, reduces implicit include directories. | **Accept** (as a private `source_set`) |
| [Issue 00003](issue_00003_make_version_py_hermeticity.md) | Hermetic versioning scripts | **Very High** — Prevents two-list drift, fixes sandboxed and source-tarball builds. | **Strong Accept** (High Priority) |
| [Issue 00004](issue_00004_perfetto_disable_log.md) | Set `PERFETTO_DISABLE_LOG` macro | **High** — Fixes fragile linker dependency assumptions, eliminates dead code. | **Strong Accept** |
| [Issue 00005](issue_00005_vendored_third_party_build_files.md) | Clean up third_party unused BUILD files | **Low** — Minor tidying. Avoids IDE package-boundary confusion. | **Accept** (Minimal effort in roll scripts) |
| [Issue 00006](issue_00006_icu_data_headers_inconsistency.md) | ICU header dependency tracking | **Medium-High** — Fixes potential incremental build bugs where data skews go untracked. | **Strong Accept** (Option B) |
| [Issue 00007](issue_00007_runtime_include_public_api_target.md) | Demarcate embedding public C API | **High** — Formalizes the SDK public contract, enables public header audit tooling. | **Strong Accept** |
| [Issue 00008](issue_00008_dfe_ifdef_toggled_symbol_definition.md) | Eliminate `dfe.cc` type-hacks | **High** — Fixes linker hacks and incompatible type-mismatches under `#ifdef` blocks. | **Strong Accept** |
| [Issue 00009](issue_00009_icudtl_path_exists_dual_layout.md) | Replace `path_exists()` with args | **Very High** — Eliminates filesystem-sniffing anti-pattern, enforces explicit configuration. | **Strong Accept** (High Priority) |

---

## Detailed Evaluations

### [Issue 00001: Split conlyopts/cxxopts for mixed-language third_party targets](issue_00001_split_conlyopts_cxxopts.md)

*   **The Bazel-Independent Problem**: GN applies C++20 flags (`-std=c++20`, `-fno-rtti`, etc.) to pure C compilers when compiling vendored third_party code (e.g., `zlib`, BoringSSL assembly files). To prevent the build from breaking, we mask the language-mismatch warnings globally. Consequently, the compile database (`compile_commands.json`) is polluted with incorrect compiler arguments, and modern language servers (like `clangd` or VS Code) spam developers with phantom errors on `.c` files.
*   **Skeptical Critique**: This is a pure SDK win. Relying on compiler warning suppression masks to cover up incorrect flags on compile commands is a bad practice that actively harms the local developer experience for anyone editing `third_party` C code.
*   **Verdict**: **Strong Accept**. We should split C-only and C++-only compiler options properly in `build/config/compiler/BUILD.gn` using `cflags_c` and `cflags_cc`.

---

### [Issue 00002: runtime/lib/ has no GN target — implicit cross-package coupling](issue_00002_runtime_lib_no_gn_target.md)

*   **The Bazel-Independent Problem**: `runtime/lib/` contains the implementations of VM intrinsic/native functions, but lacks a `BUILD.gn`. Sibling packages pull its files in by directly sourcing `.cc` lists (`runtime/vm/lib_sources.gni`), and headers are resolved implicitly via the root-level `dart_public_config`'s broad include directories. The directory boundary is undocumented and opaque to tools like `gn refs`.
*   **Skeptical Critique**: Sourcing files across packages via `.gni` files is common in monolithic builds (like the VM), but it does hide the structure. However, we must be realistic: the files in `runtime/lib/` are not a general-purpose library; they are tightly coupled with the VM. Setting up a separate `source_set("lib")` in `runtime/lib/BUILD.gn` that `runtime/vm` depends on is a clean structural improvement, but we shouldn't over-engineer it or try to make it a separate library unit.
*   **Verdict**: **Accept**. Create a `runtime/lib/BUILD.gn` defining a private `source_set` to make the dependency graph explicit and greppable.

---

### [Issue 00003: tools/make_version.py is not hermetic](issue_00003_make_version_py_hermeticity.md)

*   **The Bazel-Independent Problem**: The script that produces `version.cc` relies on relative path lookups from `__file__` to locate `tools/VERSION` and `runtime/vm/...` files. It also implicitly invokes the host's `git` binary from the workspace. Crucially, the list of files used to generate the snapshot compatibility hash is hardcoded in Python (`VM_SNAPSHOT_FILES`) and duplicated manually in GN's `inputs = [...]` block. This duplication has caused build/CI drift issues before.
*   **Skeptical Critique**: Non-hermetic build scripts are a constant source of pain for downstream integrations, sandboxed package builders (like Debian/Fedora packagers), and developers attempting to build from source tarballs. Furthermore, the duplication of the snapshot files list between GN and Python is fragile and error-prone.
*   **Verdict**: **Strong Accept (High Priority)**. Refactor the script to take explicit arguments (`--dart-dir`, `--snapshot-files`, `--git-hash`) while retaining the old behaviors as convenient defaults. This is a significant robustness upgrade for all build consumers.

---

### [Issue 00004: Set PERFETTO_DISABLE_LOG for Dart's protozero-only perfetto use](issue_00004_perfetto_disable_log.md)

*   **The Bazel-Independent Problem**: Dart uses Perfetto's `protozero` serialization engine but excludes its logging/tracing base stack. However, we compile without `PERFETTO_DISABLE_LOG`. The compiler references a `perfetto::base::LogMessage` symbol that doesn't exist in our binary, but the static linker happens to tolerate the missing symbol because the code path is dead.
*   **Skeptical Critique**: Relying on the static linker to silently ignore unresolved symbols on untreaded code paths is a fragile compile hazard. A compiler upgrade, a linker behavior change, or an optimization flag roll could easily turn this into a blocking linker error. 
*   **Verdict**: **Strong Accept**. Define `PERFETTO_DISABLE_LOG` in `libprotozero_config`. It eliminates dead code, shrinks the binary size slightly, and implements an upstream-supported flag contract rather than relying on linker leniency.

---

### [Issue 00005: Vendored third_party BUILD files conflict with sibling builds](issue_00005_vendored_third_party_build_files.md)

*   **The Bazel-Independent Problem**: rolled third_party trees (like `perfetto` and `boringssl`) contain upstream `BUILD` and `WORKSPACE` files that Dart's GN build ignores but are committed to the tree anyway. They pollute grep searches and confuse local tools/LSPs that think they denote nested package borders.
*   **Skeptical Critique**: This is mostly cosmetic for the GN build. However, the fix is trivial: update our roll/import scripts (e.g., `copy_tree.py`) to skip committing unused build configurations. It prevents code clutter and developer friction when navigating the codebase.
*   **Verdict**: **Accept**. Update our copy/roll scripts to exclude upstream build files at copy time. Do not spend substantial custom engineering time on it.

---

### [Issue 00006: ICU data headers are excluded by upstream :headers but used by Dart](issue_00006_icu_data_headers_inconsistency.md)

*   **The Bazel-Independent Problem**: Upstream ICU excludes generated data headers (`norm2_nfc_data.h`, etc.) from its public headers list because it expects they will be dynamically regenerated. Dart uses checked-in copies of these data tables. To resolve this, Dart compiles ICU files with `-Ithird_party/icu/source/common`, bypassing the build system's dependency tracker. Because GN does not track these files as header dependencies, updates to ICU data files during rolls may fail to trigger incremental rebuilds of dependent object files, risking silent runtime skews.
*   **Skeptical Critique**: Hidden header dependencies are the bane of correct incremental builds. If an engineer updates a data table, the build system must know to recompile the affected translation units. Relying on raw filesystem searches via `-I` is a build-system bypass.
*   **Verdict**: **Strong Accept (Option B)**. We should explicitly declare that Dart uses checked-in data tables, comment the divergence in `third_party/icu/BUILD.gn`, and define a GN target that includes these headers explicitly so that incremental builds are robust.

---

### [Issue 00007: No GN target demarcates Dart's public VM embedding C API](issue_00007_runtime_include_public_api_target.md)

*   **The Bazel-Independent Problem**: The public C API headers (`dart_api.h`, etc.) are only listed under a `copy_headers` rule in GN. There is no compile-time target representing this critical public contract. Dependent targets simply pull from the directory via implicit `-Iruntime/include` configs. Private/internal headers also live in the same directory, muddying the boundary.
*   **Skeptical Critique**: The VM's public C embedding API is an ABI-sensitive boundary. Having no build-level target means changes to these public headers trigger no build-graph signal, and we cannot easily restrict internal code from reaching private headers placed in the same directory.
*   **Verdict**: **Strong Accept**. Create a public `source_set("public_api_headers")` target that enumerates the official public C headers. This provides a clear boundary, allows ABI stability tooling to hook into a specific build node, and documents the exact API surface.

---

### [Issue 00008: runtime/bin/dfe.cc uses ifdef-toggled symbol definitions](issue_00008_dfe_ifdef_toggled_symbol_definition.md)

*   **The Bazel-Independent Problem**: `dfe.cc` contains an `extern "C"` block that toggles between *declaring* a symbol (`const uint8_t kKernelServiceDill[]`) or *defining* a nullptr pointer stub (`const uint8_t* kKernelServiceDill = nullptr`) depending on `EXCLUDE_CFE_AND_KERNEL_PLATFORM`. The two branches use structurally incompatible types, and the compiler is forced to rely on linker-level symbol matching hacks.
*   **Skeptical Critique**: Swapping between a declaration and a definition under `#ifdef` blocks using incompatible types is extremely fragile code. It violates standard C++ type boundaries and confuses compiler analyzers. The correct way to toggle features is to swap the *implementation file* at the build-system level, rather than hacking the source code with inconsistent types.
*   **Verdict**: **Strong Accept**. Split the stubs out into `dfe_empty_kernel_stubs.cc` and `dfe_real_kernel_stubs.cc`, and let GN choose which file to compile based on the build flags. Keep the type signatures consistent.

---

### [Issue 00009: icudtl_linkable uses path_exists() to dual-source between Dart SDK and Flutter engine layouts](issue_00009_icudtl_path_exists_dual_layout.md)

*   **The Bazel-Independent Problem**: `icudtl_linkable` uses GN's built-in `path_exists()` to probe the user's disk at gen-time and silently switch compile targets depending on whether it finds a standalone Dart checkout or a Flutter engine checkout structure. 
*   **Skeptical Critique**: Filesystem-sniffing build rules are an anti-pattern. They make build outputs dependent on untracked local disk state (e.g., if an engineer happens to have a stale directory lying around from a previous checkout, the build system will silently pick it up). Build configurations must be explicit, deterministic, and declarative.
*   **Verdict**: **Strong Accept (High Priority)**. Replace `path_exists()` with an explicit GN argument (`declare_args`) or an explicit conditional import. The build should error out if files are missing rather than guessing layouts based on local files.
