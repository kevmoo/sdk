# 🍎 macOS Apple Silicon Build Handoff & Verification Protocol

> [!NOTE]
> **Handoff Context:** The Linux developer agent (Bluefin-DX) has successfully unified the cross-compilation build architectures. Standard target compile cflags and defines have been lifted into a central, platform-aware Starlark macro wrapper `//tools/bazel:rules.bzl` which dynamically injects platform-appropriate configurations (`-mmacosx-version-min=14.0` on macOS, `--target=x86_64-linux-gnu` on Linux, etc.) using standard Bazel selects. The entire unified SDK compiles 100% green on Linux.

---

## 🚀 Handoff Instructions for macOS Darwin Agent

Please execute the following step-by-step verification sequence on the M4 Apple Silicon MacBook and report back your findings:

### Step 1: Pull the Joint Branch
Switch to this branch:
```bash
git fetch origin
git checkout kevmoo/bazel-m1-cc-toolchain
```

### Step 2: Align Subrepos
Ensure all subrepos and packages are synced to the current branch DEPS pins:
```bash
gclient sync
```

### Step 3: Run Native Apple Silicon VM Compile
Run a native compile of the standalone JIT VM target:
```bash
bazel build //runtime/vm:libdart_vm_jit
```
*Verify that the wrapper macro dynamically compiles the target for macOS Apple Silicon (ARM64) without SSE compiler flag errors.*

### Step 4: Run Standalone Native Dart Binary Compile
Run a compile of the native standalone dart binary:
```bash
bazel build //runtime/bin:dart
```

### Step 5: Build the Full Native macOS SDK
Run the full native packaging compile for the complete SDK:
```bash
bazel build //sdk:create_sdk
```

---

## 📊 What to Report Back

Once you complete these steps, please send a message back with:
1. **Build Status:** Confirm whether each build step (Step 3, 4, and 5) completed successfully (100% green) or failed.
2. **Compilation Diagnostics:** If any compilation or linking errors occur (specifically around BoringSSL assembly files or zlib SIMD routines), provide the detailed error logs so we can adjust the `select` blocks.
3. **Performance Metrics:** Report the build times and cache hits (e.g., elapsed time, action cache hits) for your local runs.

Let's get this native Apple Silicon SDK build fully verified! 🚀
