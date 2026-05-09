# SIMD Brain Dump & Notes for the Next Agent

This file contains a raw brain dump of implementation notes, compiler optimization
leads, and structural ideas captured during the design of the `MemoryBlock` and
"SIMD Atoms" proposal. These serve as highly detailed starting points for the
next agent tasked with implementing the prototype in the VM, Wasm, and Web
compilers.

---

## 1. VM Compiler & JIT Optimization Leads

### devirtualization & Monomorphism
To prevent polymorphic dispatch degradation, the JIT/AOT compiler's flow graph
optimizer must treat `MemoryBlock` as a final, exact-type class. 
*   During the flow graph building phase (in `kernel_to_il.cc`), calls to
    `MemoryBlock` methods should bypass standard method dispatch.
*   The JIT should immediately lower them to recognized intrinsics (e.g.,
    `MemoryBlockMatchMetadataInstr`, `MemoryBlockTransformPoints2DInstr`)
    without building polymorphic call inline caches.

### GC Pinned Memory Backing
*   To make `MemoryBlock.fromAddress` completely zero-copy and FFI-safe, the VM
    allocator must support **pinned memory**. 
*   Standard GC-managed Dart arrays can be relocated during scavenging or
    compaction phases. A `MemoryBlock` must wrap either:
    1.  A pinned heap array that is explicitly excluded from GC movement.
    2.  An externally allocated buffer (malloc'd) managed by a
        `NativeFinalizer` to keep raw FFI pointers statically valid without
        copying.

---

## 2. WebAssembly (WasmGC) Compilation Strategy

*   WasmGC introduces structured arrays (`array` types) which are managed by the
    Wasm garbage collector.
*   For `MemoryBlock` on Wasm:
    *   Map `MemoryBlock` directly to a flat Wasm array type: `(type $MemoryBlock (array (mut i8)))`.
    *   In `dart2wasm`, map vector methods directly to **Wasm SIMD v128**
        instructions. For example:
        *   `matchMetadata` lowers to: `v128.load` -> `i8x16.eq` ->
            `i8x16.bitmask`.
        *   `shuffleBytes` lowers to: `v128.load` -> `i8x16.shuffle`.
*   Since WasmGC array boundaries are safely checked by the Wasm runtime, bounds
    checks can be offloaded directly to the Wasm execution engine at hardware
    limit speeds.

---

## 3. JavaScript Fallback & Auto-Vectorization

Because JS does not support raw, stable SIMD instructions consistently across
all engines (V8, JSC, SpiderMonkey), the JS compiler (`dart2js` / DDC) must
generate fallback loops designed specifically to trigger JIT auto-vectorization:

*   **Loop Cleanliness**: Fallback loops must be completely free of object
    allocations, dynamic view instantiations, and generic helper calls.
*   **Typed Views**: Keep loop indexing bounded by fixed, local constants (e.g.,
    chunks of 16 or 32) so that JIT engine heuristics can cleanly unroll and translate
    them to SSE/NEON instructions on the host machine:
    ```javascript
    // Target structure for V8 auto-vectorizer:
    for (let i = 0; i < 16; i++) {
      dst[dstOffset + i] = srcA[srcAOffset + i] * (1.0 - t[tOffset + i]) + srcB[srcBOffset + i] * t[tOffset + i];
    }
    ```

---

## 4. Integration with Upstream Intrinsics

*   We successfully aligned our bit-manipulation primitives with **Gerrit CL
    498041**, which adds native, compiler-lowered properties (`oneBitCount` and
    `trailingZeroBitCount`) to the `int` type.
*   When implementing the SwissTable search in `compact_hash.dart`, the next
    agent can directly use:
    ```dart
    final int offset = matchMask.trailingZeroBitCount;
    ```
    This ensures that collision indexing compiles directly to a single-cycle
    `TZCNT` (x86) or `CLZ` (ARM) instruction in the generated assembly.

---

## 5. Open Design Questions

1.  **Direct I/O Slicing Safety**: Can we implement the "Detached Buffer"
    (neutering) pattern inside the VM with zero check overhead?
    *   *Lead*: When recycling a `MemoryBlock` in a `Socket2` ring pool, we can
        simply set an internal unboxed boolean `isDetached = true` on the
        associated `_ByteBuffer` instances. View methods must check this flag in
        non-performance paths.
2.  **Direct DMA / io_uring Integration**:
    *   Could a future `dart:io` Socket layer pass the raw physical address of
        a 64-byte aligned `MemoryBlock` directly to kernel ring buffers for
        direct-to-disk DMA writes?
