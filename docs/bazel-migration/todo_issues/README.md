# Dart SDK improvement issues surfaced by the Bazel migration

This directory tracks Dart-SDK-internal improvements that the [in-progress Bazel migration](../README.md) surfaced as hidden coupling, non-hermetic scripts, vendoring hygiene problems, or undocumented structural assumptions.

## Filter rule

An entry only belongs here if it would be a **net improvement to the SDK on its own** — independent of whether the SDK ever ships a Bazel build. Bazel is the *forcing function* that surfaced the issue; the issue itself is a Dart-SDK architectural / hermeticity / vendoring problem.

If the only argument for the change is "to make Bazel easier," it doesn't belong here. (File it elsewhere or fix it in the Bazel-side translator.)

## 🤖 Protocol for Autonomous Agents

If you are an AI agent executing a task on this repository, you MUST adhere to the following protocol:
1. **Identify Proactively**: Do not silently patch or work around SDK coupling, bad scripts, or dirty vendoring. If it is a net improvement on its own to fix it, it belongs here.
2. **Sequence & Name**: Check the existing files in this directory to find the highest sequence number (e.g., `issue_00011_...`). Use the next sequential number (e.g., `issue_00012_...`) and follow the `issue_NNNNN_short_name.md` format.
3. **Document Before Coding**: Create the issue file *before* you implement the workaround or the fix. Under the `## Resolution` section (see existing issues like `issue_00001...` for format), log what you did, the date, and your session ID so future agents have full context.
4. **Clean Up**: If your changes fully resolve the issue on both the Bazel and SDK/GN sides, delete the issue file in the same commit that resolves it. If the issue remains partially open (e.g., GN-side pending but Bazel-side fixed), leave it open and document your partial progress under `## Resolution`.

## Naming

```
issue_NNNNN_short_name.md
```

`NNNNN` is a five-digit zero-padded sequence number, starting at `00001`. The short name is kebab-case and descriptive enough to grep for.

## Template

```markdown
# Issue NNNNN: <short title>

## Problem
What is wrong / hidden / coupled today in the SDK.

## Why this is an improvement on its own
The Bazel-independent argument. If this section is weak, the issue shouldn't exist.

## How it makes Bazel (and any other non-GN build) easier
Concrete tie-in.

## Affected code
File paths + line refs where relevant.

## Notes
Discovery context, history, related issues.
```

## Lifecycle

The presence of a file here means "open." A landed fix should delete the file in the same commit that lands the fix (and reference the issue number in the commit message). No status field, no metadata bookkeeping.

## Augmenting existing issues

Agents working on this branch may freely tighten wording, add code paths that turn out to be affected, or cross-link to related issues. They may NOT change the original "this is a problem because…" framing or invent new claims that the original didn't make. When in doubt, file a sibling issue and link.
