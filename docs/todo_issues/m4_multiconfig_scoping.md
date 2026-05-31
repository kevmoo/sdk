# M4 multi-config — scoping spike (Release↔Debug)

> **Not an `issue_NNNNN` file.** This is a design/scoping note for **M4
> (multi-config `select()`)** — the second of the "three big rocks" in
> `STATUS.md`. See `STATUS.md` in this directory for where the migration stands
> overall, and `rules_dart_scoping.md` for the sibling note this one mirrors.
>
> Status: **recon only.** No `select()` added, no `BUILD.bazel` rewired. Output
> is the measured Release-vs-Debug `gn desc` delta over the C++ slice the
> migration builds today, the gn-gen/gn-desc latency + determinism numbers
> (`DESIGN.md`'s two unmeasured unknowns), and a recommended folding + overlay
> strategy.
>
> Scope is deliberately bounded to the **debug↔release axis only**. The other
> M4 sub-axes — arch, OS, product, and the cross-toolchain (sanitizer/host)
> labels GN already emits within a single out-dir — are explicit follow-ups
> (§8). _Written: 2026-05-29 (session 21)._

## 1. Why this recon

Today the migration is **single-config**: one GN out-dir (`out/ReleaseX64`),
zero `config_setting` / `select()` in any migration-authored `BUILD.bazel`. The
translator (`tools/bazel/translate_gn_desc.py`) consumes one `gn desc` and inlines
each target's fully-resolved flags; it explicitly **skips** the cross-toolchain
`//path:name(//toolchain:tc)` labels with the note *"Multi-toolchain folding is
M4 (select() blocks)."* M4 is what turns this into the arch/OS/product/mode
matrix.

`DESIGN.md` flagged two **unmeasured unknowns** that gate M4 planning:
*gn-gen latency per config* and *cflags stability across regens*. This spike
measures both, and — before anyone writes a `select()` — answers the prerequisite
question: **exactly what does a second config change?** It mirrors how
`rules_dart_scoping.md` enumerated the Dart-compile surface before any rule was
built.

## 2. Method (reproducible)

The `gn` binary is `buildtools/gn`; configs are generated the standard Dart way
via `tools/gn.py` (which derives the out-dir name from mode+arch — there is no
out-dir override, so `DebugX64` is *the* debug target).

```bash
# Second config. -nvh/-ngv match the two out-of-band flips the live ReleaseX64
# already carries (verify_sdk_hash=false, dart_version_git_info=false; see
# out_of_band/README "SDK hash discipline"), so the ONLY difference between the
# two descs is the debug↔release axis — not the migration's sdk-hash plumbing.
python3 tools/gn.py --mode=debug   --arch=x64 --no-verify-sdk-hash --no-git-version   # -> out/DebugX64
python3 tools/gn.py --mode=release --arch=x64 --no-verify-sdk-hash --no-git-version   # in-place re-gen of live out/ReleaseX64

buildtools/gn desc out/DebugX64   '//*' --format=json > debug.json
buildtools/gn desc out/ReleaseX64 '//*' --format=json > release.json
```

`gn desc '//*'` is fully recursive: **807 default-toolchain labels** (+201
cross-toolchain `(...)` labels, excluded here — that's the §8 toolchain axis).
The **slice** compared is the default-toolchain targets under `//runtime/vm` and
`//runtime/bin` — the C++ the migration builds today: **141 targets, identical
set in both configs.** Fields diffed = exactly what the translator consumes
(`cflags` → copts, `cflags_c` → conlyopts, `cflags_cc` → cxxopts, `defines`,
`include_dirs`, `deps`, `libs`+`ldflags` → linkopts) plus `asmflags` and the
GN-internal `configs` list (to locate *where* each delta originates).

**Safety:** the in-place Release re-gen is non-destructive — `gn gen` rewrites
ninja files only and does not touch the staged out-of-band artifacts. Verified:
the 9 staged files (`args.gn`, the three `BUILD.bazel` overlays, `vm_platform*.dill`,
`kernel_service.dill`, the two `core_snapshot_*.bin`) were SHA-1-identical before
and after, the original *pre-regen* Release desc is byte-identical to the
post-regen one, and `bazel build //runtime/bin:dartvm` stays green (§ acceptance).

## 3. The delta — Release vs Debug, `runtime/vm`+`runtime/bin`

**Headline: the delta is tiny, uniform, and entirely config-driven.** Across
141 common targets there are **zero target-set differences** (no target appears
or disappears) and **zero `deps`, `libs`, `asmflags`, `cflags_c` differences**
— the dependency graph and link inputs are config-invariant on this axis. Only
four flag fields move, and the same handful of tokens repeats across the slice:

| Field | Release has | Debug has | # targets | What `select()` must model |
|---|---|---|---|---|
| `defines` | `NDEBUG` | `DEBUG` | 123 | one define flip |
| `defines` | `PRODUCT` | — | 58 | product-variant targets only — *product axis leak* (§8) |
| `cflags` (copts) | `-fno-ident` | — | 123 | 1 release-only flag |
| `cflags_cc` (cxxopts) | — | `-Wno-tautological-undefined-compare`, `-Wno-undefined-bool-conversion` | 123 | 2 debug-only warning suppressions |
| `ldflags` (linkopts) | `-Wl,--icf=all`, `-Wl,-O2`, `-Wl,--gc-sections`, `-Wl,--as-needed` | — | 123 | 4 release-only link opts |
| `include_dirs` | `//out/ReleaseX64/gen/…` | `//out/DebugX64/gen/…` | 123 | **cosmetic** — out-dir path token; translator already drops `//out/*` |
| `cflags_c`, `asmflags`, `deps`, `libs` | — | — | 0 | no delta |
| target set | 141 | 141 | 0 | no delta |

**10 distinct flag/define tokens differ** in total (3 defines, 1 copt, 2 cxxopts,
4 linkopts). Origin (`configs` field): the entire delta is driven by **two GN
config-pairs** — `//build/config:debug`↔`:release` and
`//build/config/compiler:no_optimize`↔`:optimize`.

**The `-O2` surprise (verified, not a defect).** The `configs` say
`:no_optimize` (debug) vs `:optimize` (release), but the resolved `cflags` carry
**`-O2` in *both*** — there is **no `-O0` anywhere in the slice**. The Dart VM
applies its own always-optimize config (an unoptimized VM is unusably slow), and
it wins over `:no_optimize`. So on this slice the debug↔release axis is **almost
entirely the `DEBUG`/`NDEBUG` define** (assertions), not an optimization-level
change. A Debug Bazel VM is structurally very close to the Release one.

**Uniformity.** Only **3 distinct delta-signatures** across 141 targets:
- **65 targets** — the base signature (`DEBUG`↔`NDEBUG` + the copt/cxxopt deltas).
- **58 targets** — base + `PRODUCT` release-only. These are exactly the
  `*_product` variants (`gen_snapshot_product`, `dartaotruntime_product`,
  `libdart_builtin_product`, `elf_loader_product`, `crashpad`, `dart`, …). Their
  `PRODUCT` define tracks `is_release` even in a develop build — this is the
  **product axis intersecting** debug↔release, not a pure-mode effect (§8).
- **18 targets** — *no* flag delta: every `group` / `action` / `copy` target
  (the Dart-snapshot actions, file copies, dep-only groups), including
  `//runtime/vm:vm_platform`. They carry no compile flags, so nothing to select.

Because the delta is **config-level uniform** (not per-target), it folds with a
single `config_setting`, not 141 per-target `select()`s — see §6.

## 4. Latency (the first unmeasured unknown)

Per-config `gn gen` and `gn desc` are both **sub-second**. GN parses only the
reachable graph (807 targets from **138 BUILD.gn files**), not the whole tree.

| Step | Debug | Release | Notes |
|---|---|---|---|
| `gn gen` (wall) | 0.40 s | 0.50 s | GN-core self-report: **275–352 ms** |
| `gn desc //*` (wall) | 0.32–0.36 s | 0.31–0.38 s | JSON ≈ **2.75 MB** per config |
| **gen + desc total** | **≈ 0.75 s** | **≈ 0.85 s** | |

Measured on this host (8-thread, 4–5× CPU parallelism). Debug numbers are a
*cold* dir (`rm -rf` first); Release is an in-place re-gen. **Implication for
M4:** capturing a fresh `gn desc` per config is cheap — a translator that runs
`gn desc` for each config in the matrix pays ≈ 0.9 s × N, not minutes. gn-gen is
**not** a bottleneck for a per-config-desc workflow.

## 5. Determinism (the second unmeasured unknown)

**`gn desc` is byte-reproducible for a fixed out-dir path.** Three independent
checks, all `cmp`-clean (0 byte differences):

- **Release, in-place regen ×2** → desc byte-identical (2 752 518 B).
- **Debug, clean-room regen ×2** (`rm -rf out/DebugX64` between) → desc
  byte-identical (2 776 983 B). Even a from-scratch regen reproduces exactly.
- **Live pre-regen Release vs post-regen Release** → byte-identical.

The only path-sensitive content is the `//out/<Config>/gen/…` `include_dirs`
token (which the translator already drops as `//out/*`). **Conclusion:** cflags
are stable across regens; re-running the migration's `gn desc` capture will
**not** spuriously churn generated `BUILD.bazel`. That stability is what makes a
regenerate-and-commit overlay workflow (§7) trustworthy — a diff in the
generated output means a *real* source/args change, never gn nondeterminism.

## 6. Recommended `select()`-folding strategy

**Which axis first: debug↔release — as the *mechanism* proof, not for its own
value.** It is the cheapest possible first bite: a 10-token, fully uniform delta
with **no target-set change, no dep change, no toolchain change**. That makes it
the ideal vehicle to stand up the whole `config_setting` + `select()` + per-config
overlay machinery with near-zero confounders — the same philosophy as
`rules_dart` Step 0 (prove the riskiest plumbing on the smallest real artifact).
Its *intrinsic* value is low (a standalone Debug VM is rarely needed), so treat it
as the proof, then ramp difficulty:

1. **debug↔release** (here) — flags only, uniform, no graph change. Mechanism proof.
2. **product** — flag-surface delta is small and *already visible* (the `PRODUCT`
   define on 58 already-present targets), but full product also drops service-isolate
   sources/deps for some targets, so it touches more than flags.
3. **arch** (cross-compile) — the high-value, high-difficulty axis the known-red
   items demand (`gen_snapshot_*_linux_{arm,arm64,riscv64}` need `TARGET_ARCH_*`
   + `-march` + **cross-toolchains**, and the target set itself changes). Do last.

**How to fold (config-level, not per-target).** The delta originates from two GN
config-pairs and applies uniformly, so model it once:

- One `config_setting` (e.g. `dbg`) keyed on a `--compilation_mode` /
  `--//:dart_debug`-style flag.
- A single shared `select()` carrying the ~7 differing flags
  (`defines`: `DEBUG` vs `NDEBUG`; `copts`: `+= ["-fno-ident"]` on release;
  `cxxopts`: `+= ["-Wno-tautological-undefined-compare",
  "-Wno-undefined-bool-conversion"]` on debug; `linkopts`: the 4 release link
  opts), applied via a shared `cc_library`/toolchain feature rather than sprayed
  into 141 targets. `PRODUCT` is better attached to a *product* `config_setting`
  (axis #2), not the debug one.

**Translator change implied.** The translator currently inlines one config's
resolved flags per target. For M4 it should: run `gn desc` for each config (cheap,
§4), diff per target, emit the **common** flags inline and the **differing** flags
under a `select()`. Given §3's uniformity, that diff is small and almost entirely
shared — the generator can hoist it to one shared target instead of per-target
`select()`s.

> **Update — product axis landed (sessions 24–29), and the cross-slice ABI/ODR
> end-state decision.** The product `config_setting` recommended above now exists
> and is wired into the real `runtime/*` targets. Mechanism (sess 24,
> `//build/config`): `bool_flag :dart_product` (default false) → `config_setting
> :product` → a `:dart_product_mode` `cc_library` that carries the lone `PRODUCT`
> define via `select()`; the translator strips the hardcoded `"PRODUCT"` from
> `runtime/*` targets and routes `:dart_product_mode` through `deps` instead.
>
> **The slices scope that carrier differently, on purpose.** `runtime/vm`
> (sess 28) and `runtime/platform` (sess 29) put it on the **`_product`-suffixed
> variants only** (vm 23 of 44 `dart_mode` targets; platform 8 of 14 — every
> carrier name ends `_product`, zero base targets). `runtime/bin` (sess 26) put it
> on **base** targets too: 58 of its 68 `dart_mode` targets carry it (50 of 50 in
> the hand-authored `BUILD.bazel`, 8 of 18 in the generated `gen_targets.bzl`), of
> which **28 are base** — incl. `dartvm`, `libdart_builtin`, `crashpad`,
> `gen_snapshot_dart_io`, …
>
> This is **not** a package-structure difference — bin, vm and platform all use
> GN's base-vs-`_product` variant split (`library_for_all_configs` / the `build_*`
> templates). It is which of GN's **two** product mechanisms the single Bazel flag
> models (`runtime/BUILD.gn` + `configs.gni`):
> - `config("dart_product_config")` → `PRODUCT` whenever `!dart_debug`, applied
>   **only to the `_product` variants** (the `is_product = true` rows of
>   `_all_configs`). The "build product artifacts inside a normal release build"
>   axis.
> - `config("dart_maybe_product_config")` → `PRODUCT` **only** when
>   `dart_runtime_mode == "release"` (Flutter's release embed), applied to the
>   **base** variants. A whole-runtime mode flip.
>
> **Decision: `--//build/config:dart_product` models the `dart_product_config`
> (`_product`-variant) axis; the end-state product assembly links the `_product`
> variant libraries** — exactly as GN's product `gen_snapshot`/`dartaotruntime`
> link `*_product`. So vm/platform are the GN-faithful, ODR-safe shape (a product
> binary selects `libdart_vm_jit_product` + `libdart_platform_*_product`; every TU
> gets `PRODUCT` uniformly). The base `_jit`/`_aotruntime`/… variants intentionally
> never see this flag — their Flutter-release product-ness is the **separate**
> `dart_maybe_product_config` axis, to be wired later as a `dart_runtime_mode`
> setting, not this one.
>
> **Open reconciliation item (inert today; fix before the product-integration
> slice).** Under this decision, bin's carrier on its **base** targets is a latent
> mixed-`PRODUCT` inconsistency. Concretely: base `dartvm` carries the carrier
> (→ `-DPRODUCT` under the flag) yet links vm's base `libdart_vm_jit`, which does
> not (verified statically: `dart_product_mode` count is **0** in the
> `libdart_vm_jit` block and **1** for the base carrier on `dartvm`;
> `somepath(dartvm, libdart_vm_jit)` non-empty per sess-28 review). So
> `--dart_product=true` over a base-`dartvm` build would mix PRODUCT-on (`dartvm`
> TUs) with PRODUCT-off (`libdart_vm_jit` TUs) in one binary. It is inert only
> because the flag defaults false and nothing builds that combination under the
> flag yet. Before assembling a real product binary, **narrow bin's carrier to its
> `_product` variants too** (match vm/platform), or guarantee the product binary
> selects `_product` throughout and never builds a base target under the flag.
> Tracked in `STATUS.md`'s M4 row.

## 7. Overlay strategy (stop regen from clobbering hand-edits)

**The current pain.** The translator's own header says hand-fixes "belong in this
file … rerun the translator to refresh structural bits and re-apply fixes from
version control" — i.e. regen **overwrites** the generated `BUILD.bazel`
(`runtime/vm`, `runtime/bin`, …) and hand-edits are recovered by hand via git.
`out_of_band/restore.sh` re-applies the *third-party* shims, DEPS pins,
`package_config.json`, and the generated `packages.bzl` — but it does **not**
cover the translator-generated `runtime/*` hand-fixes. Multi-config makes this
acute: the translator sees one config at a time, so a naive per-config regen would
fight the `select()`s a human just added.

**Recommendation: adopt the Step-3 `packages.bzl` split tree-wide.** Step 3
already proved the pattern — a *generated* `.bzl` (`tools/bazel/dart/packages.bzl`,
emitted by `gen_packages.py`) declares the machine-derived targets, and a
*hand-authored* `BUILD.bazel` instantiates it. Bazel reads only one `BUILD.bazel`
per package, so the split must be by **file role**, not two BUILD files:

- **Generated** → the translator emits per-package targets into a
  `gen_targets.bzl` macro (pure machine output; regen overwrites it freely; it is
  byte-stable per §5, so its diffs are meaningful, never noise).
- **Hand-authored** → a thin `BUILD.bazel` that `load()`s and calls the generated
  macro, and is where the `config_setting`s, the `select()`s, and any structural
  hand-fixes live. **The translator never writes this file**, so regen can't
  clobber it.

This makes a regen a `*.bzl`-only overwrite, eliminates the "recover from version
control" step, and gives `select()` a stable home. `restore.sh` would then only
need to regenerate the `.bzl`s (as it already does for `packages.bzl`) — its
step 6 drift-check (“generated output changed — re-commit it”) is exactly the
right model. Alternatives considered and rejected: marked `# BEGIN/END generated`
regions in one file (fragile to editing inside the region) and a committed-patch
overlay (patch drift). The `.bzl`/`BUILD` split is the clean answer and the repo
already runs it for Step 3.

> **Update — landed session 23 (slice 2), on `//runtime/bin` as the pattern proof.**
> `translate_gn_desc.py` gained an opt-in `GEN_TARGETS_PACKAGES` allowlist: for a
> listed package it emits the **machine-derived** cc_* targets into a generated
> `gen_targets.bzl` (`def gen_targets()` macro) and **never (over)writes
> `BUILD.bazel`**; a hand-authored, clobber-safe `BUILD.bazel` `load()`s + calls
> `gen_targets()` and owns every hand-fixed target. Three implementation notes the
> recon didn't anticipate:
> - **The split is by NAME EXCLUSION, not a hardcoded list.** The translator emits
>   only the desc targets whose names are *not* already defined in the hand-authored
>   `BUILD.bazel` (the hand file is the authority on what it owns). A small
>   `GEN_TARGETS_DROP` set additionally suppresses obsolete GN targets the hand file
>   replaced (here: 3 `copy` stubs superseded by real `.so` `cc_binary` rules), so a
>   regen never resurrects them.
> - **Foreign-scan had to be made allowlist-aware.** A `§7` package's hand-authored
>   `BUILD.bazel` lacks the `AUTO-GENERATED` marker, which would otherwise flag it
>   "foreign" and stop the translator from regenerating its **child** packages
>   (`runtime/bin/ffi_unit_test`). The scan now skips the marker test for allowlisted
>   packages.
> - **For these hand-maintained runtime packages the §7 shape INVERTS.** Measuring
>   pristine-translator output vs the committed file: `runtime/bin` is **53/79 targets
>   hand-fixed** (`runtime/vm` 43/48) — only **20 of the 74** desc targets are
>   byte-reproducible. So `gen_targets.bzl` holds the 20 machine targets and the
>   *hand-authored* `BUILD.bazel` is the bulk (69 targets: `dartvm`, `libdart_builtin`
>   + all product/arch variants, every `gen_snapshot*`, the 5 genrules + 8 filegroups,
>   the `.so` rewrites). The recon assumed machine output is the bulk (true for the
>   clean packages a tree-wide rollout will hit); for `runtime/*` the mechanism still
>   works — the *shape* just reflects that these files are de-facto hand-maintained.
>
> Verified: `//runtime/bin:dartvm` byte-identical to pre-change; a regen regenerates
> `gen_targets.bzl` byte-stably and leaves `BUILD.bazel` untouched (content + mtime);
> additive (old-vs-new translator differ on `runtime/bin/BUILD.bazel` only, across all
> emitted packages). **No wiring yet** — flowing `//build/config:dart_mode` into the
> runtime cc_* targets is the next slice, now unblocked because their hand-authored
> home is clobber-safe.

## 8. What this recon did NOT cover

- **The other config axes:** arch, OS, product, sanitizers. The `PRODUCT`-on-58
  signature (§3) is a first peek at the product axis; it is not modeled here.
- **The cross-toolchain `(...)` labels** (201 in a single out-dir: sanitizer
  toolchains, `clang_x64` host-targeting variants). These are the *intra*-out-dir
  toolchain-folding axis the translator skips today — a distinct piece of M4 from
  the *inter*-out-dir debug↔release axis measured here.
- **Any actual `select()` / `config_setting` / `BUILD.bazel` rewiring** — none was
  added; that is the M4 implementation step this recon precedes.
- **A Debug *build*.** Only `gn gen`/`gn desc` were run (no compilation). Whether
  a Bazel Debug VM links and runs is future work; the flag delta says it should be
  structurally close to Release (§3).

## 9. Related

- `STATUS.md` — overall tracker; this is the "M4 — multi-config `select()`" row
  and "three big rocks" #2.
- `rules_dart_scoping.md` — the sibling scoping note this mirrors; its §3 Step 3
  (`packages.bzl`) is the overlay pattern recommended in §7.
- `tools/bazel/translate_gn_desc.py` — the `gn desc` consumer M4 extends
  (per-config diff + `select()` emission).
- `tools/bazel/out_of_band/{restore.sh,README.md}` — the current overlay/regen
  pain §7 addresses.
- `issue_00001_split_conlyopts_cxxopts.md` — the conlyopts/cxxopts split; on this
  slice `cflags_c` (conlyopts) has **zero** debug↔release delta, and the cxxopts
  delta is just the 2 debug-only warning suppressions.
