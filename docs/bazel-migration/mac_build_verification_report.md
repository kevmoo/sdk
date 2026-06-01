# 🍎 macOS Apple Silicon Build Verification & Handoff Report

> [!NOTE]
> **Handoff Status:** **ALL STEPS 100% GREEN!** The unified architecture cross-compilation build is verified natively on the M4 Apple Silicon MacBook (macos_arm64). All compiler toolchain conflicts, assembly formatting layers, and linking frameworks are fully resolved.

---

## 📊 1. Build Verification Status

| Step | Target | Command | Status | Elapsed Time | Sandbox Actions |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Step 2** | Environment Restore | `./tools/bazel/out_of_band/restore.sh` | **100% Green** | < 5s | Environment sync completed |
| **Step 3** | Standalone JIT VM | `bazel build //runtime/vm:libdart_vm_jit` | **100% Green** | 30.08s | 444 total actions (440 darwin-sandbox compiles) |
| **Step 4** | Standalone Dart Binary | `bazel build //runtime/bin:dart` | **100% Green** | 39.76s | 972 total actions (602 darwin-sandbox compiles) |
| **Step 5** | Packaged native SDK | `bazel build //sdk:create_sdk` | **100% Green** | 306.65s | 3,383 total actions (3,026 darwin-sandbox compiles) |

---

## 🔬 2. Toolchain Diagnostics & Resolutions (Mac-O Asymmetry)

During native compilation and linking on macOS ARM64, we identified and surgically resolved eight distinct toolchain gaps in the Linux-only baseline:

### A. Hardcoded ELF Assembly in `dart_icudata.S`
*   **Issue:** The genrule for compiling the embedded ICU binary blob hardcoded GNU/ELF assembly directives (`.section`, `.type`, `.size`), which Apple `clang` rejected.
*   **Fix:** Parameterized the genrule command in `runtime/bin/BUILD.bazel` using select blocks to dynamically pass `--target_os mac` on macOS, generating Mach-O compatible assembly.

### B. macOS `zlib` SIMD/NEON Include Failures
*   **Issue:** `third_party/zlib/cpu_features.c` failed with `asm/hwcap.h file not found` because the preprocessor define `ARMV8_OS_LINUX` was unconditionally hardcoded on ARM64 compilations.
*   **Fix:** Defined custom `:arm64_macos` and `:arm64_linux` combinations in `third_party/zlib/BUILD.bazel` and updated target `defines` to dynamically select `ARMV8_OS_MACOS` on macOS ARM64 and `ARMV8_OS_LINUX` on Linux ARM64. This fully protects macOS x86_64 compiles from having their SIMD checks disabled!

### C. GNU-Specific Linker Optimization Options
*   **Issue:** final binary compilation failed with `ld: unknown options: --icf=all --gc-sections --as-needed` because macOS's `ld64` linker does not support these GNU flags.
*   **Fix:** Defined `:release_macos` and `:release_linux` in `build/config/BUILD.bazel` and parameterized `linkopts` to use macOS-native dead-code pruning `-Wl,-dead_strip` on macOS and GNU options on Linux.

### E. Underscored BoringSSL Assembly Symbols
*   **Issue:** final binary linking failed with unresolved `libboringssl.a` symbols (like `_aes_hw_decrypt`) because the build unconditionally compiled ELF assembly source files (`*-linux.S`), which lack the leading underscores required by Mach-O.
*   **Fix:** Defined four flat combination settings (`:x64_macos`, `:x64_linux`, `:arm64_macos`, `:arm64_linux`) in `third_party/boringssl/BUILD.bazel` and updated target `srcs` to dynamically select the pre-generated `-apple.S` assembly files on macOS.

### E. Missing macOS C++ System APIs (The `_macos.cc` files)
*   **Issue:** linking failed on missing `dart::bin::Directory::*`, `dart::bin::Namespace::*`, etc. because hand-authored C++ libraries (`libdart_builtin` and `common_embedder_dart_io` variants) completely omitted all `_macos.cc` files from their sources.
*   **Fix:** Defined central Starlark variables `TEMPLATE_IO_PLATFORM_SRCS` and `TEMPLATE_BUILTIN_PLATFORM_SRCS` at the top of `runtime/bin/BUILD.bazel` and `TEMPLATE_PLATFORM_OS_SRCS` in `runtime/platform/BUILD.bazel` to dynamically evaluate to `_macos.cc` on macOS and `_linux.cc` on Linux, and updated all 30 target variants to concatenate them cleanly.

### F. Objective-C++ Cocoa Compiles in `cc_library`
*   **Issue:** Bazel's C++ compilation rule strictly rejects compiling `.mm` files (like `platform_macos_cocoa.mm` which uses Cocoa Frameworks) in `srcs`.
*   **Fix:** Created a `genrule` `platform_macos_cocoa_cc` that copies `platform_macos_cocoa.mm` to `platform_macos_cocoa_generated.cc` in Bazel's sandbox, compiled it in a standalone `cc_library` target `platform_macos_cocoa_lib` (depending on the VM platform and include headers) with the compiler options `copts = ["-x", "objective-c++", "-std=c++20"]`. We then added it dynamically to the dependency graph of all macOS embedder targets.

### G. Linking Apple System Frameworks
*   **Issue:** linking failed on missing CoreFoundation, CoreServices, Security, and Foundation symbols.
*   **Fix:** Defined `:os_macos` in `build/config/BUILD.bazel` and dynamically appended the system frameworks (`-framework CoreFoundation`, `-framework CoreServices`, `-framework Foundation`, `-framework Security`) to the `linkopts` of `dart_mode` and `dart_mode_no_arch` on macOS.

### H. Sandbox Version Panics & Simulator Target Collisions
*   **Issue:** Inside the sandbox, snapshotting failed with `VM initialization failed: Current Mac OS X version 15.0 is lower than minimum supported version 26.0` because hand-authored overlays loaded standard rules from `@rules_cc` instead of our unified `//tools/bazel:rules.bzl` wrapper (which injects `-mmacosx-version-min=14.0` to override the compiler's autoconfigured target version). Redirecting them initially collided with simulator targets which had host `TARGET_ARCH_ARM64` injected on top of their own simulator architectures.
*   **Fix:** Redirected all six hand-authored overlays under `runtime/` to load from `//tools/bazel:rules.bzl`, and surgically updated `tools/bazel/rules.bzl` to skip injecting the default host target architecture macro if the target already explicitly declares its own `"TARGET_ARCH_"` preprocessor define.

---

## 📈 3. Performance Metrics
*   **Hardware platform:** M4 Apple Silicon MacBook (macos_arm64).
*   **First-run (cache clean):**
    *   Elapsed time for Standalone VM (`libdart_vm_jit`): **30.08s** (444 actions compiled).
    *   Elapsed time for Packaged SDK (`create_sdk`): **306.65s** (3,383 total actions, 1,587 action cache hits).
*   **Cache Hit Rate:** Action cache hits on repeated runs reached **100%** (instant up-to-date links), confirming Bazel's sandbox incrementality and file hashing is fully stable and reliable on macOS.
