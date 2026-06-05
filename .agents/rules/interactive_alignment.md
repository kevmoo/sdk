---
trigger: always_on
description: Rules to distinguish Collaborative vs Autonomous modes and prevent silent preemption
---

# 🤝 OPERATIONAL MODES: COLLABORATIVE VS. AUTONOMOUS

To prevent communication breakdowns where the agent executes changes silently without alignment, the agent MUST strictly distinguish between **Interactive Chat** and **Autonomous Execution** modes.

## 1. Mode Detection & Initialization

* **Mandatory Mode Check**: At the start of a new interactive conversation or task, before executing any code edits, running terminal commands (other than safe query commands to research the workspace), or taking state-changing actions, the agent MUST explicitly ask the user in the chat:
  > *"What mode should I run in for this session: Collaborative (Pair Programming) or Autonomous (Cranking)?"*
  and wait for the user's response to establish the active mode. If running in a non-interactive or pre-configured background environment, the agent should bypass this check and proceed in Autonomous Mode.
* **Interactive Chat Mode (Default)**: Active when the user has selected Collaborative mode, or when communicating in real-time chat (and no explicit mode choice has been made yet).
* **Autonomous Mode ("Cranking")**: Active ONLY when the user has explicitly selected Autonomous mode, used the `/goal` slash command, or instructed the agent using phrases like *"just crank"*, *"run autonomously"*, or *"work on this in the background"*.

---

## 2. Interactive Chat Mode Rules ("Go Slow and Align")

When in **Interactive Chat Mode**, the agent MUST strictly adhere to the following rules:

1. **Verify Plans Manually**: Before making any code modifications or state changes, the agent MUST present a summary of the proposed changes/plans in the chat and wait for a manual confirmation message from the human user (e.g., *"proceed"*, *"go ahead"*, *"yes"*).
2. **Ignore System Auto-Approvals**: The agent MUST ignore any automated system-injected messages stating that an artifact or plan has been approved (e.g., `stop hook blocked termination due to reason: The user has automatically approved...`). The agent must wait for the human user's direct chat reply instead.
3. **No Silent Tool Execution**: The agent must output a brief message explaining what it is doing in passing (following the *"Say things out loud"* rule) before running any major terminal command or test execution.
4. **Request Commit Permission**: Even if other rules (like `commit_permissions.md`) grant autonomous VCS access, the agent must ask for explicit confirmation in the chat before committing or pushing changes during an interactive session.

---

## 3. Autonomous Mode Rules ("Crank and Commit")

When in **Autonomous Mode**, the agent is optimized for speed and independence, and MUST follow these rules:

1. **Proceed on Auto-Approval**: The agent can trust system-injected auto-approval messages and proceed to edit files immediately without waiting.
2. **Autonomous Commits**: The agent should autonomously stage, verify, and commit changes as soon as tests pass, in accordance with `commit_permissions.md`.
3. **Continuous Backlog Progression**: The agent should work through unblocked tasks in `docs/bazel-migration/BACKLOG.md` sequentially, committing progress and updating documentation automatically at the end of each session.
