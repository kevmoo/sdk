# Flutter + Bazel: the cautionary precedent (sourced)

> **Provenance note.** The migration plan invokes *"Flutter's Bazel adoption
> stalled for 7+ years because `rules_dart` was a precondition"* as motivation
> (see `rules_dart_scoping.md`, and the research city's `DESIGN.md §4.3` — which
> is **not** in this tree). This note records the **verified primary sources**
> behind that claim, with the honest nuance, so the history is sourced rather
> than asserted. Verified 2026-05-31 via `gh`.

## Primary sources

- **[flutter/flutter#14125 — "flutter/engine does not build with Bazel"](https://github.com/flutter/flutter/issues/14125)**
  Opened **2018-01-16**, closed **2019-11-06** (state: COMPLETED). The substantive thread.
- **[flutter/flutter#58082 — "Bazel support"](https://github.com/flutter/flutter/issues/58082)**
  Opened **and** closed **2020-05-27** (~47 min apart — a same-day triage close; see correction #2).

## What the sources actually establish (from #14125 maintainer comments)

- Dart build rules for Bazel are real and foundational — the thread names
  **`cbracken/rules_dart`** directly: *"if you wanted to just write Flutter rules
  yourself it's probably not actually a massive undertaking if you were to build
  on top of https://github.com/cbracken/rules_dart."*
- Those rules were only ever a **"functional starting point,"** never
  production-grade; the internal (Blaze) Dart rules are *"far more complex and
  cover a bunch of scenarios that don't matter outside our internal codebase."*
- The blocker is framed **broadly**: *"Supporting build rules for multiple build
  systems in parallel is a massive undertaking,"* *"none of the apps shipping use
  artifacts built from those internal Bazel rules … not production ready,"* and
  *"I don't believe we have any intention of supporting external Bazel builds."*

External Flutter/Dart Bazel support never materialized — 2018 → present (~7+ years),
consistent with the "7+ years" framing.

## Honest nuance (where the migration docs overstate)

1. **Causation.** *"stalled **explicitly because** `rules_dart` was a precondition
   blocker"* is an **interpretation**, not a quote. The sources confirm rules_dart
   immaturity is a **core factor**, but the stated reasons are broader (multi-build-
   system maintenance burden, low priority, no intention to support external Bazel).
   `rules_dart` is *necessary*, not the sole *explicit* cause.
2. **#58082 was mischaracterized.** `DESIGN.md` calls it *"open since 2020."* It was
   **closed the same day it was opened** (a quick triage close). Weak evidence —
   **#14125 is the real source.**
3. **Both issues are CLOSED, not open.** #14125 closed 2019 as *"no intention of
   supporting external Bazel builds"* (closed-as-won't-do) — which *supports* the
   "stalled" reading even though the issues aren't open.

## Takeaway (the strategic call still holds)

**`rules_dart` is the precondition.** Production-grade Dart Bazel rules (incl. AOT)
are the single biggest scope item, and Flutter is real evidence that *not* solving
it as a precondition is how Dart-on-Bazel efforts stall. Just cite **#14125** (and
its `cbracken/rules_dart` reference) rather than the unsourced *"7+ years explicitly
because rules_dart"* phrasing — and let the nuance stand.
