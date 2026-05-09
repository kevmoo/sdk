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

```dart
extension VectorMetadata on Uint8List {
  /// Compares [matchByte] against a 16-byte chunk of the receiver starting at [start].
  ///
  /// Returns a 16-bit bitmask where the i-th bit is set if `this[start + i] == matchByte`.
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
The following example shows how a hash map can resolve lookups, scan for empty buckets (to terminate searches), and check for potential candidate matches in a single vectorized operation without branches:

```dart
class SwissTable<K, V> {
  // Control metadata bytes (1 byte per bucket)
  final Uint8List _ctrl;
  final List<K?> _keys;
  final List<V?> _values;
  final int _capacity;

  SwissTable(int capacity)
      : _capacity = capacity,
        _ctrl = Uint8List(capacity)..fillRange(0, capacity, 0xFF), // All empty
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
