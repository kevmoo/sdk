# Issue 00014: dart2wasm does not perform the contravariant callable-class field/getter covariance check

> [!NOTE]
> **Discovered during**: Bazel migration dynamic test track — full-suite run of `bazel test @dart_tests_wasm_d8//...`.
> **Affects**: `tests/language/covariant/callable_class_field_getter_test.dart` (added for issue #53089).
> **Status**: needs an upstream-expectation determination (see Notes) — it is *not* a Bazel-migration regression.

## Problem

The test exercises a soundness check: a `Fields<int>` is viewed through static type `Fields<num>`, then a field/getter whose type uses the class type parameter **contravariantly** (`Callable<void Function(T)>`) is read. Because `void Function(int)` is **not** a subtype of `void Function(num)` (parameters are contravariant), reading that field through the `num` view must trigger a runtime covariance check and throw:

```dart
void testFields(Fields<num> fields, {required bool expectException}) {
  ...
  if (expectException) {
    Expect.throws(() => fields.contravariantUse()); // expected to throw under Fields<int>
    Callable.checkCallCount(0);
  }
}
main() {
  testFields(Fields<int>(), expectException: true);  // <-- this case
  ...
}
```

Under dart2wasm the check **does not fire** — the access returns normally and the test fails:

```
Expect.throws fails: Did not throw
    at module0.Expect.throws (wasm://…)
    at module0.testFields (wasm://…)
    at module0.main (wasm://…)
Actual Outcome:    RuntimeError
Expected Outcomes: [Pass]
```

## Investigation (what was ruled out)

1. **Not a Bazel-track invocation artifact.** Reproduces with the canonical CLI on the freshly built SDK:
   ```
   dart-sdk/bin/dart compile wasm tests/language/covariant/callable_class_field_getter_test.dart -o cov.wasm
   d8 pkg/dart2wasm/bin/run_wasm.js -- cov.mjs cov.wasm   # -> "Did not throw"
   ```
2. **Not an optimization / check-omission setting.** dart2wasm omits implicit type checks only at `optimizationLevel >= 3` (`pkg/dart2wasm/lib/translator.dart:80`), and the translator default is `optimizationLevel = 1` (`translator.dart:53`). The failure persists even when checks are *forced on* and optimization is *forced off*:
   ```
   dartaotruntime dart2wasm_product.snapshot --platform=dart2wasm_platform.dill \
     --no-omit-implicit-checks --optimization-level=0 <test> out.wasm   # still "Did not throw"
   ```
3. **Not introduced by the sync.** The only `pkg/dart2wasm/` change in the 93-commit upstream sync was `f710c4338a8 [dart2wasm] Intrinsify math.min() and math.max()` — unrelated to covariance.
4. **No status-file marking.** The test is not listed in any `tests/**/*.status`, including the dart2wasm-specific `tests/language/language_dart2wasm.status`.
5. **GN cross-check blocked.** The pre-sync GN-built `out/ReleaseX64/dart-sdk` cannot compile the test for comparison, because the sync migrated `package:expect` itself to primary-constructor syntax (`new(this.message) : name = …`) which the older compiler rejects. So a clean regression-vs-pre-existing A/B against the old GN binary was not possible.

The combined evidence (covariance code untouched by the sync, failure independent of check/opt flags) indicates a **pre-existing dart2wasm behavior**, not a migration regression.

## Why this is an improvement on its own

If dart2wasm genuinely fails to emit this contravariant callable-class field/getter check, that is a **soundness gap in a shipping compiler** — exactly the class of bug the test (`#53089`) was written to catch — and worth fixing or explicitly documenting regardless of Bazel. If instead the real dart2wasm bot does not run this test as `Pass`, then the SDK's expectation metadata for the web/wasm configuration is the thing to reconcile. Either way the outcome is a more trustworthy dart2wasm correctness signal.

## How it makes Bazel (and any other non-GN build) easier

The dynamic Bazel test track derives each test's expected outcome from `pkg/test_runner` metadata. Pinning down whether this test is *expected to pass* on `dart2wasm-linux-d8` is what lets the track's green/red match the canonical bot. Today the track reports `Expected:[Pass]` and fails; the canonical bot's true expectation must be confirmed so the two agree.

## Recommendations

1. **Determine the upstream truth.** Confirm whether `dart2wasm-linux-d8` on the real bots runs and passes `callable_class_field_getter_test`. If it passes there but not here, find the compile/runtime delta (platform dill, flags, or test selection) the Bazel track is missing.
2. **If it is a genuine dart2wasm soundness gap:** file/upstream against dart2wasm and mark the test appropriately in `tests/language/language_dart2wasm.status` until fixed.
3. **If it is a test-selection/expectation mismatch:** fix the Bazel track's expectation derivation so it stops asserting `Pass` for a test the canonical config does not.

## Affected code

* `tests/language/covariant/callable_class_field_getter_test.dart` (the failing test).
* `pkg/dart2wasm/lib/translator.dart` (covariance/implicit-check emission; lines ~80, ~1567–1671, ~3285).
* `tests/language/language_dart2wasm.status` (where a marking would live if the gap is confirmed).

## Notes

Discovered 2026-06-01 alongside `issue_00013` during `bazel test @dart_tests_wasm_d8//...` (1 of 4 reported failures; the other 3 are the unrelated generated-multitest package-resolution bug, `issue_00013`). This entry deliberately stops short of declaring a confirmed compiler bug — the open question is item (1) above.
