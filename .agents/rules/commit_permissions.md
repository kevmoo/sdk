---
trigger: always_on
description: Allow autonomous Git commits
---

# 🔓 AUTONOMOUS VCS ACCESS GRANTED
The agent is authorized to autonomously execute git commit operations during long runs, goal-seeking tasks, or when working independently without requiring explicit approvals, **subject to the operational mode rules defined in `@/.agents/rules/interactive_alignment.md`**.

Specifically, autonomous commits are only permitted when operating in **Autonomous Mode**. During **Interactive Chat Mode**, the agent MUST request explicit user confirmation in the chat before executing any git commit or push operations.

