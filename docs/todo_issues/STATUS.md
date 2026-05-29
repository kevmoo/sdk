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

_Last updated: 2026-05-29 (session 13) — THE REFRESH done (package_config regen + 16 Dart-pkg clone rolls to DEPS pins); unblocked + ported 4 more AOT tools (dart_runtime_service_vm, dartdev, dart2wasm, analysis_server). Only dartanalyzer (app-jit) + web compile_platform variants remain on the utils/ AOT seam._

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
| 2a | `utils/` — Dart-builds-Dart | 🟡 ~30% | `rules_dart` Steps 0–2 done + Step 4 broad: `dart_kernel_snapshot`+`dart_aot_snapshot`+`dart_compile_platform` macros (`//tools/bazel/dart`). Step 0 → `kernel_worker_aot_product`; Step 1 → `vm_platform.dill` in-Bazel (byte-identical to GN); Step 2 → `bootstrap_gen_kernel.dill` in-Bazel; **Step 4 → 10 AOT tools ported & running: dtd, dds, frontend_server, dart_mcp_server, ddc, dart2js + (session 13, after THE REFRESH) dart_runtime_service_vm, dartdev, dart2wasm, analysis_server.** The session-13 refresh (package_config regen + rolling all Dart-pkg clones to DEPS pins) cleared the out-of-band staleness that blocked the analyzer-stack tools. Remaining utils/ AOT work: **dartanalyzer (app-jit only — no aot_snapshot target)** + app-jit `application_snapshot` variants (need a `dart_app_jit_snapshot` rule) + `compile_platform` web variants (need generalized macro) + deps generator (Step 3). See `rules_dart_scoping.md`. |
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
   Remaining clean work: app-jit variants (incl. dartanalyzer) via a
   `dart_app_jit_snapshot` rule + the `compile_platform` web variants + deps
   generator (Step 3).
2. **Multi-config + overlay (M4).** Single-config today, and every translator
   regen trashes the hand-edits — which is the entire reason
   `tools/bazel/out_of_band/restore.sh` exists. No `select()` folding and no
   overlay = can't scale to the arch/OS/product matrix, and stays maintenance-
   fragile.
3. **Cutover machinery (§4.3 + §3.6).** Test integration, swapping
   `tools/build.py`/`test.py` backends GN→Bazel behind the same CLI, and the
   atomic per-subtree GN deletion. None started — GN is still the source of truth.

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
