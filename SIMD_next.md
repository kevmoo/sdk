# Proposal: High-Level Data-Centric Vector Primitives ("SIMD Atoms")

This proposal outlines a design for introducing high-level, data-centric vectorized primitives ("SIMD Atoms") to the Dart SDK. Instead of exposing low-level hardware vector registers (which are difficult to write, maintain, and optimize uniformly across Native, WebAssembly, and JavaScript), this approach adds vectorized bulk operations directly onto standard Dart collection types (like `Uint8List`, `String`, or `ByteData`).

---

## Core Philosophy: Data-Centric Vectorization

Exposing architectural-specific vector instructions (e.g. AVX2, NEON) in a high-level application language like Dart creates significant friction:
- **High Cognitive Load**: Framework and application developers must manage vector lanes, alignments, and target-specific feature checks.
- **Portability Gaps**: Translating low-level SIMD registers to JavaScript is highly inefficient, defeating the "write once, run fast everywhere" value proposition.

**The Solution**: Expose the most common data-manipulation hotspots as high-level vectorized methods. This allows:
1. **Native JIT/AOT**: Direct compiler lowering to SSE4.2/AVX2 (x86_64) or NEON (ARM64).
2. **WebAssembly**: Translation to standard Wasm SIMD `v128` instructions.
3. **JavaScript**: Execution via optimized TypedArray operations or highly-optimized loops that modern JS JITs can auto-vectorize.

---

## The `MemoryBlock` Abstraction

To avoid the overhead of JS-centric collection views (like bounds checks, length fields, and heap objects) on Native and Wasm targets, we introduce the concept of a low-level `MemoryBlock`.

A `MemoryBlock` represents a safe, size-bounded, contiguous chunk of memory designed specifically to meet alignment and padding constraints for hardware vector operations:

```dart
enum MemoryAlignment {
  /// 16-byte alignment (SSE, NEON, Wasm SIMD).
  sixteen(16),
  /// 32-byte alignment (AVX2).
  thirtyTwo(32),
  /// 64-byte alignment (AVX-512, cache-line).
  sixtyFour(64);

  final int bytes;
  const MemoryAlignment(this.bytes);
}

/// A safe, size-bounded contiguous chunk of aligned memory.
abstract class MemoryBlock {
  /// Allocates a block of memory initialized to [initialValue].
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

  /// Access a single byte. Lowers to raw memory offsets on Native/Wasm.
  int operator [](int index);

  /// Writes a single byte to the block. Throws an UnsupportedError
  /// if the block is read-only/immutable.
  void operator []=(int index, int value);

  /// Returns a zero-copy standard Uint8List view of this block.
  Uint8List asUint8List();

  /// Returns an immutable, unmodifiable zero-copy view of this block.
  /// Enables zero-overhead concurrent sharing across Dart Isolates.
  MemoryBlock asReadOnly();

  /// Vector-scans for the first occurrence of any byte in [targets].
  /// Compiles to branchless vector assembly with zero alignment checks.
  int indexOfAny(Uint8List targets, [int start = 0, int? end]);

  /// Vector-checks if the block contains only 7-bit ASCII.
  /// Compiles to branchless vector assembly with zero alignment checks.
  bool isAscii([int start = 0, int? end]);

  /// Vector-transcodes UTF-8 bytes directly into a UTF-16 buffer [dst].
  int _transcodeUtf8ToUtf16(int srcStart, int srcEnd, Uint16List dst, int dstStart);

  /// Compares [matchByte] against a 16-byte chunk of this block starting at [start].
  /// Returns a 16-bit bitmask.
  /// Lowers directly to hardware vector matching (e.g., SSE, NEON, Wasm SIMD).
  int matchMetadata(int matchByte, [int start = 0]);
}

/// A zero-overhead extension type providing a zero-copy vector search, validation,
/// and matching API over standard, potentially unaligned lists.
extension type const VectorView(Uint8List bytes) {
  /// Scans for targets using unaligned SIMD loads.
  /// Pays a minor runtime setup cost to handle unaligned boundaries.
  int indexOfAny(Uint8List targets, [int start = 0, int? end]) {
    // Lowers to unaligned vector matching intrinsics
  }

  /// Checks for ASCII bytes using unaligned SIMD loads.
  /// Pays a minor runtime setup cost to handle unaligned boundaries.
  bool isAscii([int start = 0, int? end]) {
    // Lowers to unaligned vector validation intrinsics
  }

  /// Compares [matchByte] against a 16-byte chunk of the list.
  /// Pays a minor runtime setup/alignment check cost.
  int matchMetadata(int matchByte, [int start = 0]) {
    // Lowers to unaligned vector comparison intrinsics
  }
}
```

### Key Characteristics:
1. **Platform-Safe Bounds Checks**: On JS, it is backed by a standard `Uint8Array` (ensuring sandbox safety). On Native and Wasm targets, JIT/AOT range analysis completely optimizes out bounds checks in loops, and memory bounds are safely managed by fast hardware-level traps or lightweight VM structures.
2. **Alignment Guarantees**: SIMD instructions perform best when memory is 16-byte or 32-byte aligned. `MemoryBlock` guarantees this alignment upon allocation.
3. **Ecosystem Interoperability**: Offers seamless interop via zero-copy views (`asUint8List()`) and zero-overhead wrapper extension types (`VectorView(Uint8List)`). This lets developers pass standard typed lists around while accessing vector performance inside critical hot paths.

### Why `MemoryBlock` does not implement `List<int>`

Exposing `List<int>` directly on `MemoryBlock` is intentionally avoided to prevent critical performance and compilation trade-offs:
- **Protects Devirtualization & Inlining**: If `MemoryBlock` implements `List<int>`, generic operations accepting lists become polymorphic. This prevents JIT/AOT compilers from optimizing calls to raw `[]` accesses down to single-instruction offset loads.
- **Prevents Interface Bloat**: Implementing `List<int>` forces the definition of dozens of standard APIs (`where()`, `map()`, `sort()`). This introduces binary size overhead and encourages high-overhead closure allocation patterns on a type built purely to avoid allocation.
- **Clean Separation via Views**: Interoperability is maintained via composition. When passing data to standard collections APIs, developers use `.asUint8List()` to obtain a standard list view.

---



## Key "Atom" Proposals

### 1. Parsing & Matching Atoms (For JSON, CSV, HTTP, XML)
When parsing text-based formats, the primary hotspot is scanning bytes for control/delimiter characters (quotes `"`, backslashes `\`, newlines `\n`, etc.).

```dart
extension VectorSearch on Uint8List {
  /// Searches the receiver for the first occurrence of any byte present in [targets].
  ///
  /// Returns the index of the first match, or -1 if no match is found.
  /// The compiler lowers this to SIMD vector byte matching (e.g., checking
  /// 16 or 32 bytes at a time in a single instruction).
  int indexOfAny(Uint8List targets, [int start = 0, int? end]);
}
```

#### Usage in JSON String Scanning:
Instead of a byte-by-byte loop, a JSON parser can skip safely through strings in chunks:
```dart
// Match quote (0x22) or escape backslash (0x5C)
static final Uint8List jsonStringTerminators = Uint8List.fromList([0x22, 0x5C]);

void scanString() {
  int nextMatch = chunk.indexOfAny(jsonStringTerminators, cursor);
  if (nextMatch != -1) {
    cursor = nextMatch;
  }
}
```

---

### 2. ASCII Validation Atoms (For Fast-Path I/O)
Knowing if a payload is purely ASCII allows I/O systems and parsers to completely bypass complex multi-byte UTF-8 decoding state machines.

```dart
extension VectorValidation on Uint8List {
  /// Returns true if the slice of bytes from [start] to [end] contains
  /// only ASCII characters (all byte values < 128).
  ///
  /// Lowers to vector OR-reductions to check if the MSB (most significant bit)
  /// is set on any byte in 16- or 32-byte lanes.
  bool isAscii([int start = 0, int? end]);
}
```

#### Usage in Fast-Path String Allocation:
```dart
String decodePayload(Uint8List chunk) {
  if (chunk.isAscii()) {
    // Bypasses complex UTF-8 validation and generic char-code scans.
    // On the VM, this directly allocates a _OneByteString and copies bytes.
    return String._createOneByteString(chunk, 0, chunk.length);
  }
  return utf8.decode(chunk);
}
```


---

### 3. Bulk Transcoding Atoms
Converting UTF-8 bytes to UTF-16 is a common bottleneck since Dart `String` objects are internally UTF-16 or Latin-1.

```dart
extension VectorTranscode on Uint8List {
  /// Vector-transcodes UTF-8 bytes directly into a destination UTF-16 buffer [dst].
  ///
  /// Returns the number of characters written to [dst].
  /// Under the hood, the VM and Wasm compilers use vectorized shuffle/pack
  /// routines to unpack 1-byte UTF-8 elements into 2-byte UTF-16 lanes.
  int _transcodeUtf8ToUtf16(int srcStart, int srcEnd, Uint16List dst, int dstStart);
}
```

---

### 4. Bitmask & Metadata Matching (For SwissTable-style Data Structures)
High-performance hash maps (like Abseil's **SwissTable** or Rust's standard `HashMap`) do not store keys directly in the lookup bucket array. Instead, they keep a separate parallel **control metadata array** consisting of 1 byte per bucket:
- `0xFF` (empty bucket)
- `0xFE` (deleted/tombstone bucket)
- `0x00` to `0x7F` (a 7-bit hash signature of the key in that bucket)

During a lookup, instead of iterating and comparing expensive key objects, the map calculates a 7-bit hash signature of the target key and compares it against a 16-byte block of the control metadata array simultaneously.

Because `matchMetadata` requires strict 16-byte memory alignment and safety padding to execute vector loads safely without hardware faults, it is exposed directly as an instance method on `MemoryBlock`:

```dart
abstract class MemoryBlock {
  // ... existing APIs ...

  /// Compares [matchByte] against a 16-byte chunk of this block starting at [start].
  ///
  /// Returns a 16-bit bitmask where the i-th bit is set if the byte matches.
  ///
  /// Under the hood, this lowers directly to vector comparisons and mask-extraction
  /// instructions:
  /// - **x86_64**: `_mm_cmpeq_epi8` followed by `_mm_movemask_epi8` (1 instruction each).
  /// - **ARM64**: `cmeq` (vector comparison) followed by `shrn` (shift right narrow).
  /// - **Wasm**: `i8x16.eq` followed by `i8x16.bitmask`.
  int matchMetadata(int matchByte, [int start = 0]);
}
```

#### Usage in a Fast SwissTable Key Lookup:
The following example shows how a hash map can resolve lookups, scan for empty buckets (to terminate searches), and check for potential candidate matches in a single vectorized operation using `MemoryBlock`:

```dart
class SwissTable<K, V> {
  // Control metadata block (guaranteed 16-byte aligned)
  final MemoryBlock _ctrl;
  final List<K?> _keys;
  final List<V?> _values;
  final int _capacity;

  SwissTable(int capacity)
      : _capacity = capacity,
        _ctrl = MemoryBlock(capacity, initialValue: 0xFF), // All empty
        _keys = List<K?>.filled(capacity, null),
        _values = List<V?>.filled(capacity, null);

  V? get(K key) {
    final int hash = key.hashCode;
    final int h1 = hash & 0xFFFFFFFF; // Bucket index group locator
    final int h2 = hash & 0x7F;       // 7-bit metadata signature

    int bucketIndex = h1 % _capacity;

    while (true) {
      // Match the 7-bit signature against 16 buckets simultaneously
      int matchMask = _ctrl.matchMetadata(h2, bucketIndex);

      // Simultaneously scan for empty buckets (0xFF) to know when to stop
      int emptyMask = _ctrl.matchMetadata(0xFF, bucketIndex);

      // Iterate over bit positions set in the matchMask
      while (matchMask != 0) {
        final int offset = matchMask.tzcnt(); // Trailing zero count (vector/CPU instruction)
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

extension on int {
  // Trailing zero count primitive (lowers to TZCNT or CLZ assembly)
  int tzcnt() {
    if (this == 0) return 32;
    // Fallback or compiler intrinsic
    int n = 0;
    int val = this;
    if ((val & 0x0000FFFF) == 0) { n += 16; val >>>= 16; }
    if ((val & 0x000000FF) == 0) { n += 8;  val >>>= 8;  }
    if ((val & 0x0000000F) == 0) { n += 4;  val >>>= 4;  }
    if ((val & 0x00000003) == 0) { n += 2;  val >>>= 2;  }
    if ((val & 0x00000001) == 0) { n += 1; }
    return n;
  }
}
```


---

### Application to SDK Collections (Optimizing `dart:collection`)

We can directly apply this metadata matching approach to optimize standard collections (such as `LinkedHashMap` and `LinkedHashSet` in [compact_hash.dart](file:///Users/kevmoo/github/dart/sdk/sdk/lib/_internal/vm_shared/lib/compact_hash.dart)):

1. **Current Open Addressing**: Dart's internal `_LinkedHashMapMixin._findValueOrInsertPoint` currently uses linear probing to search a `Uint32List _index` containing compressed hash/index pairs, checking slots one by one in a Dart loop. This introduces linear search overhead during collisions and increases cache misses.
2. **Vectorized SwissTable Integration**: We can split the index structure into a `Uint8List _ctrl` metadata array and a `Uint32List _slots` index array. During map lookups, we can call `_ctrl.matchMetadata(h2, bucketIndex)` to match the hash prefix across 16 buckets in parallel, using hardware SIMD vector operations to resolve collision probes instantly.

---


## Platform Portability & Implementation Matrix

| Target Platform | Under-the-Hood Lowering |
| :--- | :--- |
| **Native JIT / AOT** | Compiles directly to target-specific assembly instructions (e.g., `pcmpeqb`/`pmovmskb` on x86, or `cmeq`/`umaxv` on ARM64). |
| **WebAssembly (WasmGC)** | Compiles to standard **Wasm SIMD v128** instruction primitives. |
| **JavaScript** | Leverages browser-optimized TypedArray APIs or runs highly structured loops designed for JIT engine auto-vectorization. |

---

## Going further with MemoryBlock: 2D Graphics Performance

For UI and graphics frameworks like Flutter, CPU-side rendering, layout tessellation, and image/video processing represent significant performance hotspots. If `MemoryBlock` is introduced, we can expose **Bulk Graphics Atoms** to accelerate these operations at hardware limits across Native AOT and WasmGC:

### 1. Batch Coordinate Transformations (Matrix Math)
Tessellating 2D paths into triangles or positioning layout elements requires multiplying large batches of coordinate pairs `[x, y]` or triplets `[x, y, z]` by a `4x4` transformation matrix.

```dart
extension VectorGraphics on MemoryBlock {
  /// Multiplies [count] of 3D points (represented as contiguous Float32 triplets
  /// starting at [srcByteOffset]) by a 4x4 [matrix], writing the result to [dstByteOffset].
  ///
  /// Lowers directly to FMA (Fused Multiply-Add) SIMD instructions, transforming
  /// multiple vertices in parallel.
  void transformPoints3D(Float32List matrix, int srcByteOffset, int dstByteOffset, int count);
}
```

### 2. Pixel Blending and Composition (Alpha Compositing & Linear Interpolation)

Software compositing of pixel buffers (e.g., **SrcOver** alpha blending) represents a heavy CPU-bound operation. We can address this using either a targeted graphics-specific atom or a generalized mathematical primitive:

#### Option A: Graphics-Specific Blending (Direct & Fast)
Directly implements the Porter-Duff `SrcOver` composition formula (`dst = src * alpha + dst * (1 - alpha)`) using integer vector math, offloading pixel calculations directly to hardware vector lanes.

```dart
extension VectorBlending on MemoryBlock {
  /// Performs fast alpha-blending (SrcOver) of [pixelCount] pixels from a [source]
  /// block (at [srcByteOffset]) over this destination block (at [dstByteOffset]).
  ///
  /// Lowers to vector multiplication and packing instructions (e.g., `i16x8` or `i8x16`
  /// arithmetic), calculating alpha values for 4 or 8 pixels concurrently.
  void blendSrcOver(int dstByteOffset, MemoryBlock source, int srcByteOffset, int pixelCount);
}
```

#### Option B: Generalized Linear Interpolation (Versatile)
Exposes a general-purpose batch linear interpolation (`lerp`) primitive. This is highly useful not only for graphics, but also for **audio mixing** (blending audio signals), **physics engines**, and **machine learning** pipelines.

```dart
extension VectorLerp on MemoryBlock {
  /// Performs element-wise linear interpolation: dst[i] = a[i] * (1 - t[i]) + b[i] * t[i]
  /// for [count] elements starting at the respective byte offsets.
  ///
  /// Lowers to FMA (Fused Multiply-Add) vector instructions on floating-point lanes.
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
}
```

*   **Trade-off**: `lerpFloat32` is a much more versatile and elegant mathematical primitive. However, `blendSrcOver` remains faster and more efficient for Flutter's specific graphics pipeline because standard pixel composition requires specific, non-linear integer-scaled alpha divisions that are difficult to represent cleanly using generic float-based vector math.


### 3. Bulk Byte Reordering and Interleaving (Vector Shuffle)
Exposing specific video codec formats like `convertYUV420ToRGBA` directly in the core libraries is too narrow. Instead, we introduce a **Vector Shuffle / Permute** primitive. 

This provides a highly reusable mathematical foundation (extremely useful for cryptography, data serialization, and graphics) that allows package authors to build high-performance pixel conversions entirely in user-space Dart.

*   **Application to Hexadecimal (Hex) Encoding/Decoding**: A specialized `encodeHex` primitive is unnecessary. Hex encoding is fully resolved by shifting bytes (extracting high and low 4-bit nibbles) and using `shuffleBytes` against a 16-byte lookup table `MemoryBlock` containing the ASCII values `0123456789abcdef`. This achieves native, branchless hex conversions in a few lines of pure Dart code.


```dart
extension VectorShuffle on MemoryBlock {
  /// Reorders and interleaves bytes from [source] into this block
  /// according to a [mask] pattern of index offsets.
  ///
  /// Lowers directly to hardware shuffle instructions:
  /// - **x86_64**: `_mm_shuffle_epi8` (`pshufb`).
  /// - **ARM64**: `vqtbl1q_u8` (Vector table lookup).
  /// - **Wasm**: `i8x16.shuffle`.
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


### Real-World Grounding

These three graphics primitives directly address real-world bottlenecks inside Flutter's rendering pipeline and popular package ecosystems:

1. **Matrix Transformations (`transformPoints3D`)**:
   - **The Dart Context**: While the rasterizer performs transformations in C++ (Skia/Impeller), Flutter's framework layer performs extensive layout and coordinate transformations in pure Dart using `package:vector_math`'s `Matrix4`.
   - **Layout and Hit Testing**: When mapping global touch pointer offsets to local bounds through deep render trees (e.g., during gesture detection and hit testing), or computing composition layers bounds, the framework performs millions of matrix-coordinate multiplications. A native `transformPoints3D` on `MemoryBlock` bypasses the high-overhead scalar math of `vector_math` without incurring FFI transition penalties.

2. **Pixel Blending (`blendSrcOver`)**:
   - **Bitmap Manipulation (`package:image`)**: Dart's standard image processing library relies on slow, manual scalar loops to blend images and perform alpha compositing (SrcOver), taking multiple milliseconds for HD frames. Exposing `blendSrcOver` offloads this bulk color math directly to 16-byte SIMD lanes.

3. **Vector Shuffling (`shuffleBytes`)**:
   - **Flutter Camera Plugin & Video Pipelines**: The official `packages/camera` plugin streams live frames in raw YUV420 format (documented in [image_format_group.dart](flutter_packages - packages/camera/camera_platform_interface/lib/src/types/image_format_group.dart)). Converting YUV planes to displayable RGBA in pure Dart currently requires slow, manual byte-unpacking loops, capping frame rates to under 15 FPS. By using a generic `shuffleBytes` atom combined with basic arithmetic, package authors can implement high-speed color-space conversions and channel-swapping (such as RGBA to BGRA) at native SIMD speeds in pure Dart, maintaining a clean core API.

