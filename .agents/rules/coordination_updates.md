---
trigger: always_on
description: Require updating BACKLOG.md and STATUS.md when committing work
---

# 📑 COORDINATION & STATUS UPDATE PROTOCOL

To ensure seamless coordination between multiple autonomous agents and human developers working concurrently on the Bazel migration, you MUST strictly adhere to the following rules when preparing and committing work:

1. **Maintain Backlog Integrity (beads issue DB):**
   - Tasks live in the **beads** DB (`bd`), which is the source of truth — `docs/bazel-migration/BACKLOG.md` is generated from it (do not hand-edit the board).
   - Before committing a completed task, close it in beads: `bd close <id>` (and `bd create` any discovered follow-ups).
   - **Regenerate the board**: After any task change in beads, regenerate the board and push the beads change:
     `tools/sdks/dart-sdk/bin/dart docs/bazel-migration/gen_board_from_beads.dart && bd dolt push`
     then commit the updated `BACKLOG.md` / `BACKLOG_HISTORY.md`.

2. **Log Every Session (`docs/bazel-migration/STATUS.md`):**
   - Every commit or logical block of work MUST have a corresponding entry in `STATUS.md` summarizing:
     - Exactly what was implemented or refactored.
     - What was verified (and the results/commands run).
   - The **"Cross-agent notes / open handoffs"** block at the top of `STATUS.md` must be updated to reflect the active state (claims made, open residuals left for the next agent).

3. **Atomic Documentation Commits:**
   - You **MUST NOT** make a git commit for code changes without including the corresponding updates to `BACKLOG.md` and `STATUS.md` **in the same commit**. 
   - This ensures the repository history and documentation never drift, and that the branch HEAD is always in a perfectly documented state.
