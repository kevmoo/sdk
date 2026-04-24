# Wasm2Kernel: Direct IR vs. Dart Source Generation

## The Decision: Why Target Kernel IR?

When translating Wasm to the Dart ecosystem, we have two primary paths: generating Dart source code (`.dart`) or generating Kernel IR (`.dill`) directly. While source generation is easier to implement, targeting Kernel is the superior choice for high-performance systems.

### 1. Performance and "Middleman" Overhead
*   **Dart Source:** The Dart VM does not execute source code directly. It relies on the Common Front End (CFE) to parse, scan, and perform type inference to produce Kernel IR. Generating source adds a significant "compilation" step every time the Wasm is loaded.
*   **Kernel IR:** By generating Kernel directly, we bypass the CFE entirely. This results in **faster start-up times** and allows the VM to move immediately to JIT/AOT compilation.

### 2. Surgical Semantic Mapping
Wasm is a low-level, stack-based language with strict rules for integer wrap-around and memory access.
*   **Impedance Mismatch:** Expressing Wasm's linear memory and bitwise semantics in high-level Dart source often requires "boilerplate" (like explicit masking or `ByteData` calls) that the CFE might not always optimize perfectly.
*   **IR Control:** Targeting Kernel allows us to use specific IR nodes and point directly to **VM intrinsics**. We can ensure that a Wasm `i32.load` maps to the exact IR node the VM recognizes as a single CPU instruction, ensuring **maximum execution performance**.

### 3. Stability and Maintenance
*   **The "Unstable" Argument:** While the Kernel format is internal and can change, the Dart SDK itself is the primary user of this format. By building the "Wasm Frontend" within or alongside the SDK (using `pkg/kernel`), we stay in sync with the VM's expectations.
*   **Native Language:** Kernel is the "native" language of the Dart VM. Speaking this language directly removes the ambiguity of a high-level language translation layer.

## Conclusion
To achieve **zero-overhead Wasm execution**, we must speak the VM's native language. Direct Kernel generation provides the necessary control to map low-level Wasm constructs to high-performance VM primitives, fulfilling the goal of making Wasm algorithms feel "native" to the Dart environment.
