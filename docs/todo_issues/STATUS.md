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

_Last updated: 2026-05-30 (session 26) — **M4 product axis wiring landed — 1 atomic commit, NOT pushed (sdk-4cu).** (1) Tweak `translate_gn_desc.py` to strip `"PRODUCT"` from `defines` of all translated targets under `runtime/` and replace it with `//build/config:dart_product_mode` under `deps` (the select() source). (2) Surgically update hand-authored `runtime/bin/BUILD.bazel` product-variant targets, stripping `"PRODUCT"` from `defines` and transitively adding `"//build/config:dart_product_mode"` to `deps` of any target containing `//build/config:dart_mode` to align the preprocessor configurations and prevent ABI/ODR preprocessor hazards. (3) Regenerate `runtime/bin/gen_targets.bzl` byte-stably and verify that both Release and Product (`--//build/config:dart_product=true`) compilations of `//runtime/bin:dartvm` build cleanly with correct preprocessor flags (-DPRODUCT vs -DNDEBUG), and `bazel cquery` resolves a non-empty dependency path `somepath(dartvm, :dart_product_mode)`.

Session 25 — **M4 slice 4 — Transitive NDEBUG leak and ABI/ODR preprocessor hazards resolved (sdk-dj1) — 1 follow-up commit, NOT pushed.** Resolves both high-severity reviewer concerns from `sdk-dj1` (revision of `d8ad60b4efd`). (1) Modify `translate_gn_desc.py` to globally emit `local_defines` instead of `defines` for all generated targets, preventing transitive NDEBUG macro leaks to downstream consumers. (2) Add `runtime/platform`, `runtime/vm`, and `sdk` to the overlay skip list to protect hand-authored overlays. (3) Uniformly propagate `//build/config:dart_mode` to all core C++ targets under `runtime/` (including `runtime/vm` and `runtime/platform` in addition to `runtime/bin`) to guarantee consistent assertion preprocessor flags (`NDEBUG` vs `DEBUG`) and eliminate conceptual ABI/ODR preprocessor hazards across object files in debug builds (`--//build/config:dart_debug=true`). (4) Surgically convert `defines` to `local_defines` in hand-authored overlays and third-party dependencies (e.g. `boringssl`, `binaryen`, `fallback_root_certificates`) for local macro isolation. Verified that both Release and Debug builds of `//runtime/bin:dartvm` compile cleanly.

Session 24 — **M4 product axis (mechanism proof #2), plus the issue_00001 overlay regen + the sdk-52w nit — 3 atomic commits, NOT pushed.** (1) `991f44bfbc6` regenerates the committed §7 overlay `runtime/bin/gen_targets.bzl` into the split `copts`/`conlyopts`/`cxxopts` form the translator gained in `16eba651cb9` (issue_00001 — `.c` files stop receiving C++ flags, greening fresh zlib) but never re-emitted under the slice-2 hold — restoring regen-byte-stability (`//runtime/bin:dartvm` GREEN, **1043 action cache hits under BOTH the merged and split forms** ⇒ byte-identical; `process_test.cc`, the only machine `.cc`, compiles byte-identically; a fresh scoped regen by the final translator is `cmp`-clean). (2) `36cd5c6d86f` (sdk-52w) hardens the §7 `_owned_target_names` regex — `\b` word boundary (fixes a latent `filename`/`pathname` over-match) + single/double-quote + spacing tolerance; a no-op for `runtime/bin` (old+new both extract 69 names). (3) **This commit** adds **M4 mechanism proof #2, the product axis**, in hand-authored `//build/config`: `bool_flag` `:dart_product` (default false) + `config_setting` `:product` + a `:dart_product_mode` `select()` carrier fold the lone PRODUCT define, observed on a graph-isolated `:product_probe` (`-DPRODUCT` only under `--//build/config:dart_product=true`, absent by default; `somepath(dartvm, :product*)` empty; `dartvm` byte-identical) — mirrors slice 1 (`7de5d8087c7`), NO wiring. M4 sub-axis sequencing: product (done) → arch (cross-compile, platform constraints / `--platforms` + cross-toolchains) → Bzlmod/BCR (north-star, unscheduled). Session 23 — **M4 slice 2 — the §7 overlay pattern landed on `//runtime/bin`: a translator regen can no longer clobber the runtime hand-fixes.** Implements `m4_multiconfig_scoping.md` §7 (the Step-3 `gen_packages.py`→`packages.bzl` split, now applied to a translator-generated cc_* package). `translate_gn_desc.py` gains an opt-in `GEN_TARGETS_PACKAGES` allowlist: for a listed package it emits the MACHINE-derived cc_* targets into a generated `gen_targets.bzl` (`def gen_targets()` macro) and **NEVER (over)writes `BUILD.bazel`**; a hand-authored, clobber-safe `runtime/bin/BUILD.bazel` `load()`s + calls `gen_targets()` and owns every hand-fixed target. Machine-vs-hand split = **NAME EXCLUSION** (emit only desc targets the hand file doesn't already define) + a 3-name `GEN_TARGETS_DROP` for obsolete GN `copy` stubs the `.so` rewrites superseded; foreign-scan made allowlist-aware so the `ffi_unit_test` **child** still regenerates. **Empirical reality (measured pristine-translator vs committed): `runtime/bin` is 53/79 targets hand-fixed (`runtime/vm` 43/48) — only 20 of the 74 desc targets are byte-reproducible**, so the §7 shape INVERTS for these de-facto hand-maintained runtime packages: `gen_targets.bzl` holds the 20 machine targets, the hand-authored `BUILD.bazel` is the bulk (69 targets incl. `dartvm`, `libdart_builtin` + all product/arch variants, every `gen_snapshot*`, the 5 genrules + 8 filegroups, the `.so` rewrites). The mechanism is general (clean packages → thin BUILD, the intended shape); the shape just reflects the package. Verified: `//runtime/bin:dartvm` **BYTE-IDENTICAL** to pre-change (`d424476a…`, full green build, not stale); a regen regenerates `gen_targets.bzl` **byte-stably** (`cmp`-clean across runs) and leaves `BUILD.bazel` UNTOUCHED (content + mtime); **additive** (old-vs-new translator differ on `runtime/bin/BUILD.bazel` ONLY across all 60 emitted packages; `ffi_unit_test` child byte-identical). **NO wiring** (flowing `//build/config:dart_mode` into the runtime cc_* targets = the next slice, now unblocked since the home is clobber-safe). 1 atomic commit, NOT pushed. **NEXT: wire `dart_mode` into the runtime cc_* targets (clobber-safe now), the product axis, or Step 5 (sdk/ assembly).** Session 22 — **M4 mechanism proof #1 — the FIRST `select()` in the migration: the debug↔release axis folds via a hand-authored, clobber-safe `//build/config`.** Implements `m4_multiconfig_scoping.md` §6. ONE `bool_flag` `:dart_debug` (default false = today's release; a custom build setting, NOT `--compilation_mode`, so Dart's `DEBUG`/`NDEBUG` assertion axis stays decoupled from Bazel's `-O` level — the VM forces `-O2` in both, recon §3) + `config_setting` `:debug` + a single shared `:dart_mode` `cc_library` carrying the `defines` (`NDEBUG`⇄`DEBUG`) and `linkopts` (4 release-only `-Wl,*`) halves via `select()` (a `cc_library` dep propagates exactly those two flag kinds). `copts`/`cxxopts` do NOT propagate from a dep (Bazel applies them to a target's own srcs only), so the `-fno-ident` (release copt) + 2 `-Wno-*` (debug cxxopts) halves ride on the `:mode_probe` consumer via the SAME `:debug` setting. Empirically via `bazel aquery` (static, no execution): release → `-DNDEBUG` + `-fno-ident` + 4 `-Wl` linkopts, no `DEBUG`/cxxopts; `--//build/config:dart_debug=true` → `-DDEBUG` + 2 `-Wno` cxxopts, all 4 release tokens dropped. **`PRODUCT` excluded** (product axis, §8). No regression: `//runtime/bin:dartvm` green, `libdart_vm_jit` compile flags byte-identical to the pre-change baseline (224 `NDEBUG` / 224 `-fno-ident` / 0 `DEBUG`), and `somepath(dartvm, :dart_mode)` is empty (the mechanism is graph-isolated → zero impact on the real build). `bazel_skylib` 1.8.2 promoted to a direct `bazel_dep` (already the selected transitive version → `MODULE.bazel.lock` unchanged, offline-clean). Hand-authored `build/config/BUILD.bazel` + `mode_probe.cc`; NO edits to translator-generated runtime BUILD.bazel (regen can't clobber). Out of scope (later slices): the product/arch/OS axes, the §7 `.bzl`/overlay split, and generalizing `translate_gn_desc.py` to emit per-config `select()` for the 141 real targets. 1 atomic commit, NOT pushed. **NEXT: the §7 `.bzl`/overlay split, the product axis, or Step 5 (sdk/ assembly).** Session 21 — **M4 recon: characterized the Release↔Debug `gn desc` delta over the `runtime/vm`+`runtime/bin` slice — the first concrete step of M4 (multi-config), no `select()` added.** Findings (new `m4_multiconfig_scoping.md`): the debug↔release axis is a **10-token, fully uniform flag delta** — `DEBUG`↔`NDEBUG` (+`PRODUCT` on the 58 `*_product` variant targets, a product-axis leak), `-fno-ident` (release copt), 2 `-Wno-*` (debug cxxopts), 4 `-Wl,*` (release linkopts) — with **zero target-set change, zero `deps`/`libs`/`asmflags`/`cflags_c` change, and `-O2` in BOTH configs** (the VM always optimizes; `:no_optimize` never injects `-O0` on this slice). Origin is two GN config-pairs (`:debug`↔`:release`, `:no_optimize`↔`:optimize`) applied uniformly → folds with ONE config-level `select()`, not 141 per-target ones. **Both unmeasured `DESIGN.md` unknowns answered:** gn-gen ≈ 0.4–0.5 s + gn-desc ≈ 0.3–0.4 s per config (sub-second; GN parses only 138 reachable BUILD.gn files; ~2.75 MB desc), and `gn desc` is **byte-identical across regens** (in-place ×2, clean-room rm+regen ×2, and live-vs-regen — all `cmp`-clean), so re-capturing won't churn generated BUILD.bazel. Recommends modeling debug↔release first as the cheap mechanism proof (then product, then arch), and adopting the Step-3 `packages.bzl` split tree-wide (translator emits a generated `.bzl` macro; a hand-authored `BUILD.bazel` owns the `config_setting`s + `select()`s) so regen stops clobbering hand-fixes. Recon only — no `select()`/`BUILD.bazel` rewiring; staged out-of-band state SHA-verified unchanged; `bazel build //runtime/bin:dartvm` still green. 1 atomic commit (new doc + this STATUS update), NOT pushed. **NEXT: implement the debug↔release `select()` + the `.bzl`/overlay split, or Step 5 (sdk/ assembly).** Session 20 — **Scoped the platform compiles off the opaque blob — the session-19 "left opaque" follow-up, which completes Step 3 incrementality and retires the blob entirely.** The 7 platform compiles (`vm_platform` + the 6 `dart_compile_platform` web/wasm variants) were the last targets feeding on `//:dart_package_sources`. Their entry script `pkg/front_end/tool/compile_platform.dart` and its `tool/` siblings live OUTSIDE any package `lib/`, so a new hand-authored `//:compile_platform_tool` `dart_library` lists the 7 import-closure files (compile_platform / entry_points / additional_targets / bench_maker / command_line + test/coverage_helper + test/vm_service_helper) as explicit srcs, with `deps` on the 9 top-level packages the entry transitively reaches (`_fe_analyzer_shared, build_integration, compiler, dart2wasm, dev_compiler, front_end, kernel, vm, vm_service`). Because `additional_targets.dart` statically imports every kernel `Target` (vm/dart2js/dartdevc/dart2wasm), ONE closure serves all 7 callers regardless of which `--target=` they pass. Also fixed `dart_compile_platform` to materialize `.dart_tool/package_config.json` (via `_PACKAGE_CONFIG_FILE`): it had relied on the blob bundling it, so a `.dart`-only scoped closure left `--packages` reading a missing file (the real root cause — every package failed to resolve, surfacing as misleading cascading `vm_service` type errors). The other three macros already include it; deduped/harmless if `sources` is still the blob. **All 14 platform dills (7 platform + 7 outline) BYTE-IDENTICAL to GN** (`cmp` 0 vs `out/ReleaseX64`) — the vm_platform gold standard, not merely semantic. `vm_platform`'s closure shrank **21 177 → 3 210 `.dart` inputs**; `dtd_impl`/`dds`/`analysis_server`/`dartdev` no longer trigger the platform compile. `analyzer` (444 files) remains only because `pkg/dart2wasm` (and `pkg/front_end`) declare `analyzer:` in real pubspec `dependencies` — the documented §8 safe-superset, not an overreach. **The opaque `//:dart_package_sources` filegroup now has ZERO remaining consumers (no `sources=` refs, no rdeps) — a candidate for outright removal in a follow-up.** 2 commits (9890ce3df75 + 50d23ebfb54 + this docs commit), NOT pushed. **NEXT: Step 5 (sdk/ assembly) / M4 multi-config.** Session 19 — **rules_dart Step 3 DONE: the per-package deps graph** that replaces the opaque `//:dart_package_sources` blob (all ~197 pkgs, fed to every tool's kernel compile). New `dart_library` rule + `DartLibraryInfo` provider (transitive-srcs depset) + `gen_packages.py` (gazelle-style pubspec→deps generator) → `packages.bzl` (196 `dart_pkg_*` targets, declared in the ROOT package since `pkg/`+`third_party/pkg/` have no sub-BUILD.bazel). **Deps-model decision (resolves the §9 "wildcard"): pubspec `dependencies`, not import-scanning** — empirically a cycle-free safe superset of real imports (comment-aware scan: 0 imported-not-declared; `dev_dependencies` excluded → 0 cycles in 197 nodes/806 edges). All ported `utils/` tools + the shared `bootstrap_gen_kernel` (→ `dart_pkg_vm`, 17 pkgs) repointed onto per-package closures. **Incrementality proven**: editing an out-of-closure package leaves a tool's kernel compile a CACHE HIT (was a full recompile under the blob); dills SEMANTICALLY IDENTICAL to opaque (0-line dump-diff, dtd 61 397 + dart2js 329 828); `//:runtime` clean; `vm_platform.dill` byte-identical. Two macro fixes: app-jit training stage now lists `main` (DDC retrains its own bin/), and analysis_server training needs `//:dart_pkg_compiler` (its `--train-using=pkg/compiler/lib`). **Left opaque on purpose: the platform compiles** (`vm_platform` + 6 `dart_compile_platform` web variants) — their tool script `compile_platform.dart` lives outside any `lib/`, needs threading as an explicit input (clean follow-up); byte-deterministic so they don't cascade. 4 commits (0ad3f6ce667 + 5f8c68b8e8a + 555fb718622 + this), NOT pushed. **NEXT: thread compile_platform.dart as an explicit input to scope the platform compiles too; then Step 5 (sdk/ assembly) / M4 multi-config.** Session 18 — Ported the **`frontend_server` + `kernel-service` app-jit snapshots** (`application_snapshot("frontend_server")` / `application_snapshot("kernel-service_snapshot")`), the last clean app-jit tools in the `utils/` seam. The "staged platform dill in the training cwd" open question resolved cleanly: GN colocates `vm_platform.dill` next to the built `dart` so the tools find it via `computePlatformBinariesLocation()`, but in Bazel `dartvm` is NOT colocated — so the platform is passed **explicitly** through each tool's existing arg surface. `kernel_service.dart --train <script> [platform]` takes an optional 2nd positional platform path (resolved via `Uri.base.resolveUri(Uri.file(...))` against the execroot) → pass `$(location //runtime/vm:vm_platform.dill)`. `frontend_server --train` re-parses `--sdk-root`/`--platform` and does `sdkRoot.resolve(Uri.file(platform))` → `--sdk-root=.` (execroot = `Uri.base`) + `--platform=$(location ...)` (execroot-relative) land on the right file. Both reuse the session-15 `training_srcs` param (vm_platform.dill + the main entry) so `$(location)` resolves in the stage-2 training genrule; no macro change needed. Verified by the session-14 method (rebuild GN stage-1 dill from current sources + path-normalized dump-diff): **0-line semantic diff** — kernel-service 267 305 lines, frontend_server 302 958 (frontend_server's training did a real incremental compile/recompile-delta cycle, exactly GN). Both snapshots run; `//:runtime` clean (`//:most` fails only on the pre-existing cross-arch `libdart_precompiler_product_linux_arm`, unrelated); vm_platform still byte-identical. **The clean app-jit + AOT tool seam over `utils/` is now exhausted — NEXT is Step 3 (deps generator, wildcard).** app-jit tool count now **10** (dartanalyzer + 5 generate_* + dartdevc/dart2js + these 2). Session 17 — Ported the **`dartdevc` + `dart2js` app-jit snapshots** (`application_snapshot("dartdevc")` / `application_snapshot("dart2js")`), unblocked by the session-16 `compile_platform` web variants. Both training runs consume the in-Bazel platform/outline dills: dartdevc's run compiles dartdevc.dart with `--dart-sdk-summary=ddc_outline.dill` (the `:ddc_platform` outline, injected via `$(location)`); dart2js's run compiles memory_compiler.dart over the generated `dart2js.dart` entry with `--platform-binaries=$(RULEDIR)/` (where `:compile_dart2js_platform` emits `dart2js_platform.dill`/`dart2js_outline.dill`). Both verified by the session-14 method (rebuild GN dill from current sources + path-normalized dump-diff): **0-line semantic diff** — dartdevc 278 585 lines, dart2js 380 266 (the lone 2-line residual was the generated-entry wrapper's gen-dir path, location-dependent exactly as session 14 documented). Both snapshots run; `//:most`/`//:runtime` clean; vm_platform still byte-identical. app-jit tool count now **8** (dartanalyzer + the 5 generate_* + these 2). Session 16 — Ported **all 6 `compile_platform` web/wasm variants** (ddc_platform, compile_dart2js_platform, compile_dart2js_server_platform, compile_dart2wasm_platform, compile_dart2wasm_js_compatibility_platform, compile_dart2wasm_standalone_platform) by generalizing `dart_compile_platform` ADDITIVELY (new optional params platform_args/single_root_base/deps_outline/platform_out, all defaulting to the VM call → vm_platform.dill rebuild is a cache HIT, still cmp-identical to GN). **All 14 output dills (7 variants × platform+outline, incl. vm) are BYTE-IDENTICAL to a freshly-rebuilt GN** — the vm_platform gold standard, not merely semantic (canonical single-root URIs ⇒ location-independent). `//:dart2wasm_platform` now builds end-to-end; unblocks dartdevc + dart2js app-jit/AOT. Session 15 — Ported the **5 remaining clean app-jit `generate_*` variants** (the JIT-launcher snapshots that sit beside the session-12/13 AOT snapshots): dtd, dds, dartdev, dart_runtime_service_vm (all trivial main+training_args) and analysis_server. All verified by the session-14 method (rebuild GN dill from current sources + path-normalized dump-diff) → **0-line semantic diff** (dtd 42 077, dds 62 388, dartdev 743 919, drsv 67 670, analysis_server 527 792 lines); snapshots load/JIT-run. analysis_server forced a macro extension: `dart_app_jit_snapshot` gained a **`training_srcs`** param (ports GN training_inputs/training_deps) — its training run is a real analysis pass that reads sdk/lib/** + sdk/version outside the pkg/ closure, which the Bazel sandbox needs declared (also newly exported //sdk:version). app-jit tool count now **6** (these 5 + dartanalyzer). Remaining utils/ seam: dartdevc + dart2js (need compile_platform web variants), frontend_server + kernel-service (need a staged platform dill); kernel_worker app-jit skipped (deprecated, removable in 3.7, unreferenced). Session 14 — VERIFIED AOT-tool fidelity (closed the session-12 "ported snapshots unverified vs GN" risk): 4 of 10 AOT tools spot-checked, kernel dills SEMANTICALLY IDENTICAL; NEW `dart_app_jit_snapshot` macro + dartanalyzer (first app-jit tool). Session 13 — THE REFRESH (package_config regen + 16 Dart-pkg clone rolls to DEPS pins); ported 4 more AOT tools._

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
| M4 — multi-config `select()` | 🔴 ~50% (2 axis mechanisms + §7 overlay + runtime/bin wiring) | **Recon:** `m4_multiconfig_scoping.md` (10-token uniform debug↔release delta). **First `select()` landed (sess 22):** hand-authored `//build/config` folds the debug↔release delta via ONE `bool_flag` `:dart_debug` + `config_setting` `:debug` + a shared `:dart_mode` `cc_library` (propagates `defines`/`linkopts`); `:mode_probe` flips `NDEBUG`/`-fno-ident`/4 linkopts (release) ⇄ `DEBUG`/2 `-Wno` cxxopts (debug), shown via `aquery`. Default release unchanged: `//runtime/bin:dartvm` green, `libdart_vm_jit` byte-identical, graph-isolated. **§7 overlay landed (sess 23):** opt-in `GEN_TARGETS_PACKAGES` in `translate_gn_desc.py` emits `runtime/bin`'s 20 machine cc_* targets into a generated `gen_targets.bzl` macro; a hand-authored, clobber-safe `BUILD.bazel` `load()`s+calls it and owns the 69 hand-fixed targets (`dartvm` etc.) — regen byte-stable + never touches `BUILD.bazel`; `dartvm` byte-identical. **Product axis landed (sess 24, mechanism proof #2):** a net-new `bool_flag` `:dart_product` (default false) + `config_setting` `:product` + a `:dart_product_mode` `cc_library` fold the lone PRODUCT-define delta (recon §3/§8) via `select()`, observed on a graph-isolated `:product_probe` (`-DPRODUCT` under `--//build/config:dart_product=true`, absent by default; `somepath(dartvm, :product*)` empty; `dartvm` 1043-cache-hit byte-identical) — mirrors slice 1 (`7de5d8087c7`), NO wiring. **Product axis wired into runtime/bin (sess 26, sdk-4cu):** Tweak `translate_gn_desc.py` to strip `"PRODUCT"` from `defines` of all translated targets and replace with `//build/config:dart_product_mode` in `deps`, and surgically update hand-authored `runtime/bin/BUILD.bazel` to route `dart_product_mode` under `deps` to prevent ABI/ODR preprocessor hazards. Both Release and Product (`--//build/config:dart_product=true`) builds of `//runtime/bin:dartvm` compile cleanly. **M4 sub-axis sequencing:** product (done) → arch (cross-compile, via platform constraints / `--platforms` + cross-toolchains) → Bzlmod/BCR (north-star, unscheduled). Still TODO: **wiring** `dart_mode`/`dart_product` into runtime/vm real targets; the full-product service-isolate srcs/deps drop (recon §8); arch. |
| M5 — codegen / real blobs | ✅ Done (+Path-1.5) | all 4 blob symbols real; `dartvm` runs raw `.dart` source |

## The subtree phases (the actual migration — DESIGN.md §4.2)

| Phase | Subtree | Status | Detail |
|---|---|---|---|
| 0 | `build/toolchain/linux` | ✅ 100% | Bazel `cc_toolchain` port |
| 1a | `runtime/vm` core C++ | ✅ 100%¹ | `libdart_vm_jit` + 13 variants; ¹one config only |
| 1b | `runtime/bin` executables | ✅ ~90%¹ | `dart`, `dartvm`, `dartaotruntime`, `gen_snapshot` family, `run_vm_tests`, all 14 host cc_binaries, 3 FFI test `.so`s, 43 FFI unit tests pass |
| 1c | `runtime/platform`, observatory, … | 🟡 ~50% | platform done; observatory + remainder untouched |
| 2a | `utils/` — Dart-builds-Dart | 🟡 ~30% | `rules_dart` Steps 0–2 done + Step 4 broad: `dart_kernel_snapshot`+`dart_aot_snapshot`+`dart_compile_platform` macros (`//tools/bazel/dart`). Step 0 → `kernel_worker_aot_product`; Step 1 → `vm_platform.dill` in-Bazel (byte-identical to GN); Step 2 → `bootstrap_gen_kernel.dill` in-Bazel; **Step 4 → 10 AOT tools ported & running: dtd, dds, frontend_server, dart_mcp_server, ddc, dart2js + (session 13, after THE REFRESH) dart_runtime_service_vm, dartdev, dart2wasm, analysis_server.** The session-13 refresh (package_config regen + rolling all Dart-pkg clones to DEPS pins) cleared the out-of-band staleness that blocked the analyzer-stack tools. **Session 14 added a 4th macro `dart_app_jit_snapshot` (ports `application_snapshot.gni` — JIT VM training run via `//runtime/bin:dartvm`, not gen_snapshot) and ported `dartanalyzer` (first app-jit tool). Session 15 ported the 5 remaining clean app-jit `generate_*` variants (dtd, dds, dartdev, dart_runtime_service_vm, analysis_server; all 0-line dump-diff vs GN) and gave the macro a `training_srcs` param (ports GN training_inputs/training_deps) for analysis_server's real-analysis training run. app-jit tool count = 6.** **Session 16 ported all 6 `compile_platform` web/wasm variants** (ddc_platform, compile_dart2js{,_server}_platform, compile_dart2wasm{,_js_compatibility,_standalone}_platform) by generalizing `dart_compile_platform` additively — all 14 dills BYTE-IDENTICAL to GN, vm_platform untouched (cache hit). **Session 17 ported the `dartdevc` + `dart2js` app-jit snapshots** (consuming the session-16 ddc_outline.dill / dart2js_platform.dill via training_srcs; both 0-line dump-diff vs GN). **Session 18 ported the `frontend_server` + `kernel-service` app-jit snapshots** (platform passed explicitly through each tool's `--train`/`--sdk-root`/positional arg surface via `$(location)`, since Bazel's `dartvm` is not colocated with vm_platform.dill the way GN's built `dart` is; both 0-line dump-diff vs GN). **The clean app-jit + AOT tool seam over `utils/` is now exhausted** (app-jit tool count = 10). **Session 19 did Step 3 (the per-package deps generator): `dart_library` rule + `DartLibraryInfo` + `gen_packages.py`→`packages.bzl` (196 `dart_pkg_*` targets, pubspec-derived); all ported tools + `bootstrap_gen_kernel` repointed off the opaque blob onto per-package closures → real incrementality (out-of-closure edit = cache hit), dills semantically identical to opaque.** The platform compiles (`vm_platform` + 6 web variants) stay opaque pending threading `compile_platform.dart` as an explicit input. `kernel_worker` app-jit skipped (deprecated, removable in SDK 3.7, unreferenced). See `rules_dart_scoping.md`. |
| 2b | `sdk/` assembly | 🔴 0% | gated on 2a |
| 2c | `samples/` | 🟡 ~40% | all 20 `samples/embedder` + `ffi/http*` done; rest no |
| 3 | `third_party/` | 🟡 partial | icu/boringssl/perfetto/zlib/double-conversion hand-shimmed & working; BCR `bazel_dep` migration not done |
| Deferred | cross-arch, Android, Fuchsia, Windows, browser, emsdk | 🔴 0% | cross-arch `gen_snapshot` confirmed red (needs `select()`-on-arch + cross toolchains) |

## The three big rocks still ahead

1. **`rules_dart` — the single biggest scope item.** DESIGN.md §4.3: this is the
   precondition that stalled Flutter's Bazel adoption for 7+ years; the plan says
   solve it *as a precondition, not during* the migration. Gates all of Phase 2a
   and therefore 2b. Plausibly larger than everything done to date. **Scoped +
   Steps 0–4 substantially done + Step 3 done session 19 (per-package deps graph,
   real incrementality) — see `rules_dart_scoping.md`.**
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
- `m4_multiconfig_scoping.md` — scoping spike for M4 (Release↔Debug config delta,
  gn-gen/gn-desc latency + determinism, recommended `select()`-folding + overlay).
- Discovered SDK improvements: `issue_00001`–`issue_00011` in this directory.
- Independent skeptical review of issues 1–9: `other_agent_review.md`.
