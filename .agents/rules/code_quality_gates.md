---
trigger: always_on
description: Enforce formatting and static analysis cleanliness before committing Dart files
---

# 🧼 DART CODE QUALITY GATES

To maintain high code quality standards and keep the Dart SDK codebase clean, you MUST satisfy the following quality gates before executing any git commit containing Dart changes:

1. **Formatting Gate (`dart format`):**
   - Every modified or newly created `.dart` file MUST be perfectly formatted using `dart format`.
   - Run `dart format <file>` or check formatting before preparing the commit. Do not commit unformatted code.

2. **Static Analysis Gate (`dart analyze`):**
   - Every modified or newly created `.dart` file MUST be completely clean of any analyzer errors, warnings, or lints.
   - Run `dart analyze <file_or_directory>` on your changes. You are **PROHIBITED** from committing any code that introduces analysis issues.
   - If there are pre-existing analysis warnings in adjacent files that your change did not create, you are not required to fix them (adhere to Surgical Changes rule), but your own changed lines must be 100% clean.

3. **Python Test Wrapper Gate (`test_wrapper_test.py`):**
   - If `tools/test.py` is modified, you MUST run `python3 tools/test_wrapper_test.py` and verify it passes 100% green before committing.

4. **Python Formatting Gate (`yapf`):**
   - Every modified or newly created `.py` file MUST be perfectly formatted using `yapf` in accordance with the `.style.yapf` configuration.
   - Run the formatter in-place using:
     `PATH=$PATH:~/github/depot_tools ~/github/depot_tools/yapf -i <file>`
   - Verify that there are no formatting diffs before committing by running:
     `PATH=$PATH:~/github/depot_tools ~/github/depot_tools/yapf -d <file>`

5. **Bazel Formatting and Linting Gate (`buildifier`):**
   - Every modified or newly created Bazel file (`BUILD.bazel`, `MODULE.bazel`, `.bzl` files, excluding `gen_targets.bzl`) MUST be perfectly formatted and free of lint warnings using `buildifier`.
   - Run `buildifier --mode=check --lint=warn --warnings=all <files>` to verify.
   - You can run `buildifier --lint=fix --warnings=all <files>` to automatically fix formatting and some warnings.



