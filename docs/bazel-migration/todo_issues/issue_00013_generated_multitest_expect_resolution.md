# Issue 00013: Generated multitests fail `package:expect` resolution under the Bazel test track (and silently false-pass the numbered variants)

> [!NOTE]
> **Discovered during**: Bazel migration dynamic test track — full-suite run of `bazel test @dart_tests_wasm_d8//...` (237 targets).
> **Affects**: every *multitest-generated* variant emitted to `out/ReleaseX64/generated_tests/**`. Surfaced concretely on `tests/language/class/cycle_test`, `tests/language/class/literal_test`, and `tests/language/class/literal_static_test`.
> **Scope honesty**: this is primarily a **Bazel-test-track infrastructure** defect, not a core-SDK defect. It is tracked here for migration continuity because of the dangerous *masking* side-effect described below (green ≠ correct). The canonical GN/`tools/test.py` flow resolves `package:expect` for generated multitests correctly; only the Bazel track's reimplementation does not.

## Problem

The multitest framework expands a source multitest (e.g. `class/literal_test.dart`) into per-case `.dart` files written under `out/ReleaseX64/generated_tests/...` (e.g. `literal_test_none.dart`, `literal_test_01.dart`). Each generated file carries the source's `import "package:expect/expect.dart";`.

Under the Bazel test track the dart2wasm compile of these *generated* files is **not given a package configuration that resolves `expect`**, so every generated variant fails to compile:

```
Error: Couldn't resolve the package 'expect' in 'package:expect/expect.dart'.
…/generated_tests/language/class/cycle_test_none.dart:9:8: Error: Not found: 'package:expect/expect.dart'
import "package:expect/expect.dart";
       ^
…: Error: Undefined name 'Expect'.
  Expect.isTrue(new Foo() is Foo);
  ^^^^^^
[Command 1 exited with code 254]
Resolved actual test outcome: CompileTimeError
```

In-tree (non-generated) tests are unaffected — they resolve `package:expect` from the source tree's package config, which is why **233 / 237** targets pass. `package:expect` exists and is healthy at `pkg/expect/lib/expect.dart`; the defect is purely that the generated-test compile is invoked without a packages file that includes it.

### The dangerous part: silent false-passes (masking)

Only the `_none` multitest variants — whose expected outcome is `Pass` — surface this as a FAILURE. The **numbered** variants whose expected outcome is `CompileTimeError` are scored **SUCCESS for the wrong reason**: the unresolved-`expect` compile error happens to match their expectation.

Empirically verified on a "passing" target:

```
$ # testlog for language_class_cycle_test_01  (reported: PASSED)
Error: Couldn't resolve the package 'expect' in 'package:expect/expect.dart'.
Actual Outcome:    CompileTimeError
Expected Outcomes: [CompileTimeError]
RESULT: SUCCESS (Outcome matches expectations)
```

So the package-resolution break corrupts **every** generated multitest variant; the suite only *reports* the `_none` ones. The numbered "passes" are false positives that mask the very same bug. This means a green multitest result in the Bazel track currently does **not** imply the case was actually exercised — it may have died at `import` and matched a `CompileTimeError` expectation accidentally.

## Why this is an improvement on its own

Test-result *integrity* is the property at stake: a CI signal that reports SUCCESS while the program never compiled past its first `import` is worse than a plain failure, because it hides regressions. Even outside Bazel, the underlying lesson — **outcome matching should distinguish a `CompileTimeError` produced for the expected reason from one produced for an unrelated reason (e.g. a missing package)** — is a general test-runner robustness improvement. A compile error in the test *harness's* resolution should never be allowed to satisfy a `CompileTimeError` expectation in the test *body*.

## How it makes Bazel (and any other non-GN build) easier

Fixing the generated-test package resolution unblocks the full language multitest set under the hermetic Bazel sandbox and restores trust in the track's green/red signal — a prerequisite for using `bazel test @dart_tests_*//...` as a gating check during the migration.

## Recommendations

1. **Supply a package config to the generated-test compile.** When the Bazel track compiles a file under `generated_tests/`, pass the same `--packages`/`.dart_tool/package_config.json` (resolving at least `expect` plus the test's own dependencies) that `tools/test.py` supplies in the canonical flow.
2. **Harden outcome matching against harness-origin compile errors.** Treat "could not resolve a package" (and similar harness/environment compile failures) as an infrastructure error distinct from an expected `CompileTimeError`, so a numbered multitest variant cannot false-pass on a resolution failure.

## Affected code

* The dynamic test pipeline: `pkg/test_runner/bin/run_single_test.dart`, `tools/bazel/dart/test_rules.bzl`, and the `dynamic_test_repository` / `dart_tests_extension` Bzlmod machinery (sessions 42–45) — wherever the generated-test compile command is assembled without a packages file.
* `pkg/expect/lib/expect.dart` (the package that fails to resolve; itself healthy).

## Notes

Discovered 2026-06-01 while running `bazel test @dart_tests_wasm_d8//...` against a freshly built `//sdk:create_sdk`. Of 237 targets, 4 reported FAILURE; 3 of those (`cycle_test_none`, `literal_test_none`, `literal_static_test_none`) are this issue. The 4th is unrelated — see `issue_00014`. The masking was confirmed by inspecting the testlog of `language_class_cycle_test_01`, which reported `RESULT: SUCCESS` despite the identical `Couldn't resolve the package 'expect'` compile error.
