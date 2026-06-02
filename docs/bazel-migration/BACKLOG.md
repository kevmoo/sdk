# Dart SDK Bazel Migration: Agent Backlog & Coordination Board

This is the single source of truth for the remaining migration work stream. It is designed to be read, claimed, and updated by autonomous AI agents during long-runtime sessions, and reviewed by human researchers.

> 🚨 **AGENT PROTOCOL (Mandatory)**:
> 1. **Scan**: Read this file FIRST on arrival. Check for open `[PENDING]` tasks.
> 2. **Claim**: Before editing, post a "Soft Claim" by changing the task status to `[IN_PROGRESS]`, adding your Agent ID (e.g., `[jetski-3]`), and committing this file first to lock the task.
> 3. **Verify**: Run the exact `Verification Command` in the task block.
> 4. **Update**: Once verified green, update the task status to `[COMPLETED]`, check the success criteria boxes, append the git commit hash, and update the session log in `STATUS.md`.
> 5. **Handoff**: Release your claim. Never edit a task claimed by another agent.

---

## 📊 Global State

- **Active Agent**: `[none]`
- **Global Lock**: `[unlocked]`
- **Overall Progress**: 0/8 Tasks (0%)

---

## 📋 Active Backlog

### 🎯 [TASK_001] Dynamic Package Dependency Mapping
- **Status**: `[IN_PROGRESS]`
- **Prerequisites**: None
- **Owner**: `[jetski]`
- **Commit**: `[none]`
- **Target Files**:
  - `tools/bazel/dart/generate_test_targets.dart`
- **Description**:
  Implement dynamic package dependency mapping inside the test target generator. For any test target generated under `pkg/<package_name>`, the generator must dynamically inject `@//:dart_pkg_<package_name>` into its Bazel `data` dependencies. This ensures package library files and their complete transitive closures are staged inside the hermetic sandbox, resolving missing imports during JIT VM test runs and establishing perfect cache invalidation boundaries.
- **Verification Command**:
  ```bash
  python3 tools/test.py --bazel pkg/path
  ```
- **Success Criteria**:
  - [ ] `generate_test_targets.dart` dynamically adds `@//:dart_pkg_<pkgName>` to test targets generated for `pkg/` subdirectories.
  - [ ] Hardcoded package mappings in `dataDeps` are minimized to baseline frameworks.
  - [ ] Package tests execute cleanly JIT inside the hermetic sandbox and changes to `pkg/path/lib/path.dart` correctly invalidate the test cache.

---

### 🎯 [TASK_002] Pre-Computed Package Import Mapping (Fine-Grained Opt-in)
- **Status**: `[PENDING]`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - `tools/bazel/dart/generate_test_targets.dart`
  - `tools/bazel/dart/gen_test_imports.dart` (to be created)
- **Description**:
  Provide a high-performance developer tool to generate a static dependency map `test_imports.json` for huge packages like `pkg/analyzer`. Upgraded `generate_test_targets.dart` must consume this pre-computed JSON file to output individual fine-grained test targets with surgically precise file-level `data` dependencies, unlocking ultra-granular Bazel caching within packages without scanning overhead at Bazel runtime.
- **Verification Command**:
  ```bash
  python3 tools/test.py --bazel pkg/path/test/some_test.dart
  ```
- **Success Criteria**:
  - [ ] A high-performance CLI tool `gen_test_imports.dart` is created to recursively parse imports and output `test_imports.json`.
  - [ ] `generate_test_targets.dart` detects `test_imports.json` in package directories and dynamically outputs individual `sh_test` targets for each test case.
  - [ ] Modifying a single library file under `pkg/analyzer/lib/` only invalidates the specific, transitively importing JIT VM test targets inside the Bazel sandbox.

---

### 🎯 [TASK_003] Windows MSVC Toolchain Port
- **Status**: `[PENDING]`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - `build/toolchain/win/BUILD.bazel`
  - `build/toolchain/win/cc_toolchain_config.bzl`
- **Description**: 
  Port MSVC toolchain discovery from `build/vs_toolchain.py` to a dynamic Bazel Starlark repository rule. The rule must auto-detect MSVC installations on the Windows host and generate appropriate `cc_toolchain` definitions dynamically.
- **Verification Command**:
  ```bash
  /usr/local/google/home/kevmoo/bin/bazel build --platforms=//build/platforms:windows_x64 //runtime/bin:dartvm
  ```
- **Success Criteria**:
  - [ ] MSVC installation path is dynamically detected on Windows hosts.
  - [ ] `//runtime/bin:dartvm` compiles and links cleanly under Windows.
  - [ ] Context & Hints:
  See the select-based architecture in `build/toolchain/linux/cc_toolchain_config.bzl`. GN equivalent is `//build/config/win:sdk`.

---

### 🎯 [TASK_004] Android & Fuchsia Target Platform Registration
- **Status**: `[PENDING]`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - `build/platforms/BUILD.bazel`
  - `MODULE.bazel`
- **Description**:
  Register full target platforms for Android and Fuchsia. Map Android NDK references via `android_ndk_repository` and Fuchsia toolchains via Google's `rules_fuchsia`.
- **Verification Command**:
  ```bash
  /usr/local/google/home/kevmoo/bin/bazel build --platforms=//build/platforms:android_arm64 //runtime/bin:dart_aotruntime
  ```
- **Success Criteria**:
  - [ ] Android NDK toolchain resolves and compiles the AOT runtime.
  - [ ] Fuchsia target platforms compile and package cleanly.
- **Context & Hints**:
  We already compile standalone VM arm64 successfully. This task extends that to official Android/Fuchsia platform constraints.

---

### 🎯 [TASK_005] Dynamic Browser Testing Downloads
- **Status**: `[PENDING]`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - `tools/bazel/dart/test_rules.bzl`
  - `MODULE.bazel`
- **Description**:
  WASM and Web tests are currently limited to the D8 runtime. Integrate dynamic browser downloads (Chrome, Firefox, ChromeDriver) using Bzlmod `http_archive` rules and stage them dynamically in test runfiles to enable browser-based web testing under the sandbox.
- **Verification Command**:
  ```bash
  python3 tools/test.py --bazel -n dart2wasm-chrome corelib/list_test
  ```
- **Success Criteria**:
  - [ ] Chrome and ChromeDriver archives are downloaded dynamically via Bzlmod on first run.
  - [ ] Browser-based WASM/Web tests execute and pass inside the sandbox.
- **Context & Hints**:
  See browser downloader configs in GN's `third_party/browsers/`.

---

### 🎯 [TASK_006] RBE (Remote Build Execution) Verification
- **Status**: `[PENDING]`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - `build/toolchain/linux/cc_toolchain_config.bzl`
  - `.bazelrc`
- **Description**:
  Verify remote execution (RBE) against Google's `flutter-rbe-prod` instance in CI. Ensure toolchain configurations correctly serialize and do not leak host-absolute paths to the remote worker.
- **Verification Command**:
  ```bash
  /usr/local/google/home/kevmoo/bin/bazel build --config=rbe //sdk:create_sdk
  ```
- **Success Criteria**:
  - [ ] Entire SDK compiles cleanly on remote RBE workers.
  - [ ] Cache hit rate is high and no local toolchain leaks are observed.

---

### 🎯 [TASK_007] Sanitizer Suite Verification
- **Status**: `[PENDING]`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - `build/toolchain/linux/cc_toolchain_config.bzl`
- **Description**:
  Activate and verify the full sanitizer test suites (`asan`, `msan`, `tsan`) at scale in Bazel. Ensure compiler option selections for sanitizers map cleanly to execution environments.
- **Verification Command**:
  ```bash
  python3 tools/test.py --bazel -n dart-asan corelib/list_test
  ```
- **Success Criteria**:
  - [ ] Sanitizer configurations compile without linker errors.
  - [ ] Sanitizer tests execute and report diagnostic outputs correctly.

---

### 🎯 [TASK_008] Minor SDK Assembly Stubs Resolution
- **Status**: `[PENDING]`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - `sdk/BUILD.bazel`
- **Description**:
  Resolve the remaining minor packaging stubs in the SDK assembly:
  1. Implement `dart2bytecode` AOT snapshot compilation and staging.
  2. Implement dynamic compilation of DevTools from source under Bazel instead of copying prebuilt assets via `copy_prebuilt_devtools` (if `build_devtools_from_sources` is enabled).
- **Verification Command**:
  ```bash
  /usr/local/google/home/kevmoo/bin/bazel build //sdk:create_sdk
  ```
- **Success Criteria**:
  - [ ] `dart2bytecode` snapshot is built and staged successfully under `dart-sdk/bin/snapshots/`.
  - [ ] DevTools builds hermetically from source when required.
