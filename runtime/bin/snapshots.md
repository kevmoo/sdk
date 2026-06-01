# Dart VM Snapshot Embeddings in `runtime/bin`

This document describes how various compiled snapshot blobs are embedded into the Dart SDK executables (such as `dartvm`, `dart`, and `dartaotruntime`) at build time, their corresponding preprocessor symbols, producing targets, and runtime consumers.

## Snapshot Families

The build system generates and links three distinct families of snapshot embeddings depending on the target executable and its execution mode (JIT vs AOT).

| Preprocessor Symbol | Build Target | Executable (Consumer) | `gen_snapshot` Recipe | Description |
| --- | --- | --- | --- | --- |
| `kDartCoreSnapshotData`<br>`kDartCoreSnapshotText` | `core_snapshot_data_linkable`<br>`core_snapshot_text_linkable` | `dartvm` (JIT runtime) | `gen_snapshot --snapshot_kind=core` | Core JIT snapshots loaded to bootstrap the JIT VM state. |
| `kDartVmSnapshotData`<br>`kDartVmSnapshotInstructions` | `vm_snapshot_data_linkable`<br>`vm_snapshot_instructions_linkable` | AOT product loaders (`dart`, `dartaotruntime`) | `gen_snapshot --snapshot_kind=vm-aot` | AOT VM snapshot containing heap-serialised data and initial instructions shared across isolates in AOT mode. |
| `kIsolateSnapshotData`<br>`kIsolateSnapshotInstructions` | `isolate_snapshot_data_linkable`<br>`isolate_snapshot_instructions_linkable` | AOT product loaders (`dart`, `dartaotruntime`) | `gen_snapshot --snapshot_kind=app-aot-blobs` | AOT isolate snapshot containing program-specific metadata and compiled application code. |

---

## JIT vs AOT Snapshot Routing

The executable a developer is building (`dartvm` vs AOT tools) determines **which subset** of these linkable targets are populated with real data:

1. **JIT Mode (`dartvm`)**:
   - Consumes the **Core Snapshot** (`kDartCoreSnapshotData`/`kDartCoreSnapshotText`).
   - When the JIT VM boots, it expects these symbols to point to valid bootstrapped snapshot data.
   - AOT snapshot symbols (`kDartVmSnapshotData`, `kIsolateSnapshotData`, etc.) are not used.

2. **AOT Mode (`dart`, `dartaotruntime`)**:
   - Consumes the **AOT VM** and **Isolate Snapshots** (`kDartVmSnapshotData`, `kIsolateSnapshotInstructions`, etc.) to run pre-compiled AOT applications.
   - In AOT-mode builds, the JIT core snapshot symbols are unused.

### The Role of `snapshot_empty.cc`

To avoid duplicate symbol errors and reduce binary size, the build system uses `snapshot_empty.cc` as a fallback helper:
- In JIT builds (`dartvm`), we compile and link real generated assembly files (containing the binary snapshot bytes).
- In AOT builds (`dart` or `dartaotruntime`), the build system links `snapshot_empty.cc` instead of the real JIT core snapshot linkables.
- `snapshot_empty.cc` defines `kDartCoreSnapshotData` and `kDartCoreSnapshotText` as `nullptr` with size `0`. This satisfies the linker's dependency requirements without bundling unused JIT bootstrap bytes into the AOT binary.

---

## Other Embeddings (`.dill` Files)

In addition to the three `gen_snapshot`-produced families, `runtime/bin` also embeds some raw Kernel bytecode files using the same `bin_to_linkable` mechanism:

- `kKernelServiceDill` (`kernel_service_dill_linkable`): Contains the Common Front-End (CFE) `kernel-service.dill` compiler bytecode, embedded directly to let the VM run compilation tasks.
- `kPlatformDill` (`platform_dill_linkable`): Contains the core library platform outline/bytecode (`vm_platform.dill`), used to resolve SDK libraries during compilation.

These targets wrap compiled `.dill` files directly from the compiler and do not pass through the `gen_snapshot` utility.

---

## Command Reference

The authoritative reference on how snapshots are laid out is the `gen_snapshot` tool itself. You can inspect all supported snapshot kinds by running:

```bash
gen_snapshot --help
```

Refer to the `--snapshot_kind` flag options:
- `core`: Standard JIT VM bootstrap snapshot.
- `vm-aot`: AOT VM-wide shared heap snapshot.
- `app-aot-blobs`: Application-specific AOT data + instructions.
