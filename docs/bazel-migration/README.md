# Bazel Build Migration

This directory houses the documentation, designs, and live status tracking for the migration of the Dart SDK build and packaging engine from GN+Ninja to Bazel.

## 🧭 Quick Start for Agents & Contributors

If you are an autonomous agent or human contributor picking up this migration workstream, follow this sequence:

1. **Start with [BACKLOG.md](BACKLOG.md) & [STATUS.md](STATUS.md)**: If you are an agent, read the `BACKLOG.md` first to claim an open task and set your lock. Check `STATUS.md` for live coordination. These two files are the single source of truth for what needs to be done next and what is currently running.
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
  There is **no realtime channel — git is the coordination bus.**
  * **`git fetch` and rebase onto the remote tip BEFORE you start editing — not after.**
    The other agent is probably already ahead of your local tip. If you base work on a
    stale commit you *will* have to rebase later, and the hot files (`runtime/bin/BUILD.bazel`,
    `STATUS.md`) conflict badly — partly because both agents run `buildifier`, so two
    whole-file canonicalizations of the same drifted file overlap textually even when the
    edits are semantically independent. Starting from the live tip avoids the whole mess.
  * Then `git log --oneline -20` and look for `TAG=` trailers (e.g. `TAG=agy`) to see who
    did what recently, and read the **Cross-agent notes** block at the top of `STATUS.md`
    for open claims/handoffs.
  * When you finish *or* discover something the other agent needs, write it into
    **`STATUS.md`** — a session entry for completed work, and the **Cross-agent notes**
    block for live claims/residuals. That is how the other agent finds out.
  * If you intend to take a chunk of work, post a **soft claim** in the Cross-agent notes
    block so two agents don't grab the same thing.
  * The human relays pushes between forks; don't assume your local commits are visible to
    the other agent until pushed, and don't assume the remote is idle while you work.
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
* **Commit discipline.** Branch is `kevmoo/bazel`; **never push without
  explicit human approval.** Prefer small atomic commits. The pre-commit hook re-`git add`s
  the *whole* staged BUILD/.bzl file (buildifier `--lint=fix`), so per-hunk atomic commits
  of one file need `git commit --no-verify` (the files are already canonical).

## Directory Map

### 🗺️ Design & Status
* **[BACKLOG.md](BACKLOG.md)** — The agent backlog and coordination board. Houses active lock states, task claims, and detailed success criteria for remaining work.
* **[DESIGN.md](DESIGN.md)** — The core plan of record: target Bazel design, rule mappings, toolchain shims, third-party vendoring strategies, and sequence phases.
* **[STATUS.md](STATUS.md)** — The living session-by-session progress tracker. Maps actual progress against the DESIGN.md phases. **The single source of truth for the current migration state.**

### 🔍 Deep-Dives & Scoping
Architectural characterization of core migration seams:
* **[deep_dives/rules_dart_scoping.md](deep_dives/rules_dart_scoping.md)** — Design of the per-package dependencies graph (`packages.bzl`).
* **[deep_dives/testing_migration_roadmap.md](deep_dives/testing_migration_roadmap.md)** — Dynamic dry-run metadata JSON and hermetic sandbox executor roadmap.
* **[deep_dives/m4_multiconfig_scoping.md](deep_dives/m4_multiconfig_scoping.md)** — Scoping of the Debug/Release and Product compilation axes.
* **[deep_dives/m4_arch_axis_scoping.md](deep_dives/m4_arch_axis_scoping.md)** — Cross-compilation mapping (x64 host to ARM64 target).
* **[deep_dives/other_agent_review.md](deep_dives/other_agent_review.md)** — Multi-agent execution reviews.
* **[deep_dives/agent_c_migration_guide_reflection_mac_agy.md](deep_dives/agent_c_migration_guide_reflection_mac_agy.md)** — Architectural reflection on Bzlmod, macros, overlays, toolchains, and analysis latencies.
* **[deep_dives/agent_g_migration_guide_reflection_mac_agy.md](deep_dives/agent_g_migration_guide_reflection_mac_agy.md)** — Architectural reflection on Windows runfiles manifests, private header encapsulation, and include flag propagation.
* **[deep_dives/flutter_bazel_history.md](deep_dives/flutter_bazel_history.md)** — Analysis of historical context and prior art in rules_dart.

### 🛠️ Local Tooling & Verification
* **[bazel_tooling.md](bazel_tooling.md)** — Setup for local Starlark formatting/linting tools (`buildifier`, `buildozer`).
* **[bazel_run_instructions.md](bazel_run_instructions.md)** — Instructions for executing and validating compiled outputs locally.
* **[mac_build_verification_report.md](mac_build_verification_report.md)** — Apple Silicon native compilation verification report.
* **[WRAP_HANDOFF.md](WRAP_HANDOFF.md)** — Cross-host and cross-agent handoff protocol.

### 🚨 Discovered SDK Issues
* **[todo_issues/README.md](todo_issues/README.md)** — Strict filter rules and agent protocol for documenting SDK-internal bugs surfaced by the migration.
* **[todo_issues/](todo_issues/)** — The live directory containing only open SDK-independent bug proposals.
