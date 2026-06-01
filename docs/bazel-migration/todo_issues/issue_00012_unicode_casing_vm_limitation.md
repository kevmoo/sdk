# Issue 00012: Standalone VM String Casing is Strictly 1-to-1 (lacks ICU casing integration)

> [!NOTE]
> **Discovered during**: Bazel Migration testing suite scaling.
> **Affects**: `tests/corelib/unicode_test.dart` and `tests/corelib/string_case_test.dart` (multitest `/01` for German sharp s `ß`).

## Problem

In the Dart SDK, the core `String.toUpperCase()` specification requires locale-independent Unicode case mapping. Specifically, the lowercase German sharp s (`ß`, U+00DF) must be expanded into the two-character uppercase string `"SS"` (length 1 to length 2).

Under Bazel testing (and indeed, **all standalone VM configurations**), these test assertions fail:
```
Expect.equals(expected: <STRASSE>, actual: <STRA\xDFE>) fails.
Expect.equals(expected: <SS>, actual: <\xDF>) fails.
```

### Detailed Analysis & Investigation

1. **Execution Route Verification:**
   * In `sdk/lib/_internal/vm/lib/string_patch.dart`, `_OneByteString.toUpperCase()` checks for multi-character upper cases (marked as `0x00` in a static lookup table `_UC_TABLE`).
   * For `ß` (`0xDF`), `_UC_TABLE` indeed has `0x00` at index `223`.
   * The Dart code correctly redirects this character by calling `super.toUpperCase()`.
   * `super.toUpperCase()` is marked `external` and routes directly to the native C++ entry point `String_toUpperCase` in `runtime/lib/string.cc`.
   * This in turn delegates to `String::ToUpperCase()` -> `String::Transform()` in `runtime/vm/object.cc`.

2. **The strictly 1-to-1 C++ Transform Model:**
   * In `runtime/vm/object.cc`, `String::Transform()` is strictly designed around a 1-to-1 character mapping. It determines the string type to allocate by looking at the maximum code point after mapping (`dst_max`), but **allocates a string of the exact same length** as the input string:
     ```cpp
     const String& result = String::Handle(OneByteString::New(len, space)); // len is input length!
     NoSafepointScope no_safepoint;
     for (intptr_t i = 0; i < len; ++i) {
       int32_t ch = mapping(str.CharAt(i));
       ASSERT(Utf::IsLatin1(ch));
       *CharAddr(result, i) = ch;
     }
     ```
   * The mapping function used is `CaseMapping::ToUpper()` from `runtime/platform/unicode.h`.
   * In `CaseMapping::Convert()`, the static table `stage2_` is checked. At index `223` (`0xDF`), the value is `0` (indicating no mapping exists). `CaseMapping::ToUpper(0xDF)` therefore returns `0xDF` unchanged.
   * Consequently, `String::Transform` returns the original string `"ß"` unchanged, yielding `STRAßE` (length 6) instead of `STRASSE` (length 7).

3. **Complete Absence of ICU Casing in Core VM:**
   * A codebase-wide search across `runtime/vm/` (excluding `regexp/`) confirms there is **no call or reference** to any ICU casing functions (e.g. `u_toupper`, `u_strToUpper`, `u_tolower`, etc.).
   * The *only* place the VM links and uses ICU is inside the regular expression engine (`irregexp` in `runtime/vm/regexp/`) for case-independent matches and fold-casing parser utilities.
   * As a result, even when ICU is successfully initialized and loaded via `SetupICU()` (from `icudtl.dat`), the core VM string library **literally has no C++ code path to use it**.

4. **GN Build & Official Bootstrap SDK Verification:**
   * The same casing tests were executed on:
     1. The GN-built standalone `dart` binary in `out/ReleaseX64/dart`.
     2. The official beta bootstrap SDK binary in `tools/sdks/dart-sdk/bin/dart` (version `3.13.0-103.1.beta`).
   * **Both runtimes failed in exactly the same way**, returning `\xDF` unchanged instead of `SS`.
   * This proves that the casing failure is **not a Bazel migration regression**, but is instead a long-standing standalone VM core casing model limitation.
   * The tests pass on `dart2js`, `ddc`, and `dart2wasm` web runtimes only because they compile Dart to JavaScript/Wasm and delegate casing to the browser's host JS engine, which natively handles the `ß` -> `SS` conversion.

### The Sandboxing Red Herring

During the early stages of the Bazel migration, missing `icudtl.dat` dependencies in Bazel sandboxes led to real `SetupICU()` initialization failures, which coincided with these test failures. The previous agent resolved the sandboxing issue (ensuring `icudtl.dat` is packaged and `SetupICU()` returns success), but expected this to fix the casing failures. In reality, since the VM string library does not use ICU, `SetupICU()` success or failure has no impact on `String.toUpperCase()`.

## Recommendations

1. **Maintain corelib.status updates:** Keep `unicode_test` and `string_case_test/01` registered under `tests/corelib/corelib.status` as `RuntimeError` for standalone VM/AOT configurations (`$runtime == vm || $runtime == dart_precompiled`).
2. **Long-term spec alignment:** If full Unicode specification compliance is desired for the VM in the future, the C++ `String::ToUpperCase` must be refactored to support variable-length character transforms (perhaps delegating to ICU casing when available, or maintaining an VM-side character expansion map in Dart or C++).

## Affected Files
* `tests/corelib/corelib.status` (registers expected `RuntimeError` on VM)
