# Bazel migration — status

> **Not an `issue_NNNNN` file.** This is the living progress tracker for the
> GN+Ninja → Bazel migration on branch `kevmoo/bazel-m1-cc-toolchain`. It lives
> here because `docs/todo_issues/` is where this work stream keeps its durable,
> reviewable artifacts. The `issue_*.md` files are *discovered SDK improvements*;
> this file is *where the migration itself stands*.
>
> **Keep this current.** Update it at the end of any session that changes the
> migration's state — same discipline as filing an `issue_*.md`. The plan of
> record is `DESIGN.md` (§4.1 molecules, §4.2 phases); this doc maps progress
> onto it.

_Last updated: 2026-05-29 (session 18) — Ported the **`frontend_server` + `kernel-service` app-jit snapshots** (`application_snapshot("frontend_server")` / `application_snapshot("kernel-service_snapshot")`), the last clean app-jit tools in the `utils/` seam. The "staged platform dill in the training cwd" open question resolved cleanly: GN colocates `vm_platform.dill` next to the built `dart` so the tools find it via `computePlatformBinariesLocation()`, but in Bazel `dartvm` is NOT colocated — so the platform is passed **explicitly** through each tool's existing arg surface. `kernel_service.dart --train <script> [platform]` takes an optional 2nd positional platform path (resolved via `Uri.base.resolveUri(Uri.file(...))` against the execroot) → pass `$(location //runtime/vm:vm_platform.dill)`. `frontend_server --train` re-parses `--sdk-root`/`--platform` and does `sdkRoot.resolve(Uri.file(platform))` → `--sdk-root=.` (execroot = `Uri.base`) + `--platform=$(location ...)` (execroot-relative) land on the right file. Both reuse the session-15 `training_srcs` param (vm_platform.dill + the main entry) so `$(location)` resolves in the stage-2 training genrule; no macro change needed. Verified by the session-14 method (rebuild GN stage-1 dill from current sources + path-normalized dump-diff): **0-line semantic diff** — kernel-service 267 305 lines, frontend_server 302 958 (frontend_server's training did a real incremental compile/recompile-delta cycle, exactly GN). Both snapshots run; `//:runtime` clean (`//:most` fails only on the pre-existing cross-arch `libdart_precompiler_product_linux_arm`, unrelated); vm_platform still byte-identical. **The clean app-jit + AOT tool seam over `utils/` is now exhausted — NEXT is Step 3 (deps generator, wildcard).** app-jit tool count now **10** (dartanalyzer + 5 generate_* + dartdevc/dart2js + these 2). Session 17 — Ported the **`dartdevc` + `dart2js` app-jit snapshots** (`application_snapshot("dartdevc")` / `application_snapshot("dart2js")`), unblocked by the session-16 `compile_platform` web variants. Both training runs consume the in-Bazel platform/outline dills: dartdevc's run compiles dartdevc.dart with `--dart-sdk-summary=ddc_outline.dill` (the `:ddc_platform` outline, injected via `$(location)`); dart2js's run compiles memory_compiler.dart over the generated `dart2js.dart` entry with `--platform-binaries=$(RULEDIR)/` (where `:compile_dart2js_platform` emits `dart2js_platform.dill`/`dart2js_outline.dill`). Both verified by the session-14 method (rebuild GN dill from current sources + path-normalized dump-diff): **0-line semantic diff** — dartdevc 278 585 lines, dart2js 380 266 (the lone 2-line residual was the generated-entry wrapper's gen-dir path, location-dependent exactly as session 14 documented). Both snapshots run; `//:most`/`//:runtime` clean; vm_platform still byte-identical. app-jit tool count now **8** (dartanalyzer + the 5 generate_* + these 2). Session 16 — Ported **all 6 `compile_platform` web/wasm variants** (ddc_platform, compile_dart2js_platform, compile_dart2js_server_platform, compile_dart2wasm_platform, compile_dart2wasm_js_compatibility_platform, compile_dart2wasm_standalone_platform) by generalizing `dart_compile_platform` ADDITIVELY (new optional params platform_args/single_root_base/deps_outline/platform_out, all defaulting to the VM call → vm_platform.dill rebuild is a cache HIT, still cmp-identical to GN). **All 14 output dills (7 variants × platform+outline, incl. vm) are BYTE-IDENTICAL to a freshly-rebuilt GN** — the vm_platform gold standard, not merely semantic (canonical single-root URIs ⇒ location-independent). `//:dart2wasm_platform` now builds end-to-end; unblocks dartdevc + dart2js app-jit/AOT. Session 15 — Ported the **5 remaining clean app-jit `generate_*` variants** (the JIT-launcher snapshots that sit beside the session-12/13 AOT snapshots): dtd, dds, dartdev, dart_runtime_service_vm (all trivial main+training_args) and analysis_server. All verified by the session-14 method (rebuild GN dill from current sources + path-normalized dump-diff) → **0-line semantic diff** (dtd 42 077, dds 62 388, dartdev 743 919, drsv 67 670, analysis_server 527 792 lines); snapshots load/JIT-run. analysis_server forced a macro extension: `dart_app_jit_snapshot` gained a **`training_srcs`** param (ports GN training_inputs/training_deps) — its training run is a real analysis pass that reads sdk/lib/** + sdk/version outside the pkg/ closure, which the Bazel sandbox needs declared (also newly exported //sdk:version). app-jit tool count now **6** (these 5 + dartanalyzer). Remaining utils/ seam: dartdevc + dart2js (need compile_platform web variants), frontend_server + kernel-service (need a staged platform dill); kernel_worker app-jit skipped (deprecated, removable in 3.7, unreferenced). Session 14 — VERIFIED AOT-tool fidelity (closed the session-12 "ported snapshots unverified vs GN" risk): 4 of 10 AOT tools spot-checked, kernel dills SEMANTICALLY IDENTICAL; NEW `dart_app_jit_snapshot` macro + dartanalyzer (first app-jit tool). Session 13 — THE REFRESH (package_config regen + 16 Dart-pkg clone rolls to DEPS pins); ported 4 more AOT tools._

## TL;DR

A **deep vertical slice is done**: a Bazel-built `dartvm` runs a real `.dart`
program end-to-end on Linux x64 Release. The hard de-risking — "is gn-desc →
Bazel structurally sound?" — is answered yes. But the slice is one config, C++
only, with GN still the source of truth. The **breadth of the migration is
still ahead**, dominated by `rules_dart` (the precondition that stalled
Flutter's Bazel adoption for 7+ years), the full config/arch/OS matrix, and the
cutover machinery.

Rough effort estimate: **~15–25% complete.** Treat as order-of-magnitude, not
measured — DESIGN.md itself reports low confidence on total effort, with two
unmeasured unknowns (gn-gen latency per config, cflags stability across regens).
The reliable claim is the *ordering*: nothing in Phase 2+ moves until
`rules_dart` exists.

## The 5 molecules (first-proof plan — DESIGN.md §4.1)

| Molecule | Status | Notes |
|---|---|---|
| M1 — `cc_toolchain` port | ✅ Done | clang link driver, libc++ auto-link, `-x c` feature for clang 23 |
| M2 — translator skeleton | ✅ Done | `tools/bazel/translate_gn_desc.py`; still receiving bug fixes (sess 10: cc_binary `hdrs` fold) |
| M3 — gn dump + `libdart_vm_jit` green | ✅ Done | the original "first proof" |
| M4 — multi-config `select()` | 🔴 ~10% | still single-config `out/ReleaseX64`. No `select()` folding, no overlay for hand-edits |
| M5 — codegen / real blobs | ✅ Done (+Path-1.5) | all 4 blob symbols real; `dartvm` runs raw `.dart` source |

## The subtree phases (the actual migration — DESIGN.md §4.2)

| Phase | Subtree | Status | Detail |
|---|---|---|---|
| 0 | `build/toolchain/linux` | ✅ 100% | Bazel `cc_toolchain` port |
| 1a | `runtime/vm` core C++ | ✅ 100%¹ | `libdart_vm_jit` + 13 variants; ¹one config only |
| 1b | `runtime/bin` executables | ✅ ~90%¹ | `dart`, `dartvm`, `dartaotruntime`, `gen_snapshot` family, `run_vm_tests`, all 14 host cc_binaries, 3 FFI test `.so`s, 43 FFI unit tests pass |
| 1c | `runtime/platform`, observatory, … | 🟡 ~50% | platform done; observatory + remainder untouched |
| 2a | `utils/` — Dart-builds-Dart | 🟡 ~30% | `rules_dart` Steps 0–2 done + Step 4 broad: `dart_kernel_snapshot`+`dart_aot_snapshot`+`dart_compile_platform` macros (`//tools/bazel/dart`). Step 0 → `kernel_worker_aot_product`; Step 1 → `vm_platform.dill` in-Bazel (byte-identical to GN); Step 2 → `bootstrap_gen_kernel.dill` in-Bazel; **Step 4 → 10 AOT tools ported & running: dtd, dds, frontend_server, dart_mcp_server, ddc, dart2js + (session 13, after THE REFRESH) dart_runtime_service_vm, dartdev, dart2wasm, analysis_server.** The session-13 refresh (package_config regen + rolling all Dart-pkg clones to DEPS pins) cleared the out-of-band staleness that blocked the analyzer-stack tools. **Session 14 added a 4th macro `dart_app_jit_snapshot` (ports `application_snapshot.gni` — JIT VM training run via `//runtime/bin:dartvm`, not gen_snapshot) and ported `dartanalyzer` (first app-jit tool). Session 15 ported the 5 remaining clean app-jit `generate_*` variants (dtd, dds, dartdev, dart_runtime_service_vm, analysis_server; all 0-line dump-diff vs GN) and gave the macro a `training_srcs` param (ports GN training_inputs/training_deps) for analysis_server's real-analysis training run. app-jit tool count = 6.** **Session 16 ported all 6 `compile_platform` web/wasm variants** (ddc_platform, compile_dart2js{,_server}_platform, compile_dart2wasm{,_js_compatibility,_standalone}_platform) by generalizing `dart_compile_platform` additively — all 14 dills BYTE-IDENTICAL to GN, vm_platform untouched (cache hit). **Session 17 ported the `dartdevc` + `dart2js` app-jit snapshots** (consuming the session-16 ddc_outline.dill / dart2js_platform.dill via training_srcs; both 0-line dump-diff vs GN). **Session 18 ported the `frontend_server` + `kernel-service` app-jit snapshots** (platform passed explicitly through each tool's `--train`/`--sdk-root`/positional arg surface via `$(location)`, since Bazel's `dartvm` is not colocated with vm_platform.dill the way GN's built `dart` is; both 0-line dump-diff vs GN). **The clean app-jit + AOT tool seam over `utils/` is now exhausted** (app-jit tool count = 10); remaining utils/ work is the deps generator (Step 3). `kernel_worker` app-jit skipped (deprecated, removable in SDK 3.7, unreferenced). See `rules_dart_scoping.md`. |
| 2b | `sdk/` assembly | 🔴 0% | gated on 2a |
| 2c | `samples/` | 🟡 ~40% | all 20 `samples/embedder` + `ffi/http*` done; rest no |
| 3 | `third_party/` | 🟡 partial | icu/boringssl/perfetto/zlib/double-conversion hand-shimmed & working; BCR `bazel_dep` migration not done |
| Deferred | cross-arch, Android, Fuchsia, Windows, browser, emsdk | 🔴 0% | cross-arch `gen_snapshot` confirmed red (needs `select()`-on-arch + cross toolchains) |

## The three big rocks still ahead

1. **`rules_dart` — the single biggest scope item.** DESIGN.md §4.3: this is the
   precondition that stalled Flutter's Bazel adoption for 7+ years; the plan says
   solve it *as a precondition, not during* the migration. Gates all of Phase 2a
   and therefore 2b. Plausibly larger than everything done to date. **Scoped +
   Steps 0–2 done + Step 4 well underway (sessions 11–12) — see `rules_dart_scoping.md`.**
   The first proof (`kernel_worker_aot_product`, the external contract) builds and
   runs; `vm_platform.dill` + `bootstrap_gen_kernel.dill` are produced in-Bazel
   (the former byte-identical to GN); and **10 AOT tools** (dtd, dds,
   frontend_server, dart_mcp_server, ddc, dart2js + dart_runtime_service_vm,
   dartdev, dart2wasm, analysis_server) are ported and run. The session-13 refresh
   cleared the out-of-band staleness that blocked the analyzer-stack tools.
   Session 14 added the `dart_app_jit_snapshot` macro and ported `dartanalyzer`
   (first app-jit tool); **session 15 ported the 5 remaining clean app-jit
   `generate_*` variants (dtd, dds, dartdev, dart_runtime_service_vm,
   analysis_server) — 6 app-jit tools now, all 0-line dump-diff vs GN.**
   **Session 16 ported all 6 `compile_platform` web/wasm variants (additive
   `dart_compile_platform` generalization; all 14 dills byte-identical to GN,
   vm_platform untouched). Session 17 ported the `dartdevc` + `dart2js` app-jit
   snapshots (consuming those web-variant dills; 0-line dump-diff vs GN). Session 18
   ported the `frontend_server` + `kernel-service` app-jit snapshots — the last
   clean app-jit tools (platform staged via each tool's own `--train`/`--sdk-root`
   arg surface + `$(location)`; 0-line dump-diff vs GN). app-jit tool count = 10.**
   **The clean app-jit + AOT tool seam over `utils/` is now exhausted — remaining
   clean work is the deps generator (Step 3).**
2. **Multi-config + overlay (M4).** Single-config today, and every translator
   regen trashes the hand-edits — which is the entire reason
   `tools/bazel/out_of_band/restore.sh` exists. No `select()` folding and no
   overlay = can't scale to the arch/OS/product matrix, and stays maintenance-
   fragile.
3. **Cutover machinery (§4.3 + §3.6).** Test integration, swapping
   `tools/build.py`/`test.py` backends GN→Bazel behind the same CLI, and the
   atomic per-subtree GN deletion. None started — GN is still the source of truth.

## AOT tool snapshot fidelity (verified — session 14)

Closes the risk recorded at the session-12 gating decision: *"ported tool
snapshots are unverified vs GN (only `vm_platform` was diffed)."* Spot-checked
**4 of the 10** ported AOT tools, chosen to span the distinct rule paths:
`dtd` (plain), `dart2js` (generated entry via `make_version --no-git-hash`),
`dart2wasm_asserts` (`--enable-asserts` threaded to gen_kernel + gen_snapshot),
`analysis_server` (analyzer stack, post-refresh; `-Dbuilt_as_aot=true`).

**Method (the trap, and how to avoid it):** the GN artifacts staged in
`out/ReleaseX64` are dated **Feb 27 — pre-refresh**. `cmp`-ing fresh Bazel output
against them is invalid (input drift, not rule drift). The fair test is to
**rebuild the GN target from *current* sources via ninja** (delete the stale leaf
`*.dart.dill` + `*.snapshot` first; they're leaf outputs — `vm_platform`/blob
deps are upstream and untouched), then compare against Bazel built from the same
sources. Compare **semantically**: `tools/sdks/dart-sdk/bin/dart pkg/kernel/bin/dump.dart`
on both dills, normalize the absolute-path prefixes
(`/var/home/.../sdk/` and the Bazel `…/sandbox/linux-sandbox/N/execroot/_main/`
both → `ROOT/`; generated-entry gen dirs → `GENROOT/`), then `diff`.

**Result: kernel dills are SEMANTICALLY IDENTICAL** — 0-line dump diff for all
four (dtd 61 397, dart2js 329 828, dart2wasm_asserts 426 203, analysis_server
462 779 lines). `dtd` additionally got a byte-level forensic: the residual raw-byte
diff is *entirely* the embedded absolute source-URI prefix (sandbox execroot vs
checkout) cascading into kernel string-table offset **varint widths** — size delta
(12 360 B) accounted for to the byte (192 URIs × prefix-length delta + varint
widening). After prefix-stripping, the differing region is exactly the string
table.

**Why not byte-identical (and why that's correct, not a defect):** the AOT
*tool* kernel compiles embed absolute `file://` source URIs — they do **not** use
`--single-root-base`/`org-dartlang-sdk:///` canonical URIs the way
`compile_platform`/`vm_platform.dill` does. So these dills are *location-dependent
under GN itself* (a different checkout path → different bytes). "Byte-identical to
GN" was never achievable here; **"semantically identical" is the right bar, and we
meet it.** (Forward note: threading a multi-root scheme into the tool AOT compiles
would make them reproducible/remote-cacheable for GN *and* Bazel — a possible
SDK improvement, not yet filed.)

**Define-position finding (confirmed non-issue):** GN passes
`analysis_server`'s `-Dbuilt_as_aot=true` via the template's post-`main_dart`
`args` slot; the Bazel port uses pre-`main` `gen_kernel_args`. The dump diff is
still 0 lines — gen_kernel collects `-D` defines globally regardless of position.

**AOT ELF snapshots:** byte-different, **wholly inherited** from the dill's
path divergence (same `gen_snapshot --deterministic`, path-divergent input dill).
NOT independently byte/semantic-compared; functional equivalence rests on the dill
semantic identity + the session-13 run verification (each tool launches/runs).

## Known red / blocked

- **Cross-arch `gen_snapshot`** (`*_linux_{arm,arm64,riscv64}`): host x64 clang
  without `TARGET_ARCH_*` threaded → `use of undeclared identifier 'R31'`. Needs
  `select()`-on-arch + cross toolchains (overlaps M4).
- **Real `libdart_engine_*.so`** (gn `type=copy` stubs): blocked on toolchain-wide
  `supports_pic` — the whole VM closure compiles `-fPIE`, which overrides
  toolchain `-fPIC`. Currently redirected to static. Unconsumed on linux/x64.
- **In-Bazel `core_snapshot` / `kernel_service.dill` regeneration**: blocked on
  exec-config `third_party/zlib` strict-C++ failures and `record_use` DEPS drift.
  Worked around via pre-staged blobs.

## Out-of-band state (fragile, not in git)

Substantial working-tree state lives outside git (nested non-submodule subrepos:
icu, zlib, boringssl, perfetto, and all `third_party/pkg/*` clones pinned to
their DEPS revs — session 13; plus the gitignored `.dart_tool/package_config.json`,
`out/` exports, and `args.gn` flips). `tools/bazel/out_of_band/restore.sh`
re-applies all of it idempotently
after a `gclient sync` or translator regen. **Read it before assuming a clean
checkout reproduces the build.**

## Related

- Plan of record: `DESIGN.md` (not in this repo — in the dart-bazel city workspace).
- `rules_dart_scoping.md` — scoping spike for the next milestone (Phase 2a).
- Discovered SDK improvements: `issue_00001`–`issue_00011` in this directory.
- Independent skeptical review of issues 1–9: `other_agent_review.md`.
