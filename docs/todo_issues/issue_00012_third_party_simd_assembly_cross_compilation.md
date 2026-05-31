# Issue 00012: GN→Bazel translator hardcodes host-specific (x64) SIMD flags and assembly in third-party dependencies, breaking cross-compilation

## Problem

The GN→Bazel translator (`tools/bazel/translate_gn_desc.py`) generates `BUILD.bazel` files by digesting a GN configuration dump (`desc.json`). Because the translator typically processes a host-centric configuration (such as `ReleaseX64`), it emits third-party build targets with hardcoded host-specific flags and optimizations. 

This hardcoding manifests in two severe issues when trying to cross-compile targeting `linux_arm64`:

1. **Host Compile Flags in copts**: Targets in `third_party/fallback_root_certificates`, `third_party/boringssl`, `third_party/binaryen`, and `third_party/zlib` unconditionally carried host-specific flags like:
   ```starlark
   copts = [
       "-m64",
       "-march=x86-64",
       "-msse2",
       "--target=x86_64-linux-gnu",
   ]
   ```
   When Bazel invoked the cross-compilation toolchain (`aarch64-linux-gnu-clang++`), the hardcoded `--target=x86_64-linux-gnu` flag overrode the toolchain target, forcing the compiler to emit x86_64 ELF objects instead of ARM64. This resulted in linker incompatibility errors:
   ```
   ld.lld: error: bazel-out/k8-fastbuild/bin/third_party/boringssl/libboringssl.a(bcm.o) is incompatible with elf64-littleaarch64
   ```

2. **Static x86_64 Assembly Lists**: BoringSSL's assembly target `boringssl_asm` unconditionally listed all x86_64 assembly sources (`aesni-x86_64-linux.S`, etc.) without architecture filters. During ARM64 cross-compilation, these files preprocessed to empty objects, leading to undefined symbol errors at link time:
   ```
   ld.lld: error: undefined symbol: bn_mul_mont_words
   ld.lld: error: undefined symbol: vpaes_encrypt
   ```

3. **Static Zlib SIMD Targets**: Zlib's `zlib_adler32_simd` and `zlib_crc32_simd` targets unconditionally compiled x86 SSSE3/SSE4.2 optimization code paths and flags (like `-mssse3`, `-mpclmul`), and did not propagate platform macros like `ARMV8_OS_LINUX` transitively to zlib's `cpu_features.c`, causing the compiler to skip providing `cpu_check_features()`, leading to:
   ```
   ld.lld: error: undefined symbol: Cr_z_cpu_check_features
   ```

## Why this is an improvement on its own

Build configurations for foundational third-party packages (like zlib, BoringSSL, binaryen, etc.) should be platform-independent and leverage Bazel's dynamic target resolution. Hardcoding a specific host's instruction set and target triple inside a checked-in or generated BUILD file prevents building for other architectures.

Applying platform-dynamic configurations:
- Eliminates instruction set mismatch compile/link errors under cross-compilation.
- Selects CPU-appropriate SIMD code paths (e.g., NEON/ARMv8 vs SSSE3/SSE4.2) dynamically at build-time based on target configuration constraints.
- Reduces maintenance overhead by avoiding multiple copies of BUILD files for different host architectures.

## How it makes Bazel (and any other non-GN build) easier

By refactoring these targets to use Bazel `select()` lists:
- The main `zlib` and `boringssl` libraries can compile seamlessly for any target platform (x86_64, arm64, etc.) out of the box under the sandbox.
- Cross-compilation of dependent targets like `//runtime/bin:dartvm` compiles cleanly without encountering binary target mismatch link-errors.
- It provides a clean, standard Bazel implementation pattern for vendored third-party libraries in the repository.

## Affected code

- `tools/bazel/translate_gn_desc.py` — needs to be updated to strip host-specific CPU/target flags (`-m64`, `-march=x86-64`, `-msse2`, `--target=x86_64-linux-gnu`) and dynamically parameterize SIMD/assembly sources using Bazel `select()`.
- `third_party/zlib/BUILD.bazel` (Tracked via `tools/bazel/out_of_band/snapshot/third_party/zlib/BUILD.bazel.snap`) — refactored SIMD helper library sources, copts, and defines using selects.
- `third_party/boringssl/BUILD.bazel` — refactored `boringssl_asm` sources using selects to compile AArch64 assembly on arm64, and x64 assembly on x86_64.
- `third_party/fallback_root_certificates/BUILD.bazel` — stripped hardcoded target/arch flags.
- `third_party/binaryen/BUILD.bazel` — stripped hardcoded target/arch flags.

## Notes

Surfaced and fully resolved during the Rock 2 ARM64 cross-compilation phase (Session 31, 2026-05-31). Both `//runtime/bin:dartvm` and all transitive dependency libraries now compile 100% successfully targeting ARM64 Linux, producing a pristine `ELF 64-bit LSB pie executable, ARM aarch64` under the sandbox.
