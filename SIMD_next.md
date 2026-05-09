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
    // Bypasses complex UTF-8 validation and decodes near-instantaneously
    return String.fromCharCodes(chunk);
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
  int transcodeUtf8ToUtf16(int srcStart, int srcEnd, Uint16List dst, int dstStart);
}
```

---

### 4. Bitmask & Metadata Matching (For SwissTable Data Structures)
High-performance SwissTable hash maps track bucket states using a 1-byte control metadata array. Looking up a key involves comparing a single hash signature against a block of metadata bytes.

```dart
extension VectorMetadata on Uint8List {
  /// Compares [matchByte] against a 16-byte chunk of the receiver starting at [start].
  ///
  /// Returns a 16-bit bitmask where each set bit indicates a matching index.
  /// Lowers directly to matching vector comparison and mask-extraction 
  /// primitives (e.g., `_mm_movemask_epi8` on x86_64).
  int matchMetadata(int matchByte, [int start = 0]);
}
```

---

## Platform Portability & Implementation Matrix

| Target Platform | Under-the-Hood Lowering |
| :--- | :--- |
| **Native JIT / AOT** | Compiles directly to target-specific assembly instructions (e.g., `pcmpeqb`/`pmovmskb` on x86, or `cmeq`/`umaxv` on ARM64). |
| **WebAssembly (WasmGC)** | Compiles to standard **Wasm SIMD v128** instruction primitives. |
| **JavaScript** | Leverages browser-optimized TypedArray APIs or runs highly structured loops designed for JIT engine auto-vectorization. |
