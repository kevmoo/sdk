# Wasm2Kernel: Milestone 2 - The Power of 64-bit

## Summary
We have achieved near-total compliance for WebAssembly 64-bit integer instructions. By leveraging Dart's native 64-bit integer support on the VM, we have successfully mapped the core Wasm numeric instruction set to native Kernel IR nodes.

## Achievements

### 1. Spec Test Breakthrough
- **Target:** `i64.wast` (The official WebAssembly spec test for 64-bit integers).
- **Result:** **354 / 374 assertions passing** (~95% compliance).
- **Parallelism:** Implemented a multi-core test harness that runs assertions in parallel, reducing test time from minutes to seconds.

### 2. IR Mapping Advancements
- **Constants:** Moved from `IntLiteral` (limited to non-negative) to `ConstantExpression(IntConstant(...))` to support the full signed 64-bit range.
- **Complex Ops:** Implemented `clz`, `ctz`, `popcnt`, `rotl`, and `rotr` using a mix of Kernel AST nodes and auto-generated private helper methods.
- **Unsigned Semantics:** Implemented unsigned comparisons using the `(a ^ min_int) < (b ^ min_int)` bit-trick, allowing signed Dart operators to emulate unsigned Wasm behavior.
- **Sign Extension:** Full support for `extend8_s`, `extend16_s`, and `extend32_s`.

### 3. Native Optimization
Because these map directly to `dart:core` `int` operations, the Dart VM's JIT compiler can recognize and optimize them as standard CPU instructions. For example, a Wasm `i64.add` is now an actual machine-level `add` instruction in the VM's output.

## Remaining Numeric Challenges
- **Unsigned Division/Remainder:** Precise 64-bit unsigned division in a signed environment requires careful handling of the most significant bit.
- **Edge Cases:** Refining `clz(0)` and `ctz(0)` to match Wasm specs perfectly.

## Next Milestone: Control Flow
With the numeric foundation solid, we are ready to tackle Tier 3: Structured Control Flow (`block`, `loop`, `if`, `br`).
