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
