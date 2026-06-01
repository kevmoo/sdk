# Bazel Build Migration

This directory houses the documentation, designs, and live status tracking for the migration of the Dart SDK build and packaging engine from GN+Ninja to Bazel.

## 🧭 Quick Start for Agents & Contributors

If you are an autonomous agent or human contributor picking up this migration workstream, follow this sequence:

1. **Start with [STATUS.md](STATUS.md)**: Read the "Last updated" and latest session entries at the top of `STATUS.md`. This is the absolute single source of truth for what is currently running, what has been committed locally, and what the immediate next step is.
2. **Read the [DESIGN.md](DESIGN.md)**: Understand the overarching target architecture, rule definitions, phase sequence, and design constraints.
3. **Follow the Protocols**:
   - **SDK-Independent Gaps/Defects**: If you discover a non-hermetic script, undocumented SDK coupling, or packaging defect, consult the **[todo_issues/README.md](todo_issues/README.md)** protocol. Document the defect as a numbered issue in `todo_issues/` *before* writing a workaround.
   - **Session Handoff**: When wrapping up a session, update `STATUS.md` with your notes and consult **[WRAP_HANDOFF.md](WRAP_HANDOFF.md)** to ensure cross-host and cross-agent consistency.
4. **Local Testing**: Use **[bazel_run_instructions.md](bazel_run_instructions.md)** to run local builds and tests.

## 🚨 Before you build or edit — operational rules (read this)

The Quick Start tells you *what to read*; this tells you *what will break you* and
*how to behave*. Skipping it is the fastest way to a broken tree or a collision with
another agent.

* **You may not be alone in here.** More than one agent works this branch concurrently.
  There is **no realtime channel — git is the coordination bus.** Before starting:
  `git log --oneline -20` and look for `TAG=` trailers (e.g. `TAG=agy`) to see who did
  what recently. When you finish *or* discover something the other agent needs, write it
  into **`STATUS.md`** as a session entry — that is how the other agent finds out. If you
  intend to take a chunk of work, say so in `STATUS.md` as a **soft claim** so two agents
  don't grab the same thing. The human relays pushes between forks; don't assume your
  local commits are visible to the other agent until pushed.
* **⚠️ The translator clobbers the tree.** Running `tools/bazel/translate_gn_desc.py`
  regenerates SDK `BUILD.bazel` files **and** overwrites the hand-authored
  `third_party/*/BUILD.bazel` shims (zlib especially → build then dies with
  `-std=c++20 not allowed with C`). **Always run `tools/bazel/out_of_band/restore.sh`
  afterward** (idempotent). Note `git checkout -- .` reverts *uncommitted source edits
  too* — commit first, or you'll lose work. Full story: `tools/bazel/out_of_band/README.md`.
* **Some `BUILD.bazel` files are hand overlays — don't assume the translator owns them.**
  Files marked `# … NOT translator output` / clobber-guarded (e.g. `runtime/vm`,
  `runtime/bin`, `runtime/lib`, `sdk`) are hand-maintained; a re-translation will **not**
  rewrite them, so GN-side changes to those packages need a **manual** Bazel-side update.
* **Environment.** `bazel` = `/home/linuxbrew/.linuxbrew/bin/bazel`; `gn` =
  `depot_tools/gn`. On a fresh clone, re-activate the buildifier pre-commit hook:
  `ln -sf ../../tools/bazel/hooks/pre-commit .git/hooks/pre-commit`.
* **Commit discipline.** Branch is `kevmoo/bazel-m1-cc-toolchain`; **never push without
  explicit human approval.** Prefer small atomic commits. The pre-commit hook re-`git add`s
  the *whole* staged BUILD/.bzl file (buildifier `--lint=fix`), so per-hunk atomic commits
  of one file need `git commit --no-verify` (the files are already canonical).

## Directory Map

### 🗺️ Design & Status
* **[DESIGN.md](DESIGN.md)** — The core plan of record: target Bazel design, rule mappings, toolchain shims, third-party vendoring strategies, and sequence phases.
* **[STATUS.md](STATUS.md)** — The living session-by-session progress tracker. Maps actual progress against the DESIGN.md phases. **The single source of truth for the current migration state.**

### 🔍 Deep-Dives & Scoping
Architectural characterization of core migration seams:
* **[deep_dives/rules_dart_scoping.md](deep_dives/rules_dart_scoping.md)** — Design of the per-package dependencies graph (`packages.bzl`).
* **[deep_dives/testing_migration_roadmap.md](deep_dives/testing_migration_roadmap.md)** — Dynamic dry-run metadata JSON and hermetic sandbox executor roadmap.
* **[deep_dives/m4_multiconfig_scoping.md](deep_dives/m4_multiconfig_scoping.md)** — Scoping of the Debug/Release and Product compilation axes.
* **[deep_dives/m4_arch_axis_scoping.md](deep_dives/m4_arch_axis_scoping.md)** — Cross-compilation mapping (x64 host to ARM64 target).
* **[deep_dives/other_agent_review.md](deep_dives/other_agent_review.md)** — Multi-agent execution reviews.
* **[deep_dives/flutter_bazel_history.md](deep_dives/flutter_bazel_history.md)** — Analysis of historical context and prior art in rules_dart.

### 🛠️ Local Tooling & Verification
* **[bazel_tooling.md](bazel_tooling.md)** — Setup for local Starlark formatting/linting tools (`buildifier`, `buildozer`).
* **[bazel_run_instructions.md](bazel_run_instructions.md)** — Instructions for executing and validating compiled outputs locally.
* **[mac_build_verification_report.md](mac_build_verification_report.md)** — Apple Silicon native compilation verification report.
* **[WRAP_HANDOFF.md](WRAP_HANDOFF.md)** — Cross-host and cross-agent handoff protocol.

### 🚨 Discovered SDK Issues
* **[todo_issues/README.md](todo_issues/README.md)** — Strict filter rules and agent protocol for documenting SDK-internal bugs surfaced by the migration.
* **[todo_issues/](todo_issues/)** — The live directory containing only open SDK-independent bug proposals.
