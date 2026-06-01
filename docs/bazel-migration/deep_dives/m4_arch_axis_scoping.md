# M4 arch axis — scoping spike (x64↔arm64, cross-compile)

> **Not an `issue_NNNNN` file.** This is a design/scoping note for the **arch
> sub-axis of M4** (multi-config `select()`) — the third and highest-difficulty
> of M4's sub-axes (debug↔release → product → **arch** → Bzlmod). It is the
> sibling of `m4_multiconfig_scoping.md` (the debug↔release recon) and mirrors its
> method; read that one first. See `STATUS.md` for where the migration stands.
>
> Status: **recon only.** No `select()` / `config_setting` / cross-toolchain /
> `--platforms` was added; no `BUILD.bazel` was rewired. Output is the measured
> `ReleaseX64`-vs-`ReleaseARM64` `gn desc` delta over the runtime slice, the
> Bazel cross-compile requirements, and — the headline — an **empirical re-test of
> the "cross-arch `gen_snapshot` is compile-RED" claim** that gates the `create_sdk`
> assembly (`sdk-uk2`). _Written: 2026-05-31 (session 34)._

## 0. TL;DR (the two findings that matter)

1. **There are two different "arch" mechanisms, routinely conflated.** **Axis A**
   is a *true cross-compile*: retarget the whole build to **run on** an arm64
   device (the `ReleaseX64`→`ReleaseARM64` out-dir flip). **Axis B** is a host-x64
   binary that **emits** arm64 code (`gen_snapshot_product_linux_arm64`) — the Dart
   VM selects its *target* architecture by C++ **macro** (`TARGET_ARCH_ARM64`),
   **not** by the compiler's target triple, so a host-x64 clang compiles arm64
   codegen perfectly well. **`create_sdk` needs only Axis B**, not Axis A.

2. **The documented "Known red" — cross-arch `gen_snapshot_*_linux_{arm,arm64,riscv64}`
   is compile-RED with `use of undeclared identifier 'R31'` — is STALE. The whole
   cluster is GREEN on the current tree** (verified: all three executables build,
   136 real sandbox compile/link actions, RC=0, real `x86-64` ELF binaries). The
   `TARGET_ARCH_*` define *is* threaded now (the sess 23–28 overlay/define-rework
   post-dates the original RED note). So **the arch axis is not what gates
   `create_sdk`** — the aggregator `cc_library`→`filegroup` conversion + the
   `dart-sdk/` rooting decision are (exactly as `STATUS.md` already says).

## 1. Why this recon

`m4_multiconfig_scoping.md` sequenced M4's sub-axes and put **arch last** as "the
high-value, high-difficulty axis the known-red items demand
(`gen_snapshot_*_linux_{arm,arm64,riscv64}` need `TARGET_ARCH_*` + `-march` +
**cross-toolchains**, and the target set itself changes)." The debug↔release and
product axes are now landed. This spike does for arch what that note did for
debug↔release: **before any `select()`/toolchain is written, measure exactly what a
second arch changes** — and, because `sdk-uk2` is blocked on a cluster the tracker
calls cross-arch-RED, **re-test that claim empirically** rather than trust the note.

## 2. Method (reproducible)

Same `gn`/`gn desc` method as the debug↔release recon (§2 there). The second
config already existed in the tree (`out/ReleaseARM64`), generated the standard
Dart way (`tools/gn.py --mode=release --arch=arm64 -nvh -ngv`). The two `args.gn`
files are **byte-identical except the two arch lines** — so the only difference
between the descs is the x64↔arm64 axis, not the migration's sdk-hash plumbing:

```
$ diff out/ReleaseX64/args.gn out/ReleaseARM64/args.gn
< target_cpu = "x64"          > target_cpu = "arm64"
< dart_target_arch = "x64"    > dart_target_arch = "arm64"
```

Note `host_cpu = "x64"` in **both** — `ReleaseARM64` is a genuine **cross-compile**
(host x64, target arm64), not a native arm64 build.

```bash
buildtools/gn desc out/ReleaseX64   '//*' --format=json > x64.json     # 2 752 518 B
buildtools/gn desc out/ReleaseARM64 '//*' --format=json > arm64.json   # 3 150 104 B
```

The x64 desc is **byte-identical** to the figure `m4_multiconfig_scoping.md` §5
recorded (2 752 518 B) — confirms `gn desc` determinism and that the live
`ReleaseX64` config is unchanged. The **slice** compared is the same as the
debug↔release recon: default-toolchain targets under `//runtime/vm` + `//runtime/bin`.
Fields diffed = what the translator consumes (`cflags`→copts, `cflags_c`→conlyopts,
`cflags_cc`→cxxopts, `defines`, `include_dirs`, `deps`, `libs`+`ldflags`→linkopts)
plus `asmflags` and the GN `configs` list. The RED re-test (§4) used `bazel aquery`
(static, no execution) for the compile flags and a real `bazel build` for the
verdict; `tools/bazel/out_of_band/restore.sh` was run first (it reported the tree
already fully in place — no staged-artifact change).

## 3. Axis A — the out-dir flip (`ReleaseX64`↔`ReleaseARM64`), runtime slice

**Census.** The runtime slice is **141 default-toolchain targets, the identical set
in both configs** (0 added, 0 dropped, every target type unchanged) — same as
debug↔release. The arch flip moves the *graph* elsewhere: cross-toolchain `(...)`
labels grow **201 → 281 (+80)** and default-toolchain labels shrink **606 → 596
(−10)** across the whole desc (§5 explains the +80).

**The per-field flag delta over the 141 common targets:**

| Field | `ReleaseX64` has | `ReleaseARM64` has | # targets | What `select()`/toolchain must model |
|---|---|---|---|---|
| `cflags` (copts) | `--target=x86_64-linux-gnu`, `-march=x86-64`, `-m64`, `-msse2` | `--target=aarch64-linux-gnu` | 123 | target triple + ISA swap |
| `asmflags` | `--target=x86_64-linux-gnu`, `-march=x86-64`, `-m64`, `-msse2` | `--target=aarch64-linux-gnu` | 123 | **same swap on asm** — debug↔release had ZERO asmflags delta |
| `ldflags` (linkopts) | `--target=x86_64-linux-gnu`, `-m64` | `--target=aarch64-linux-gnu`, `-Wl,--fix-cortex-a53-843419` | 123 | triple + the ARM Cortex‑A53 erratum link fix |
| `defines` | `TARGET_ARCH_X64` | `TARGET_ARCH_ARM64` | 54 | **one define flip**, single uniform signature |
| `deps` | `…:gen_snapshot`, FFI `.so`(`clang_x64_shared`) | `…:gen_snapshot(clang_x64)`, FFI `.so`(`clang_arm64_shared`) | 8 | **cross-toolchain `(...)` deps** — the host/target split (§5) |
| `include_dirs` | `//out/ReleaseX64/gen/…` | `//out/ReleaseARM64/gen/…` | 0\* | cosmetic out-dir token; translator already drops `//out/*` |
| `cflags_c`, `cflags_cc`, `libs` | — | — | 0 | no delta |
| `--sysroot` | `../../buildtools/sysroot/linux` | `../../buildtools/sysroot/linux` | 0 | **same multiarch debian sysroot — NOT a delta** |
| target set | 141 | 141 | 0 | no delta |

\*after normalizing the `//out/*` path token, exactly as the translator does.

**Headline:** the arch delta is **bigger than debug↔release but still uniform and
config-driven** — ~7 distinct flag tokens on 123 targets (1 arm triple + the cortex
link fix on the arm side; the x64 triple + `-march=x86-64`/`-m64`/`-msse2` on the
x64 side) plus the `TARGET_ARCH_X64`→`ARM64` define on 54 targets, one signature, no
graph change in the slice. Two things debug↔release did **not** have:
- **`asmflags` moves** (123 targets) — the assembler needs the target triple too.
- **`deps` reference cross-toolchain `(...)` labels** (8 targets) — the host/target
  split (gen_snapshot built with the host `clang_x64`; FFI test `.so`s with
  `clang_arm64_shared`). This is the structural piece §5 unpacks.

**The sysroot does NOT change** — GN points both arches at the one
`buildtools/sysroot/linux` multiarch debian sysroot. Only the `--target=` triple,
the ISA flags, and the cortex link fix move. This materially shrinks what a cross
`cc_toolchain` must provide (no second sysroot to vendor).

**Origin (the `configs` field is byte-identical between the two descs).** The same
GN configs resolve different flags off `target_cpu`/`dart_target_arch`:
- `//runtime:dart_arch_config` (`runtime/BUILD.gn:177`) → the `TARGET_ARCH_*` define.
- `//build/config/compiler:compiler` (`build/config/compiler/BUILD.gn`) → the triple
  (`:345` aarch64 / `:354` x86_64), the x64 ISA (`-march=x86-64`/`-msse2`, `:263–270`),
  and the cortex link fix (`-Wl,--fix-cortex-a53-843419`, `:114`).

## 4. Axis B — the cross-arch cluster *inside* one out-dir, and the RED re-test

A normal **`ReleaseX64`** build contains, on the **default toolchain**, host-x64
`gen_snapshot` executables that target *other* architectures:

```
//runtime/bin:gen_snapshot_product_linux_{x64,arm,arm64,riscv64}   [executable]
```

Each is an `ELF … x86-64` binary (runs on the x64 host) compiled with **host x64
flags** (`--target=x86_64-linux-gnu`, `-march=x86-64`) but a **foreign**
`-DTARGET_ARCH_<arch>` + `-DDART_TARGET_OS_LINUX`. They exist so an x64 host can AOT
a Dart program *for* arm/arm64/riscv64. The arch is selected **purely by the C++
macro, never by the compiler triple** — which is the whole reason no cross-toolchain
is needed to build them.

Underneath, GN builds a **per-arch variant library closure**: e.g.
`libdart_{vm,compiler}_precompiler_product_linux_arm64`,
`libdart_{builtin,precompiler}_product_linux_arm64`,
`libdart_platform_precompiler_product_linux_arm64` — each recompiling the arch
sources (`assembler_arm64.cc`, `constants_arm64.cc`, `disassembler_arm64.cc`, …)
with the matching `TARGET_ARCH_ARM64` define. The base x64 libraries list those
same files but compile them as **no-op TUs** (each body is `#if
defined(TARGET_ARCH_ARM64)`-guarded; `R31` lives at `runtime/vm/constants_arm64.h:66`).

**The RED re-test (the reason this recon exists).** `STATUS.md`'s *Known red*
section and prior session notes say this cluster is compile-RED — "host x64 clang
**without `TARGET_ARCH_*` threaded** → `use of undeclared identifier 'R31'`." That
is **no longer true.** Three empirical checks:

- **`aquery` (static).** `//runtime/vm:libdart_compiler_precompiler_product_linux_arm64`
  compiles `assembler_arm64.cc` with **`-DTARGET_ARCH_ARM64`** present (+ host x64
  triple). The base `…_product` variant compiles the same file with
  `-DTARGET_ARCH_X64`. The define **is** threaded — the documented root cause is stale.
- **`bazel build` (real).** All three —
  `//runtime/bin:gen_snapshot_product_linux_{arm,arm64,riscv64}` — build
  **GREEN** with `--keep_going` (RC=0; **136 real `linux-sandbox` compile/link
  processes**, 1628 cache hits; outputs are real `ELF 64-bit … x86-64 pie`
  binaries). The historically-cited `//runtime:libdart_precompiler_product_linux_arm`
  (the "`//:most` fails only on this" leaf) and the riscv64 variant also build GREEN.
- **Not cache-masking.** The 136 fresh sandbox actions in that build *are* genuine
  arm/arm64/riscv64 TU compiles + links that had never succeeded before (only the
  one arm64 compiler lib was pre-cached); they completed with zero `error:`/`R31`.

**Conclusion:** the macro-based cross-arch `gen_snapshot` cluster is **green under
the single host toolchain** — Axis B needs *no* cross-toolchain at all. The sess
23–28 work that flowed `TARGET_ARCH_*`/`local_defines` through the runtime targets
incidentally fixed the original RED. **`STATUS.md`'s *Known red* bullet and the M4
row's "cross-arch `gen_snapshot` confirmed red" line are corrected in this commit.**

**Relationship to `create_sdk` (`sdk-uk2`).** GN adds these as deps purely *"so
that they are built"* — it explicitly does **not** copy cross-compilation
`gen_snapshot` binaries into the SDK on a 64-bit host (`sdk/BUILD.gn:965–972`).
Bazel's `create_full_sdk` already lists all four as `deps`
(`sdk/BUILD.bazel:607–610`), and they build. So **the arch cluster does not block
the assembly.** What blocks it is unchanged: `create_full_sdk` is still a
`cc_library` depending on `filegroup`s (no `CcInfo`) — the aggregator→`filegroup`
conversion — plus the `dart-sdk/` rooting collision. Both are tracked on `sdk-uk2`.

## 5. Cross-compile needs in Bazel (today's one toolchain → Axis A)

Today the migration has exactly **one** registered C++ toolchain — the host x64
clang repo `@+dart_clang+dart_linux_x64_clang` (seen in every `aquery` action's
inputs) — and **no `--platforms`/`constraint_values`** beyond the default. That is
sufficient for **everything `create_sdk` needs**, because both the host binaries and
the macro-selected cross-arch `gen_snapshot`s (Axis B) are *host* x64 compiles.

**Axis B (build a host binary that emits foreign-arch code): already satisfied.**
No cross `cc_toolchain`, no platform. The VM's `TARGET_ARCH_*` macro does the work;
`select()`-on-arch is not even required for the variant libraries because GN
pre-expands them into distinct named targets the translator already emits with the
right define.

**Axis A (build the runtime to *run on* an arm64 device): not started, and not on
the `create_sdk` critical path.** What it needs, read straight off the §3 delta and
the §3-census cross-toolchain growth:

- **A target platform + constraints.** A `platform` (e.g. `//build/platforms:linux_arm64`)
  with `constraint_values = ["@platforms//cpu:aarch64", "@platforms//os:linux"]`,
  selected via `--platforms`.
- **A cross `cc_toolchain`.** An aarch64 clang toolchain: swap the triple to
  `--target=aarch64-linux-gnu`, drop the x64 ISA flags, add `-Wl,--fix-cortex-a53-843419`,
  and **reuse the existing `buildtools/sysroot/linux` multiarch sysroot** (§3 — no new
  sysroot needed). Register it with `toolchain()` + a `config_setting`/constraint so
  Bazel's toolchain resolution picks it under `--platforms=…:linux_arm64`.
- **The host/target split — Bazel-native, not GN-manual.** The §3-census `+80
  clang_x64` labels that appear *only* in the arm64 desc (with the matching −10
  default-toolchain drop) are GN's manually-spelled **host-toolchain** instances of
  the build-time tools — gen_snapshot and its source-set/dep closure, plus other
  host helpers — that must run on the host while the target is arm64 (in the x64
  build, host==target, so they sit on the default toolchain — hence 0 explicit
  `clang_x64` there). In Bazel this is the **exec transition**: host tools build automatically in
  the exec configuration (the x64 toolchain) while target libraries build for the
  target platform. Bazel models this natively; we do **not** port GN's explicit
  `(//build/toolchain/linux:clang_x64)` dep labels — they collapse into exec deps.
- **The flag delta itself.** Once the triple/ISA/cortex flags live in the cross
  `cc_toolchain` (keyed on the target CPU constraint) and `TARGET_ARCH_ARM64` rides a
  platform-keyed `config_setting` `select()` (or a constraint-derived `local_defines`),
  the 141-target slice needs **no per-target `select()`** — the delta is fully
  carried by toolchain + one arch `config_setting`, mirroring how debug↔release folded
  to one shared carrier.

The §3-census sanitizer/shared labels (`clang_{x64→arm64}_{asan,msan,shared,tsan}`,
identical 45/48/60/48 counts on both sides) are the *target-arch* sanitizer
toolchains — they rename with the axis and are a later concern (sanitizers are §7
out-of-scope today; the migration is single-config there).

## 6. Recommended sequencing + first mechanism-proof

The arch axis splits cleanly along §0's two mechanisms, and they have **opposite
priority** to their difficulty:

1. **Axis B — already green; just consume it.** The highest-value, lowest-effort
   arch work is *not* new arch machinery — it is letting `create_sdk` consume the
   already-green cross-arch `gen_snapshot`s, which only needs the `sdk-uk2`
   aggregator→`filegroup` + `dart-sdk/` rooting fixes (not arch work at all). No
   mechanism-proof needed; the mechanism already runs in production.

2. **Axis A — the real cross-compile, the deferred high-difficulty axis.** When it
   is scheduled, prove it the same way sess 22 proved debug↔release: a **single
   graph-isolated leaf**, not the whole VM. Stand up one aarch64 cross `cc_toolchain`
   + a `linux_arm64` platform, then `bazel build --platforms=…:linux_arm64` **one**
   small target (e.g. `//runtime/platform:libdart_platform` or a probe `cc_library`)
   and confirm via `aquery` that its compile carries `--target=aarch64-linux-gnu` +
   `TARGET_ARCH_ARM64` and links. Only after that one-target proof, widen to the
   runtime slice and rely on the exec transition for host tools. This is lower
   priority than `create_sdk` because **nothing the SDK assembly ships needs Axis A**
   — it ships host-x64 binaries + the macro-selected cross `gen_snapshot`s.

**Net:** the arch axis is *much* further along than the tracker implied. Its
create_sdk-relevant half (B) is done; its remaining half (A, true cross-compile) is
a bounded, well-understood port — one platform, one cross toolchain, no new sysroot,
the exec transition for host/target — to be done when an arm64-host SDK is actually a
goal, not as a `create_sdk` precondition.

## 7. What this recon did NOT cover

- **Axis A implementation** — no platform, `constraint_values`, cross `cc_toolchain`,
  or `select()` was added. This is the recon that precedes it.
- **Running the cross `gen_snapshot`s.** They build and are real x86-64 ELF; this
  recon did **not** invoke them to emit an actual arm64 AOT snapshot and run it on
  arm64 hardware/QEMU. Compile/link greenness is the claim, not end-to-end execution.
- **OS axis and `riscv32`/`ia32`.** Only linux x64↔arm64 was diffed; the
  `*_linux_{arm,riscv64}` variants were build-tested but not desc-diffed field by
  field. Cross-OS (android/fuchsia/ios/macos/win) `run_ffi_unit_tests_*` targets are a
  separate (cross-OS) axis and out of scope.
- **Sanitizer/shared target-arch toolchains** (the renamed `clang_arm64_{asan,…}`
  labels) — single-config today; a later axis.
- **The `create_sdk` aggregator/rooting fixes** — those are `sdk-uk2`, not arch work;
  this recon only establishes that arch does *not* gate them.

## 8. Related

- `m4_multiconfig_scoping.md` — the sibling debug↔release recon this mirrors; its §6
  sequenced arch as sub-axis #3 and its §8 deferred it here.
- `STATUS.md` — overall tracker; this is the "M4 — multi-config `select()`" arch
  sub-axis. Its *Known red* cross-arch `gen_snapshot` bullet and the Phase-2b/M4
  arch lines are corrected in the same commit as this doc.
- `rules_dart_scoping.md` — the deps-graph scoping note; unaffected by arch.
- `build/config/compiler/BUILD.gn` (triple/ISA/cortex origin) + `runtime/BUILD.gn`
  `:dart_arch_config` (the `TARGET_ARCH_*` define origin).
- `sdk/BUILD.gn:965–972` / `sdk/BUILD.bazel:607–610` — where the cross-arch
  `gen_snapshot`s attach to the SDK assembly ("built, not copied" on a 64-bit host).
