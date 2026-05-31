# Factory wrap — solo handoff (2026-05-31)

The gc multi-agent "factory" was shut down (`gc stop`) at the **structural
`//sdk:create_sdk`** milestone. From here, drive the migration **solo** (you +
Claude directly), per the (c) decision: keep the factory as a parallel
experiment, but run the critical path solo.

## You are here
- Branch `kevmoo/bazel-m1-cc-toolchain`; all commits are **local (never pushed)**.
- **Done:** M4 product axis wired across `runtime/{bin,vm,platform}`; §7 overlay
  generalized; Step 5 sdk/ assembly — copies re-rooted under `dart-sdk/`, and
  **`//sdk:create_sdk` assembles analysis-green** (structural). Wrap commit:
  `9879731` *"structural //sdk:create_sdk analysis-green (WRAP)"*.
- **Living tracker:** `docs/todo_issues/STATUS.md` documents the stubs/gaps in detail.

## Structural gaps (documented, intentional — this is the "next" work)
`//sdk:create_sdk` is analysis-green but **stubs around** the not-yet-built pieces:
- `vm_platform_product`, `gen_kernel_aot` stubs
- cross-arch `gen_snapshot` (= the M4 **arch axis**: needs `--platforms` + a cross `cc_toolchain`)
- missing sanitizers / strip / devtools / dev_compiler
- `libdart_engine_*.so` copy stubs (toolchain-wide)

## Next (post-wrap, solo)
1. **M4 arch axis** — platform constraints, `--platforms`, `TARGET_ARCH_*`; unblocks cross-arch gen_snapshot.
2. **Fully-functional `create_sdk`** — real platform/kernel, devtools, dev_compiler (gated on the breadth above).
3. **Bzlmod / BCR** — migrate `restore.sh` third-party state (north star).
4. **Translator canonical output** — make `tools/bazel/translate_gn_desc.py` emit
   buildifier-canonical (short labels, no unused loads, module docstring) so
   regenerated `gen_targets.bzl` stops diverging.

## Tooling
- `docs/_bazel_tooling.md` — buildifier/buildozer setup + the canonical convention.
- **Style drift:** the buildifier-canonical style is **not auto-enforced** and has
  already drifted (e.g. `sdk/BUILD.bazel`, `tools/bazel/dart/BUILD.bazel`). Re-canonicalize with:
  ```bash
  buildifier --lint=fix <files>   # excludes generated gen_targets.bzl
  ```
- **Optional pre-commit hook** (auto-canonicalize on commit). Install it yourself:
  ```bash
  cat > .git/hooks/pre-commit <<'EOF'
  #!/usr/bin/env bash
  set -uo pipefail
  command -v buildifier >/dev/null 2>&1 || exit 0
  files=$(git diff --cached --name-only --diff-filter=ACM \
    | grep -E '(^|/)(BUILD\.bazel|MODULE\.bazel)$|\.bzl$' \
    | grep -v 'gen_targets\.bzl' || true)
  [ -z "$files" ] && exit 0
  echo "$files" | xargs buildifier --lint=fix
  echo "$files" | xargs git add
  EOF
  chmod +x .git/hooks/pre-commit
  ```

## Restarting the factory (if ever)
City config persists; `gc start` restarts it. Provider/order state is intact:
mayor+coder+reviewer were on the `claude` provider, dogs suspended (city
`pack.toml` `[[patches.agent]]`), and the `convoy-reap` + `coder-gate-nudge`
orders are present (the gate-nudge is dormant for a Claude coder). See the
`provider-hybrid-split` notes.
