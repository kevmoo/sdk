---
trigger: always_on
description: Safeguard against Bazel hangs and GC thrashing
---

# 🛑 BAZEL HANG DETECTION & TIMEOUT SAFEGUARD

To prevent wasting time and system resources on hung Bazel processes (such as JVM Garbage Collection loops or lock starvation), you MUST strictly adhere to the following rules:

1. **3-MINUTE TIMEOUT SAFEGUARD:**
   - Any background Bazel command (e.g. `bazel fetch`, `bazel build`, `bazel test`, `bazel query`) that runs for **more than 3 minutes** without updating its progress or showing active output MUST be investigated immediately.
   - Do NOT simply wait indefinitely for long-running Bazel commands.

2. **INVESTIGATION PROTOCOL:**
   - If a Bazel command exceeds the 3-minute threshold, execute `ps aux | grep bazel` (or check active processes) to inspect its CPU and memory (RSS) usage.
   - **GC Thrashing Sign:** If the Bazel server process is consuming **over 400% CPU** (multiple cores pegged by JVM GC threads) and **over 15 GB of RAM**, it is highly likely stuck in a Garbage Collection loop.
   - **Action:** If a hang or GC loop is confirmed:
     1. Immediately terminate the active task using the `manage_task` tool with `Action="kill"`.
     2. Attempt to run `bazel shutdown`.
     3. **Shutdown Hang Safeguard:** If `bazel shutdown` itself hangs or takes more than 30 seconds, the server is unresponsive. You MUST find the PID of the Bazel server process (from `ps aux`) and execute `kill -9 <PID>` to forcefully terminate it and reclaim memory. Do not wait for the user to tell you to kill it.
