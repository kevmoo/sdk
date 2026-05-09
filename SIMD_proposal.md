Proposal: High-Level Data-Centric Vector Primitives ("SIMD Atoms")

This proposal outlines a design for introducing high-level, data-centric vectorized primitives ("SIMD Atoms") to the Dart SDK. Instead of exposing low-level hardware vector registers (which are difficult to write, maintain, and optimize uniformly across Native, WebAssembly, and JavaScript), this approach introduces the concept of a low-level `MemoryBlock` and adds vectorized bulk operations directly onto standard Dart collection types and views.

---

# 1. Background & Limitations of the Status Quo

Exposing architectural-specific vector instructions (e.g., AVX2, NEON) in a high-level application language like Dart creates significant friction:
*   **High Cognitive Load**: Framework and application developers must manage vector lanes, alignments, and target-specific feature checks.
*   **Portability Gaps**: Translating low-level SIMD registers to JavaScript is highly inefficient, defeating the "write once, run fast everywhere" value proposition.
*   **The Legacy of JS-Centric Typed Data**: The existing `dart:typed_data` classes (like `Uint8List`) were designed to mirror JavaScript's `ArrayBuffer` views, carrying heap object overhead, length fields, and generic bounds checks that penalize Native AOT and WasmGC.
*   **Polymorphism & Devirtualization Inhibits Optimization**: When low-level vector operations are placed on standard collection classes that implement `List<int>`, the JIT/AOT compilers must handle a highly polymorphic type hierarchy. This prevents the compiler from optimizing calls to raw index accesses down to single-instruction offset loads, forcing virtual dispatch or explicit runtime type-checks.

**The Solution**: Expose the most common data-manipulation hotspots as high-level vectorized methods on a dedicated, monomorphic, aligned `MemoryBlock` abstraction. This allows:
1.  **Native JIT/AOT**: Direct compiler lowering to SSE4.2/AVX2 (x86_64) or NEON (ARM64) intrinsics.
2.  **WebAssembly**: Translation to standard Wasm SIMD `v128` instructions.
3.  **JavaScript**: Execution via optimized TypedArray operations or highly-optimized loops that modern JS JITs can auto-vectorize.

---

# 2. Core Target Scenarios

## A. Text & JSON Parsing
When parsing text-based formats, the primary hotspot is scanning bytes for control/delimiter characters (quotes `"`, backslashes `\`, newlines `\n`, etc.) and validating ASCII/UTF-8 content boundaries.
*   **Primitives**: `indexOfAny`, `isAscii`.
*   **Benefit**: Bypasses slow byte-by-byte loop scans, moving through input buffers 16 or 32 bytes at a time in a single instruction.

## B. High-Performance Data Structures (SwissTables)
Modern high-performance hash maps (like Abseil's **SwissTable** or Rust's standard `HashMap`) track bucket states using a separate parallel **control metadata array** consisting of 1 byte per bucket:
*   `0xFF` (empty bucket)
*   `0xFE` (deleted/tombstone bucket)
*   `0x00` to `0x7F` (a 7-bit hash signature of the key in that bucket)

During lookups, instead of iterating and comparing expensive key objects, the map calculates a 7-bit hash signature of the target key and compares it against a 16-byte block of the control metadata array simultaneously.
*   **Primitives**: `matchMetadata`, `tzcnt`.
*   **Benefit**: Allows resolving collisions and searching empty buckets in constant time with zero branches.

## C. 2D Graphics & Video (Flutter)
While core rasterization matrix transforms occur in C++ (Skia/Impeller), Flutter's framework layer performs extensive layout and coordinate transformations in pure Dart (gesture hit testing, layout clipping) using `package:vector_math`'s `Matrix4`. Furthermore, live video/camera frames streamed in Dart via `packages/camera` use YUV420 format, requiring high-overhead color space conversions to displayable RGBA.
*   **Primitives**: `transformPoints2D`, `blendSrcOver`/`lerpFloat32`, `shuffleBytes`.
*   **Benefit**: Offloads bulk layout math, pixel alpha compositing, and YUV-to-RGB interleaving to hardware vector units, enabling 60 FPS pipelines in pure Dart.

---

# 3. Public (User-Facing) API Specification

## A. Memory Alignment Enum
Statically restricts memory boundaries to valid hardware power-of-two vector widths, preventing hardware faults and removing runtime verification overhead.

```dart
enum MemoryAlignment {
  /// 16-byte alignment (SSE, NEON, Wasm SIMD).
  sixteen(16),
  /// 32-byte alignment (AVX2).
  thirtyTwo(32),
  /// 64-byte alignment (AVX-512, CPU cache-line boundary).
  sixtyFour(64);

  final int bytes;
  const MemoryAlignment(this.bytes);
}
```

## B. The `MemoryBlock` Abstraction
Represents a safe, size-bounded, contiguous chunk of aligned memory. It
intentionally **does not implement `List<int>`** to protect devirtualization,
preserve AOT compiler inlining, and prevent API bloat.

To prevent manual memory management bugs:
- **GC-Managed**: Standard constructors (`MemoryBlock`, `fromList`) allocate
  fully managed buffers tracked by the garbage collector.
- **FFI Safe Lifetimes**: The `fromAddress` constructor implements
  `Finalizable`, allowing unmanaged native memory to integrate with
  `NativeFinalizer` or scoped FFI `Arena` allocation blocks.

```dart
abstract class MemoryBlock implements Finalizable {
  /// Allocates a block of memory initialized to [initialValue] (standard zero-pass memset).
  external factory MemoryBlock(int length, {
    MemoryAlignment alignment = MemoryAlignment.sixteen,
    int initialValue = 0,
  });

  /// Allocates a new aligned block of memory populated by copying [list].
  external factory MemoryBlock.fromList(List<int> list, {
    MemoryAlignment alignment = MemoryAlignment.sixteen,
  });

  /// Zero-copy constructor wrapping a raw pointer (Native FFI only).
  external factory MemoryBlock.fromAddress(Pointer<Uint8> address, int length);

  int get length;

  /// Returns the underlying ByteBuffer for this memory block.
  /// Allows zero-overhead creation of standard Float32List, Uint32List,
  /// or ByteData views using standard SDK view constructors.
  ByteBuffer get buffer;

  /// Returns an immutable, unmodifiable zero-copy view of this block.
  /// Enables zero-overhead concurrent sharing across Dart Isolates.
  MemoryBlock asReadOnly();

  /// Decodes a slice of this block from [offset] to [offset + length] directly
  /// into a Dart String. Bypasses standard validation if the slice is pure ASCII.
  String decodeToString([int offset = 0, int? length]);

  /// Vector-scans for the first occurrence of any byte in [targets].
  /// Compiles to branchless vector assembly with zero alignment checks.
  int indexOfAny(Uint8List targets, [int start = 0, int? end]);

  /// Vector-checks if the block contains only 7-bit ASCII.
  /// Compiles to branchless vector assembly with zero alignment checks.
  bool isAscii([int start = 0, int? end]);

  /// Compares [matchByte] against a 16-byte chunk of this block starting at [start].
  /// Returns a 16-bit bitmask.
  /// Lowers directly to hardware vector matching (e.g., SSE, NEON, Wasm SIMD).
  int matchMetadata(int matchByte, [int start = 0]);

  /// Multiplies [count] of 2D points (represented as contiguous Float32 pairs
  /// starting at [srcByteOffset] in [source]) by a 3x3 or 4x4 [matrix] (represented
  /// as a 9- or 16-element Float32List), writing the result to [dstByteOffset] in [this].
  /// Lowers directly to FMA (Fused Multiply-Add) SIMD instructions.
  void transformPoints2D(
    Float32List matrix,
    MemoryBlock source,
    int srcByteOffset,
    int dstByteOffset,
    int count,
  );

  /// Performs element-wise linear interpolation:
  /// dst[i] = a[i] * (1 - t[i]) + b[i] * t[i]
  /// for [count] elements starting at the respective byte offsets.
  /// Lowers to floating-point FMA instructions.
  ///
  /// Useful for:
  /// - Graphics & UI: Procedural coordinate morphing, keyframe animation
  ///   interpolation, and path transitions.
  /// - Audio Processing: Fast multichannel audio mixing, smooth signal
  ///   crossfading, and volume gain envelopes.
  /// - Physics & Games: Particle movement calculation, spring-damper
  ///   simulations, and bounding-box scaling.
  /// - Machine Learning: Batch weighting and parallel float activation scaling.
  void lerpFloat32(
    int dstByteOffset,
    MemoryBlock sourceA,
    int aByteOffset,
    MemoryBlock sourceB,
    int bByteOffset,
    MemoryBlock t,
    int tByteOffset,
    int count,
  );

  /// [Proposed Future Extension]
  /// Performs fast alpha-blending (SrcOver) of [pixelCount] pixels from a [source]
  /// block (at [srcByteOffset]) over this destination block (at [dstByteOffset]).
  /// Lowers to integer vector arithmetic (e.g., `i16x8` or `i8x16` packing).
  void blendSrcOver(int dstByteOffset, MemoryBlock source, int srcByteOffset, int pixelCount);

  /// Reorders and interleaves bytes from [source] into this block
  /// according to a [mask] pattern of index offsets.
  /// Lowers directly to hardware shuffle instructions.
  ///
  /// Useful for:
  /// - Graphics: High-speed pixel channel swapping (e.g., RGBA to BGRA).
  /// - I/O & Serialization: Endianness byte-swapping (Big-to-Little Endian) and
  ///   binary protocol parsing.
  /// - Data Conversions: Vector-accelerated hexadecimal encoding and decoding.
  /// - Cryptography: High-speed block cipher byte permutations (AES/SHA).
  void shuffleBytes(
    int dstByteOffset,
    MemoryBlock source,
    int srcByteOffset,
    MemoryBlock mask,
    int maskByteOffset,
    int count,
  );
}
```

## C. The `VectorView` Extension Type
A zero-overhead wrapper type over standard `Uint8List` buffers.
This provides complete zero-copy fallbacks for unaligned vectors
(handling boundary padding with a minor runtime alignment-check setup cost in assembly).

```dart
extension type const VectorView(Uint8List bytes) {
  /// Scans for targets using unaligned SIMD loads.
  int indexOfAny(Uint8List targets, [int start = 0, int? end]) {
    // Lowers to unaligned vector matching intrinsics
  }

  /// Checks for ASCII bytes using unaligned SIMD loads.
  bool isAscii([int start = 0, int? end]) {
    // Lowers to unaligned vector validation intrinsics
  }

  /// Compares [matchByte] against a 16-byte chunk of the list.
  int matchMetadata(int matchByte, [int start = 0]) {
    // Lowers to unaligned vector comparison intrinsics
  }
}
```

## D. First-Class Bit-Manipulation Intrinsics

To support high-performance index scanning and collision walks without relying
on slow, branch-heavy Dart-level loop fallbacks, we align this proposal with
active core library development in Gerrit CL 498041, which introduces native,
compiler-lowered properties directly on the `int` type:

```dart
extension BitIntrinsics on int {
  /// Returns the number of trailing zero bits in the integer.
  /// Lowers directly to compiler-recognized hardware instructions.
  int get trailingZeroBitCount;

  /// Returns the number of set bits (population count) in the integer.
  /// Lowers directly to compiler-recognized hardware instructions.
  int get oneBitCount;

  /// [Proposed Future Extension]
  /// Returns the number of leading zero bits in the integer.
  int get leadingZeroBitCount;
}
```

Under the hood, these methods are compiler-recognized (`asm-intrinsic`) to
guarantee they translate directly to single-cycle hardware assembly instructions
(`TZCNT` / `POPCNT` on x86, `CLZ` / `CNT` on ARM, and standard bit count
operators on WebAssembly).

---

# 4. Internal SDK Additions (`dart:_internal` & Patches)

To protect the core library APIs from domain-specific pollution, internal implementation details are kept private.

Specifically, transcoding APIs are kept private to the SDK (as implementation details inside standard conversion libraries like `dart:convert` patches), while graphics, blending, and shuffling operations are made fully **public** on `MemoryBlock` to allow direct consumption by Flutter and other external packages.

## A. Internal Transcoding Primitives
```dart
abstract class MemoryBlock {
  // ...
  /// Vector-transcodes UTF-8 bytes directly into a UTF-16 buffer [dst].
  /// Handled internally by VM and Wasm compiler shuffle/pack pipelines.
  int _transcodeUtf8ToUtf16(int srcStart, int srcEnd, Uint16List dst, int dstStart);
}
```

*   **Application to Hexadecimal (Hex) Encoding/Decoding**: Hex encoding is fully resolved by extracting high and low 4-bit nibbles and passing a 16-byte mask `MemoryBlock` containing `0123456789abcdef` to `shuffleBytes`, achieving branchless hex conversions in pure Dart.

---

# 5. Detailed SwissTable Key Lookup Example

The following example shows how a high-performance hash map can use `matchMetadata` and the `trailingZeroBitCount` primitive (which compiles to single-cycle hardware instructions) to resolve lookups and scan empty buckets:

```dart
class SwissTable<K, V> {
  // Control metadata block (guaranteed 16-byte aligned)
  final MemoryBlock _ctrl;
  final List<K?> _keys;
  final List<V?> _values;
  final int _capacity;

  SwissTable(int capacity)
      : _capacity = capacity,
        _ctrl = MemoryBlock(capacity, initialValue: 0xFF), // All empty (0xFF)
        _keys = List<K?>.filled(capacity, null),
        _values = List<V?>.filled(capacity, null);

  V? get(K key) {
    final int hash = key.hashCode;
    final int h1 = hash & 0xFFFFFFFF; // Bucket index locator
    final int h2 = hash & 0x7F;       // 7-bit metadata signature

    int bucketIndex = h1 % _capacity;

    while (true) {
      // Match the 7-bit signature against 16 buckets simultaneously
      int matchMask = _ctrl.matchMetadata(h2, bucketIndex);

      // Simultaneously scan for empty buckets (0xFF) to know when to stop
      int emptyMask = _ctrl.matchMetadata(0xFF, bucketIndex);

      // Iterate over bit positions set in the matchMask
      while (matchMask != 0) {
        final int offset = matchMask.trailingZeroBitCount; // Single CPU instruction
        final int candidateIndex = (bucketIndex + offset) % _capacity;

        if (_keys[candidateIndex] == key) {
          return _values[candidateIndex];
        }
        matchMask &= ~(1 << offset); // Clear the processed bit
      }

      // If any bucket in this 16-byte block was empty, the key is not present
      if (emptyMask != 0) {
        return null;
      }

      // Move to next 16-byte block (handling collision)
      bucketIndex = (bucketIndex + 16) % _capacity;
    }
  }
}
```

---

# 6. Compilation Lowering Matrix

## A. x86_64 Lowering (SSE4.2 / AVX2)

| Primitive / Atom | Compiler ASM Code Generation |
| :--- | :--- |
| `indexOfAny` | `movdqu` (load targets) + `pcmpeqb` / `pmovmskb` + `bsfq` scanning loops. |
| `isAscii` | `movups` vector loads + `pmovmskb` + check if result bitmask is `0`. |
| `matchMetadata` | `movaps` (aligned load) + `pcmpeqb` + `pmovmskb` mask extraction. |
| `shuffleBytes` | `movdqu` (load source/mask) + `pshufb` (byte-level shuffle). |
| `lerpFloat32` | `vfmadd213ps` / `vfmadd231ps` (Fused Multiply-Add vector floats). |
| `trailingZeroBitCount` | `tzcnt` (Trailing Zero Count, AVX/BMI1) or `bsfq` (Bit Scan Forward). |

## B. ARM64 Lowering (NEON / SVE)

| Primitive / Atom | Compiler ASM Code Generation |
| :--- | :--- |
| `indexOfAny` | `ld1` vector load + `cmeq` (compare) + `umaxv` / `mov` scanning loops. |
| `isAscii` | `ld1` vector load + `orrv` reduction + check sign bit. |
| `matchMetadata` | `ldr` (aligned load) + `cmeq` (compare vector) + `shrn` bit extraction. |
| `shuffleBytes` | `ld1` + `vqtbl1q_u8` (Vector table byte shuffle). |
| `lerpFloat32` | `fmla` (Vector Floating-Point Fused Multiply-Add). |
| `trailingZeroBitCount` | `clz` (Count Leading Zeros, executed on bit-reversed register). |

## C. WebAssembly Lowering (WasmGC SIMD)

| Primitive / Atom | Compiler Wasm Instruction Generation |
| :--- | :--- |
| `indexOfAny` | `v128.load` + `i8x16.eq` + `i8x16.bitmask` scanning. |
| `isAscii` | `v128.load` + check MSB signs in lanes. |
| `matchMetadata` | `v128.load` + `i8x16.eq` + `i8x16.bitmask`. |
| `shuffleBytes` | `v128.load` + `i8x16.shuffle`. |
| `lerpFloat32` | Fused float multiply-add instruction sequence. |
| `trailingZeroBitCount` | `i32.ctz` (Count Trailing Zeros). |

## D. JavaScript Lowering (TypedArrays / Auto-Vectorization)

| Primitive / Atom | Browser JS Engine Execution |
| :--- | :--- |
| `indexOfAny` | Optimized `Uint8Array.indexOf` loops (leverages browser `memchr` C++ fallbacks). |
| `isAscii` | Fallback to standard JS TypedArray loop or WebAssembly fallback helper. |
| `matchMetadata` | Highly structured 16-byte comparison loop designed for JIT auto-vectorization. |
| `shuffleBytes` | Direct byte swaps or standard JS loops designed for `pshufb` JIT translation. |
| `lerpFloat32` | Optimizable TypedArray iteration mapped to hardware vector float instructions. |
| `trailingZeroBitCount` | `Math.clz32` (Bitwise conversion fallback). |

---

# 7. dart:io Socket2 Specification

In standard `dart:io`, the current `Socket` API is built around `List<int>` and
`Stream<Uint8List>`. This model introduces substantial garbage collection (GC)
pressure during high-throughput I/O (such as gRPC, HTTP/2, or high-volume
database connections) because every read event allocates a new `Uint8List` on
the heap and copies bytes into it from the OS socket.

By utilizing `MemoryBlock`, we can specify a zero-copy, allocation-free I/O
abstraction named `Socket2`.

## A. Zero-Copy Reads & Buffer Reusability

Instead of allocating and returning new buffers, `Socket2` allows developers to
pass a mutable `MemoryBlock` directly to the socket, copying bytes from the OS
kernel buffer directly into the pre-allocated aligned block:

```dart
abstract class Socket2 {
  /// Reads bytes from the socket directly into [buffer] starting at [offset].
  ///
  /// Returns the number of bytes read.
  /// Since the VM passes the aligned MemoryBlock address directly to the OS
  /// read/recv syscall, this operates as a zero-copy, zero-heap-allocation path.
  int read(MemoryBlock buffer, [int offset = 0, int? length]);
}
```

## B. Recycled Ring-Buffer Event Loop

To maintain an asynchronous event-driven model without heap allocation overhead,
`Socket2` can offer a callback loop that recycles a fixed pool of `MemoryBlock`
ring buffers:

```dart
abstract class Socket2 {
  /// Listens for incoming socket chunks using a pre-allocated pool of MemoryBlocks.
  ///
  /// Once the [onData] callback completes, the MemoryBlock is immediately
  /// recycled back into the socket's internal ring-buffer pool.
  void listen(
    void onData(MemoryBlock chunk), {
    Function? onError,
    void onDone()?,
  });
}
```
*   **Developer Usage**: The parser (e.g., a fast JSON or HTTP parser) processes the incoming aligned `MemoryBlock` in place using SIMD primitives (`indexOfAny`, `matchMetadata`) inside the callback and returns. The memory is then immediately reused for the next network package without hitting the garbage collector.

## C. Zero-Copy Writes

For writing data, `Socket2` accepts a `MemoryBlock` directly, passing its raw memory address directly to the OS `write`/`send` system call without copying:

```dart
abstract class Socket2 {
  /// Writes [length] bytes from [buffer] starting at [offset] directly to the socket.
  ///
  /// Bypasses standard VM collection wrapper and copy penalties.
  void write(MemoryBlock buffer, [int offset = 0, int? length]);
}
```
