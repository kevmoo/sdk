# Dart SDK improvement issues surfaced by the Bazel migration

This directory tracks Dart-SDK-internal improvements that the [in-progress Bazel
migration](https://github.com/dart-lang/sdk) surfaced as hidden coupling,
non-hermetic scripts, vendoring hygiene problems, or undocumented structural
assumptions.

## Filter rule

An entry only belongs here if it would be a **net improvement to the SDK on its
own** — independent of whether the SDK ever ships a Bazel build. Bazel is the
*forcing function* that surfaced the issue; the issue itself is a Dart-SDK
architectural / hermeticity / vendoring problem.

If the only argument for the change is "to make Bazel easier," it doesn't
belong here. (File it elsewhere or fix it in the Bazel-side translator.)

## 🤖 Protocol for Autonomous Agents

If you are an AI agent executing a task on this repository, you MUST adhere to the following protocol:
1. **Identify Proactively**: Do not silently patch or work around SDK coupling, bad scripts, or dirty vendoring. If it is a net improvement on its own to fix it, it belongs here.
2. **Sequence & Name**: Check the existing files in this directory to find the highest sequence number (e.g., `issue_00011_...`). Use the next sequential number (e.g., `issue_00012_...`) and follow the `issue_NNNNN_short_name.md` format.
3. **Document Before Coding**: Create the issue file *before* you implement the workaround or the fix. Under the `## Resolution` section (see existing issues like `issue_00001...` for format), log what you did, the date, and your session ID so future agents have full context.
4. **Clean Up**: If your changes fully resolve the issue on both the Bazel and SDK/GN sides, delete the issue file in the same commit that resolves it. If the issue remains partially open (e.g., GN-side pending but Bazel-side fixed), leave it open and document your partial progress under `## Resolution`.

## Migration planning docs (not issues)

This directory also holds the migration's own planning artifacts (they live here
because it's where this work stream keeps its durable, reviewable docs):

- **[DESIGN.md](DESIGN.md)** — plan of record: target Bazel design, rule mapping,
  toolchain, third-party, and the Phase 0–3 sequencing the other docs cite as
  `DESIGN.md §3.x/§4.x/§5.x`.
- **[STATUS.md](STATUS.md)** — living progress tracker mapped onto DESIGN.md's
  phases. **The source of truth for where the migration actually stands.**
- **Scoping deep-dives** — [rules_dart_scoping.md](rules_dart_scoping.md)
  (per-package deps graph), [m4_multiconfig_scoping.md](m4_multiconfig_scoping.md)
  (product/config axis), [m4_arch_axis_scoping.md](m4_arch_axis_scoping.md) (arch
  axis), [flutter_bazel_history.md](flutter_bazel_history.md) (prior art).

When DESIGN.md and STATUS.md disagree, STATUS.md + the scoping docs win.

## Naming

```
issue_NNNNN_short_name.md
```

`NNNNN` is a five-digit zero-padded sequence number, starting at `00001`. The
short name is kebab-case and descriptive enough to grep for.

## Template

```markdown
# Issue NNNNN: <short title>

## Problem
What is wrong / hidden / coupled today in the SDK.

## Why this is an improvement on its own
The Bazel-independent argument. If this section is weak, the issue shouldn't
exist.

## How it makes Bazel (and any other non-GN build) easier
Concrete tie-in.

## Affected code
File paths + line refs where relevant.

## Notes
Discovery context, history, related issues.
```

## Lifecycle

The presence of a file here means "open." A landed fix should delete the file
in the same commit that lands the fix (and reference the issue number in the
commit message). No status field, no metadata bookkeeping.

## Augmenting existing issues

Agents working on this branch may freely tighten wording, add code paths that
turn out to be affected, or cross-link to related issues. They may NOT change
the original "this is a problem because…" framing or invent new claims that
the original didn't make. When in doubt, file a sibling issue and link.

## Why this directory exists at all

Each issue is a *proposal* the SDK team can evaluate on its own merits without
having to buy into Bazel. The migration is a discovery vehicle; these files
are the artifacts of discovery.
