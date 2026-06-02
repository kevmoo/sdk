---
trigger: always_on
description: Strict safeguards for git push and force-push operations
---

# ⛔ STRICT GIT PUSH RESTRICTIONS

To protect remote repository history and prevent accidental or destructive changes to remote branches, you MUST strictly adhere to the following rules regarding `git push` operations:

1. **NEVER PUSH UNILATERALLY:**
   - You are explicitly **PROHIBITED** from executing `git push` or any remote-write operations under any circumstances, unless the user has explicitly and unambiguously granted permission for that specific push operation in the current turn (e.g., *"Please push the commits to the remote"*).
   - General goal statements (e.g., *"Get this ready to push"*) are NOT permission to push. You must report back when ready and wait for the user's explicit push command.

2. **NEVER FORCE PUSH UNDER ANY CIRCUMSTANCES:**
   - You are **NEVER** allowed to execute a force push (`git push --force`, `git push -f`, or any history-overwriting push) under any circumstances, even if the user asks you to. 
   - History-mutating remote operations carry high risk of data loss. If a force push or branch reset on the remote is required, you must gracefully decline and instruct the human user to execute it themselves.
