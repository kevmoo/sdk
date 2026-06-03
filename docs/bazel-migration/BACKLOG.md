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
- **Overall Progress**: 8/14 Tasks (57.1%)

---

## 📋 Active Backlog

### 🎯 [TASK_001] Dynamic Package Dependency Mapping
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[jetski]`
- **Commit**: `[4bbcd110701]`
- **Target Files**:
  - `tools/bazel/dart/generate_test_targets.dart`
- **Description**:
  Implement dynamic package dependency mapping inside the test target generator. For any test target generated under `pkg/<package_name>`, the generator must dynamically inject `@//:dart_pkg_<package_name>` into its Bazel `data` dependencies. This ensures package library files and their complete transitive closures are staged inside the hermetic sandbox, resolving missing imports during JIT VM test runs and establishing perfect cache invalidation boundaries.
- **Verification Command**:
  ```bash
  python3 tools/test.py --bazel pkg/smith
  ```
- **Success Criteria**:
  - [x] `generate_test_targets.dart` dynamically adds `@//:dart_pkg_<pkgName>` to test targets generated for `pkg/` subdirectories.
  - [x] Hardcoded package mappings in `dataDeps` are minimized to baseline frameworks.
  - [x] Package tests execute cleanly JIT inside the hermetic sandbox and changes to `pkg/smith/lib/` correctly invalidate the test cache.

---

### 🎯 [TASK_002] Pre-Computed Package Import Mapping (Fine-Grained Opt-in)
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[jetski]`
- **Commit**: `[dynamic]`
- **Target Files**:
  - `tools/bazel/dart/generate_test_targets.dart`
  - `tools/bazel/dart/gen_test_imports.dart`
- **Description**:
  Provide a high-performance developer tool to generate a static dependency map `test_imports.json` for huge packages like `pkg/analyzer`. Upgraded `generate_test_targets.dart` must consume this pre-computed JSON file to output individual fine-grained test targets with surgically precise file-level `data` dependencies, unlocking ultra-granular Bazel caching within packages without scanning overhead at Bazel runtime.
- **Verification Command**:
  ```bash
  python3 tools/test.py --bazel pkg/analyzer/test/dart/analysis/analysis_context_test.dart
  ```
- **Success Criteria**:
  - [x] A high-performance CLI tool `gen_test_imports.dart` is created to recursively parse imports and output `test_imports.json`.
  - [x] `generate_test_targets.dart` detects `test_imports.json` in package directories and dynamically outputs individual `sh_test` targets for each test case.
  - [x] Modifying a single library file under `pkg/analyzer/lib/` only invalidates the specific, transitively importing JIT VM test targets inside the Bazel sandbox.

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

---

### 🎯 [TASK_009] Relocate and Migrate Worktree Symlinker to Dart
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[jetski]`
- **Commit**: `[local]`
- **Target Files**:
  - `tools/bazel/dart/setup_worktree_links.sh`
  - `tools/setup_worktree_links.dart`
- **Description**:
  Relocate the git worktree helper script `setup_worktree_links.sh` from `tools/bazel/dart/` to the root of the `tools/` directory to make it a prominent, standard tool, and migrate its bash scripting logic to a robust, cross-platform Dart CLI tool (`tools/setup_worktree_links.dart`). The new Dart tool should recursively resolve the parent git checkout path using git worktree metadata, verify directories, and safely establish symlinks for untracked gclient dependencies (`third_party/`, `buildtools/`, prebuilt SDKs) across all supported platforms (Linux, macOS, and Windows).
- **Verification Command**:
  ```bash
  dart tools/setup_worktree_links.dart
  ```
- **Success Criteria**:
  - [x] **Task 1.1 (Port Symlinker):** Author the cross-platform Dart worktree symlinker at `tools/setup_worktree_links.dart`.
  - [x] **Task 1.2 (Excise Shell Script):** Delete the legacy shell script `tools/bazel/dart/setup_worktree_links.sh` completely.
  - [x] It successfully resolves parent git checkouts and establishes symlinks under secondary git worktrees.
  - [x] It handles file existences, skips tracked configurations safely, and works cleanly on Linux, macOS, and Windows.

---

### 🎯 [TASK_010] Non-Flattened Direct Import Mapping for Test Caching
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[jetski]`
- **Commit**: `[304f78ec535]`
- **Target Files**:
  - `tools/bazel/dart/generate_test_targets.dart`
  - `tools/bazel/dart/gen_test_imports.dart`
- **Description**:
  Refactor `test_imports.json` from storing fully-flattened transitive dependency lists to storing a minimal, non-flattened graph of **direct local imports/exports** for each file in the package (tests and libs). Upgrade `generate_test_targets.dart` to load this direct import graph and dynamically compute the transitive closure for each test using a memoized, cycle-safe Depth-First Search (DFS) traversal at generation time. This shrinks the JSON database sizes by ~95% (from 3.4MB to <150KB) and keeps Git history clean by ensuring changes to library imports only touch a single line in the JSON file.
- **Verification Command**:
  ```bash
  python3 tools/test.py --bazel pkg/analyzer/test/dart/analysis/analysis_context_test.dart
  ```
- **Success Criteria**:
  - [x] `gen_test_imports.dart` is updated to only write out direct local imports for each file in `test_imports.json`, resulting in a vastly smaller JSON size.
  - [x] `generate_test_targets.dart` successfully implements a cycle-safe DFS with memoization to resolve closures in under 50ms.
  - [x] Running tests via `tools/test.py --bazel` yields identical dynamic sandboxed targets and passes completely green.

---

### 🎯 [TASK_011] Repo-Local Upstream SDK Merge Flow Skill
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[jetski]`
- **Commit**: `[648fea99a8d]`
- **Target Files**:
  - `.agents/skills/merge_main_to_bazel.md`
- **Description**:
  Design and document a dedicated repo-local skill for the synchronization and merge of the local `bazel` branch with the upstream SDK `origin/main`. Document the fetch, dry-run merge, out-of-band restore flow, visibility fixes for prebuilts, and PATH-aware git commit hook handling to allow future agents to handle merges cleanly.
- **Verification Command**:
  ```bash
  /usr/local/google/home/kevmoo/bin/bazel build //runtime/bin:dartvm
  ```
- **Success Criteria**:
  - [x] A dedicated, repo-local skill file `.agents/skills/merge_main_to_bazel.md` is authored to document the merge sequence, conflict resolution, restore workflow, and pre-commit formatting.
  - [x] The upstream branch `origin/main` is successfully merged into `bazel` via a merge commit and verified buildable.

---

### 🎯 [TASK_012] Coarse-Grained Test Suite Clustering
- **Status**: `[COMPLETED]`
- **Prerequisites**: `[TASK_010]`
- **Owner**: `[jetski]`
- **Commit**: `[local]`
- **Target Files**:
  - `tools/bazel/dart/generate_test_targets.dart`
- **Description**:
  Optimize Starlark loading times and minimize filesystem overhead by grouping core test suites under unified package directories. For coarse-grained suites (`corelib`, `standalone`, `ffi`, `language`), replace the deeply nested sub-package folder generation (e.g., creating `corelib/list/BUILD.bazel`) with a single package-level `BUILD.bazel` in the suite root (e.g., `@dart_tests//corelib`). Declare all tests belonging to that suite inside this unified package, utilizing explicit target labels to preserve fine-grained file-level cache invalidation boundaries.
- **Verification Command**:
  ```bash
  python3 tools/test.py --bazel corelib/list_test
  ```
- **Success Criteria**:
  - [x] `generate_test_targets.dart` clusters generated targets under root suite directories (`corelib/BUILD.bazel`).
  - [x] Generated `BUILD.bazel` files are reduced by 700+ packages.
  - [x] Modifying a single `.dart` test file still invalidates **only** its specific `sh_test` target.
  - [x] Sandbox JIT execution is completely green.

---

### 🎯 [TASK_013] Unified Test Repository with Configuration Subtargets
- **Status**: `[COMPLETED]`
- **Prerequisites**: `[TASK_012]`
- **Owner**: `[jetski]`
- **Commit**: `[local]`
- **Target Files**:
- `tools/bazel/dart/test_rules.bzl`
- `MODULE.bazel`
- `tools/bazel/dart/generate_test_targets.dart`
- `tools/test.py`
- **Description**:
  Consolidate the 7 redundant external Starlark test repositories into a single unified external repository `@dart_tests` to eliminate sequential Bazel repository fetch runs. Refactor target generation to define configuration subtargets inside the package `BUILD` files using configuration suffixes (e.g., `_vm_debug`, `_wasm_d8`) rather than distinct repository namespaces. Upgrade `generate_test_targets.dart` to run the 7 dry-run sweeps concurrently via Dart's `Future.wait` to complete target discovery under 2 seconds.
- **Verification Command**:
  ```bash
  python3 tools/test.py --bazel -n dart2wasm-linux-d8 corelib/list_test -v
  ```
- **Success Criteria**:
  - [x] `MODULE.bazel` is refactored to define exactly **one** dynamic test repository (`@dart_tests`).
  - [x] `generate_test_targets.dart` parallelizes dry-run sweeps using `Future.wait` and completes target discovery in <2.5 seconds.
  - [x] `test_rules.bzl` defines configuration-suffixed test targets inside the root suite packages.
  - [x] `tools/test.py` routes different configuration runs correctly to their corresponding suffixed targets.
  - [x] All configurations compile and execute green inside the sandboxed repository.

---

### 🎯 [TASK_014] Python Test Wrapper Unit Testing
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[jetski]`
- **Commit**: `[local]`
- **Target Files**:
  - `tools/test_wrapper_test.py`
- **Description**:
  Implement a comprehensive Python unit test suite `tools/test_wrapper_test.py` to verify the target resolution and flag translation logic inside `tools/test.py` (`TestWithBazel` and `ResolveConfig`). The test suite must mock Bazel query executions and test various selector inputs (coarse-grained, fine-grained, broad directory, and completely invalid). It must assert that valid selectors resolve to correct targets without emitting any warning or error outputs, and invalid selectors emit the correct warning message.
- **Verification Command**:
  ```bash
  python3 tools/test_wrapper_test.py
  ```
- **Success Criteria**:
  - [x] `tools/test_wrapper_test.py` is authored utilizing Python's `unittest` standard library.
  - [x] Test cases verify configuration resolutions and flag conversions.
  - [x] Test cases verify that valid selectors resolve to correct targets warning-free.
  - [x] Test cases verify that invalid selectors emit the appropriate target warning.
  - [x] Executing `python3 tools/test_wrapper_test.py` runs and passes completely green.



