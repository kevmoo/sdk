# rules_dart — scoping spike

> **Not an `issue_NNNNN` file.** This is a design/scoping note for the single
> largest unstarted milestone of the Bazel migration: the Dart-compilation rule
> set (`rules_dart`) that gates all of Phase 2a/2b in `DESIGN.md` §4.2. See
> `STATUS.md` in this directory for where the migration stands overall.
>
> Status: **scoping only.** No rules built yet. Output is a sequenced plan + a
> concrete first-proof target + the open decisions that need an answer before
> implementation.
>
> _Written: 2026-05-28 (session 11)._

## 1. Why this is the gating rock

Everything in `runtime/` (C++) is buildable in Bazel today. Everything in
`utils/` and `sdk/` is **not**, because those subtrees compile *Dart* into
snapshots, and Bazel has no rule that knows how to do that. `DESIGN.md` §4.3 is
blunt: this is the precondition that stalled Flutter's Bazel adoption for 7+
years (`flutter/flutter#58082`, open since 2020). The plan says solve it *as a
precondition, not during* the migration. This spike de-risks it early rather
than discovering its true size at the end.

## 2. What the SDK does today (the surface rules_dart must replicate)

All Dart-to-artifact compilation funnels through a small set of GN templates:

| Template | File | What it produces |
|---|---|---|
| `application_snapshot()` | `utils/application_snapshot.gni:55` | app-jit or kernel `.dart.snapshot` (2-stage: kernel compile → JIT train) |
| `aot_snapshot()` | `utils/aot_snapshot.gni:11` | AOT `.snapshot` (ELF/Mach-O) (2-stage: kernel compile → `gen_snapshot`) |
| `compile_platform()` | `utils/compile_platform.gni:10` | platform `.dill` (dart:core kernel) for VM/DDC/dart2js/dart2wasm |
| `dart_action()` | `build/dart/dart_action.gni:350` | runs in-progress `dartvm` on a script (only when exact VM compat matters) |
| `gen_snapshot_action()` | `build/dart/dart_action.gni:409` | runs in-progress `gen_snapshot`: dill → AOT snapshot |
| `prebuilt_dart_action()` | `build/dart/dart_action.gni:198` | runs the **prebuilt** `tools/sdks/dart-sdk/bin/dart` on a script |

The whole of `utils/*/BUILD.gn` is a thin layer over `aot_snapshot` /
`application_snapshot`: dartdev, analysis_server, ddc, dart2js, dart2wasm, dds,
dtd, gen_kernel, kernel-service, dart_mcp_server, etc. — each tool is 1–3
snapshot targets plus (for the web compilers) a `compile_platform()`.

### The bootstrap chain (how Dart-builds-Dart avoids a cycle)

```
tools/sdks/dart-sdk/  (CIPD-pinned prebuilt SDK — hermetic input)
        │  prebuilt_dart_action runs prebuilt `dart` on pkg/vm/bin/gen_kernel.dart
        ▼
bootstrap_gen_kernel.dill   (utils/gen_kernel/BUILD.gn:11)
        │  prebuilt `dart` runs this dill to compile any tool's Dart → app.dill
        ▼
<tool>.dill   ──►  gen_snapshot (in-progress, ALREADY a green Bazel target)  ──►  <tool>.aot.snapshot
```

Key consequence for sequencing: **the kernel-compile stage needs only the
prebuilt SDK** (a CIPD-pinned, hermetic directory) plus `bootstrap_gen_kernel.dill`,
`vm_platform.dill`, `.dart_tool/package_config.json`, and the tool's sources. The
AOT stage needs `gen_snapshot`, which sessions 7–9 already made green. **Both
building blocks exist today.** What's missing is the rule glue.

## 3. What exists on the Bazel side today: nothing real

The translator emits empty stubs for every one of these targets, e.g. in
`utils/bazel/BUILD.bazel`:

```python
# TODO(M3): genrule for kernel_worker_aot_dill (gn type=action)
cc_library(name = "kernel_worker_aot_dill")
# TODO(M3): genrule for kernel_worker_aot_gen_snapshot (gn type=action)
cc_library(name = "kernel_worker_aot_gen_snapshot")
# TODO(M3): copy for kernel_worker_aot (gn type=copy)
cc_library(name = "kernel_worker_aot")
```

So `gn type=action`/`type=copy` Dart targets all become no-op `cc_library`
placeholders. Confirmed greenfield — `DESIGN.md` §3.1/§3.5 already verified there
are zero `.bzl`/`BUILD.bazel`/`MODULE.bazel` Dart rules anywhere in the tree
(the lone `pkg/analyzer_cli/test/data/blaze/WORKSPACE` is a 0-byte analyzer
fixture).

## 4. Ecosystem reality — can't borrow, must own

All four known `rules_dart` forks are **archived** (`DESIGN.md` §3.1, verified):
`dart-archive/bazel`, `dart-archive/rules_dart`, `cbracken/rules_dart`
(archived 2025-06), `matanlurey/rules_dart` (archived 2024-09). Combined they
cover `dart_library` / `dart_vm_binary` / `dart_vm_snapshot` / `dart_vm_test` /
web rules — but **none covers AOT** (`gen_snapshot`, `dartaotruntime`), which is
exactly what the SDK's own tools need. So: author from near-scratch, or
fork-and-revive cbracken and design the AOT rules from zero.

## 5. The compatibility contract that must not break

`utils/bazel/kernel_worker.dart` ships as
`<SDK>/bin/snapshots/kernel_worker_aot_product.dart.snapshot`, invoked by
**external** Bazel users (Google-internal `rules_dart`, `dart-lang/build`) as
`dartaotruntime <snapshot> --persistent_worker` (`DESIGN.md` §3.5, sdk-edw). The
SDK's Bazel build **must keep producing this snapshot at the same path with the
same CLI**. Conveniently, this also makes it the ideal *first* port — the new
rule's output can be diffed byte-for-byte against the GN-produced snapshot.
(DDC's `--bazel_worker` entry in `pkg/dev_compiler/lib/ddc.dart` may be a second
instance of the same contract — not yet audited.)

## 6. What rules are actually needed (decomposition)

Minimum viable set, in dependency order:

1. **`dart_kernel`** — run prebuilt `dart` + `bootstrap_gen_kernel.dill` over a
   main Dart file + its package closure → `.dill`. (Replaces the `*_dill` action
   stage.) Inputs: prebuilt SDK, bootstrap dill, `vm_platform.dill`,
   `package_config.json`, srcs. Pure "run a hermetic binary on files" — closest
   to a `genrule`/small custom rule.
2. **`dart_aot_snapshot`** — run the Bazel-built `gen_snapshot` over a `.dill` →
   AOT `.snapshot` (ELF). (Replaces the `*_gen_snapshot` stage.) `gen_snapshot`
   already green.
3. **`dart_library`** — a `DartLibraryInfo` provider carrying transitive srcs +
   the package-name→path mapping, so `dart_kernel` gets a real dep graph instead
   of one giant filegroup. (This is the difference between Bazel-incremental and
   "opaque blob" — see §7 open decision.)
4. **`compile_platform`** — produce `vm_platform.dill` etc. from
   `sdk/lib/libraries.json` via prebuilt `compile_platform.dart`. Needed before
   #1 can run for real, but is itself just another prebuilt-dart invocation.
5. **`dart_app_jit_snapshot`** — the `application_snapshot` analog (JIT + train
   via in-progress `dartvm`). Lower priority; AOT is what the shipped tools use.

`bootstrap_gen_kernel.dill` itself is `dart_kernel`'s bootstrap input and can be
produced by the same prebuilt-dart mechanism (or pre-staged, like the M5 blobs).

## 7. Open decisions (need an answer before building)

- **Greenfield vs revive cbracken's fork.** Greenfield = clean, Bzlmod/BCR-
  native, no inherited WORKSPACE machinery, but more upfront. Revive = faster to
  first `dart_library`/`dart_vm_binary`, but inherits WORKSPACE-era patterns and
  still needs AOT designed from zero. *Leaning greenfield* given Bazel 8+ makes
  Bzlmod default and the AOT rules (the hard part) can't be borrowed anyway.
- **Pubspec → deps model** (`DESIGN.md` §3.5, sdk-rsv):
  (a) gazelle-style generator that walks `pkg/*/pubspec.yaml` → per-package
  `BUILD.bazel`, or (b) opaque pub-workspace — one big filegroup of all
  `pkg/`+`third_party/pkg/`, mirroring today's GN. *Hybrid recommended:* opaque
  first (unblocks the first proof immediately), generator later (recovers
  incrementality). Don't block the spike's first proof on this.
- **Bzlmod vs WORKSPACE** — downstream of the greenfield/revive choice. If
  greenfield, target Bzlmod/BCR.

## 8. Proposed phased plan + concrete first proof

The bootstrap-is-hermetic insight (§2) means we can produce a *real* Dart
snapshot in Bazel **now**, without solving the deps model or the platform-dill
chicken-and-egg first. Sequenced so each step ships a verifiable artifact:

| Step | Deliverable | Verify |
|---|---|---|
| **0 (first proof)** — ✅ **DONE (session 11)** | `dart_kernel_snapshot` + `dart_aot_snapshot` macros in `//tools/bazel/dart:defs.bzl`; opaque-filegroup deps (`//:dart_package_sources`); bootstrap dill built in-Bazel (the checked-in blob was stale). Target: **`//utils/bazel:kernel_worker_aot_product_snapshot`**. | ✅ `bazel build` produces a 14M AOT ELF; runs under Bazel `dartaotruntime_product` (real CFE path: "No input file provided to the compiler"; `--persistent_worker` starts+exits clean). This is the §5 external contract. |
| 1 | `compile_platform` rule → produce `vm_platform.dill` in Bazel (drop the pre-stage). | Resulting `.dill` matches GN's. |
| 2 | `bootstrap_gen_kernel.dill` produced by a Bazel rule (drop that pre-stage). | dartvm/snapshots still byte-match. |
| 3 | `dart_library` provider + gazelle-style pubspec→deps generator (recover incrementality). | Touching one pkg rebuilds only its dependents. |
| 4 | Port the rest of `utils/` tool-by-tool (dartdev, analysis_server, ddc, dart2js, dart2wasm, dds, dtd, …). | Each tool's snapshot matches GN; `create_sdk` assembles. |
| 5 | `sdk/` assembly (Phase 2b) — mostly `copy`/`copy_tree` once snapshots exist. | `bazel build //sdk` produces a working SDK dir. |

Step 0 is the de-risking move: if a Bazel rule can produce the kernel_worker
snapshot and it matches GN, the entire approach is validated and the rest is
breadth.

### Step 0 result (session 11) — validated

`bazel build //utils/bazel:kernel_worker_aot_product_snapshot` works end-to-end
and the output runs under the Bazel-built `dartaotruntime_product`. What we
learned doing it:

- **Opaque deps via filegroup works hermetically.** `//:dart_package_sources` =
  `glob(["pkg/**/*.dart", "third_party/pkg/**/*.dart"]) + package_config.json`,
  globbed from the root package (neither subtree has a sub-`BUILD.bazel`). The
  kernel compile ran clean in `linux-sandbox` with only that + the prebuilt SDK
  tree + the platform/bootstrap dills declared. No undeclared-input failures.
- **The checked-in `bootstrap_gen_kernel.dill` was stale** (kernel format v127;
  current prebuilt dart emits v130) — risk #1 below, hit immediately. Fixed by
  building it in-Bazel from the prebuilt SDK (`dart_kernel_snapshot`), so it
  never goes stale. Pre-staging would have re-introduced the trap.
- **Exec-config `gen_snapshot_product` compiled cleanly** as a genrule `tool` —
  the zlib strict-C++ exec-config failure noted in earlier sessions did *not*
  recur (the `-x c` toolchain feature now covers it). This unblocks the
  "gen_snapshot as a Bazel tool" path that M5 had punted on.
- **One out-of-band file added:** `tools/sdks/dart-sdk/BUILD.bazel` (the prebuilt
  SDK dir is CIPD-managed / gitignored). Captured in `out_of_band/restore.sh`.
- **Not yet done:** byte-for-byte diff vs GN (the on-disk GN artifact predates
  the sdk_hash flip, so a clean comparison needs a fresh GN build with
  `0000000000`); behavioral equivalence is established.

## 9. Effort estimate (low confidence — flagged honestly)

- **Step 0 (first proof):** small — days, not weeks. Both building blocks exist;
  this is rule plumbing + getting the prebuilt-dart invocation's args exactly
  right (the GN templates spell them out). *Medium-high* confidence.
- **Steps 1–3 (platform dill, bootstrap, deps model):** medium. The deps
  generator is the wildcard — could be a week, could be more if the path-override
  map in root `pubspec.yaml` has surprises. *Medium* confidence.
- **Steps 4–5 (all of utils/ + sdk/):** large. ~15 tools × per-tool quirks
  (training args, platform variants, product-mode alignment). *Low* confidence —
  this is the bulk of Phase 2.
- **Whole milestone:** plausibly comparable in size to everything done in
  sessions 1–10 combined. `DESIGN.md`'s scout *declined* to estimate this and
  flagged it the biggest scope item — I'm not going to pretend to a number I
  can't defend. The reliable claim is the *ordering* and that **Step 0 is
  achievable now and proves the riskiest assumption cheaply.**

## 10. Risks

- **Prebuilt-SDK version skew.** The kernel-compile stage uses the CIPD-pinned
  prebuilt `dart`; if it's too old to parse current SDK source, kernel compiles
  fail (already bitten us — see `STATUS.md` "known red", record_use/sdk_hash).
  Mitigate by enforcing the DEPS pin via `out_of_band/restore.sh` or a Bazel
  `repository_rule` that runs `cipd ensure`.
- **sdk_hash discipline** carries over: snapshots must be built with matching
  `-Dsdk_hash` or the VM rejects them (`STATUS.md`). The rules must thread this.
- **Persistent-worker protocol** is a runtime contract of the *shipped snapshot*,
  not of the build rules — so porting the build shouldn't touch it, but the
  output path/name must be preserved exactly (§5).
- **Deps model lock-in.** Picking the opaque model for the first proof is fine,
  but shipping it as the final answer loses Bazel's incrementality. Treat opaque
  as scaffolding, not the destination.

## 11. Related

- `STATUS.md` — overall migration tracker (this milestone is "Phase 2a, blocked").
- `DESIGN.md` §3.1 (rules_dart ecosystem), §3.5 (test integration + worker
  contract + deps model), §4.2 (phase ordering), §4.3 (the Flutter cautionary
  tale).
- `issue_00003_make_version_py_hermeticity.md` — sdk_hash/version stamping, which
  the snapshot rules must respect.
