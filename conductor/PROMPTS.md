# User-Driven Design Notes

The final design of `Socket2` was heavily influenced by iterative feedback from the "Vibe-Coding" Product Manager. Here are the key pivots driven by the user's prompts.

## 1. "Keep it Simple: Use Records"
*   **Original Plan**: I proposed creating custom `ReadResult` and `WriteResult` classes to hold the byte count and the returned buffer.
*   **Prompt**: "Why not just have one Result class... Or even a Dart Record type. Keep it simple."
*   **Impact**: We pivoted to using Dart 3 Records. This reduced class-bloat in `dart:io` and made the API feel much more modern and "Dart-y."

## 2. "Use Object, not dynamic"
*   **Prompt**: "Let's make address type Object (not dynamic) - we'll never allow null."
*   **Impact**: This improved the type safety of the API. While `ServerSocket.bind` in `Socket1` used `dynamic` (for legacy reasons), `Socket2` starts with a cleaner, non-nullable contract for its host and address parameters.

## 3. "Use Named Record Fields"
*   **Prompt**: "Make those record fields NAMED - so folks don't have to deal with $1, $2."
*   **Impact**: This was a huge ergonomic win. It changed the return type from `(int, TypedData)` to `({int bytes, TypedData buffer})`. It made the implementation code (especially in the `bottom_shelf` loop) significantly more readable and less prone to "off-by-one" positional errors.

## 4. "The Throughput Challenge"
*   **Prompt**: "How do I see how good it can be? I was hoping to have a 'slam dunk' for overall throughput."
*   **Impact**: This pushed me to go beyond simple "hello world" echo tests. It led to the creation of the 1.3MB payload benchmark, which provided the definitive proof that zero-copy `Socket2` is 3.3x faster than the original implementation.
