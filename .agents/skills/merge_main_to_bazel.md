# Upstream SDK Merge Flow Skill

This skill documents the highly efficient, safe mechanism an AI agent (or human developer) uses to merge the latest upstream SDK changes from `origin/main` into the local `bazel` branch, resolve any out-of-band working-tree dependencies, and validate the resulting state.

## 📋 Merge & Synchronization Sequence

To safely synchronize the `bazel` branch with upstream without breaking custom Bazel overlays, follow these precise steps:

### Step 1: Safe Fetch & Dry-Run Merge
Always perform a fetch and a non-committing merge first to identify potential conflicts before polluting the commit history.

```bash
# Fetch the latest upstream changes
git fetch origin

# Perform a non-committing merge
git merge origin/main --no-commit --no-ff
```

### Step 2: Out-of-Band Workspace Restoration (Critical)
Upstream merges often update the `DEPS` pins or structural packages. In addition, routine `gclient sync` operations can wipe out critical out-of-band states needed by the Bazel sandbox.
Always restore out-of-band states right after the merge:

```bash
# Restores CIPD pins, regenerates package_config.json and packages.bzl
tools/bazel/out_of_band/restore.sh
```

### Step 3: Stage and Verify Regenerated Configs
The restoration script will likely regenerate `tools/bazel/dart/packages.bzl` and other files due to dependency upgrades. Verify and stage them:

```bash
# Stage updated Bazel package graphs and snapshots
git add tools/bazel/dart/packages.bzl
git add tools/bazel/out_of_band/snapshot/tools/sdks/dart-sdk/BUILD.bazel.snap
```

---

## 🔍 Validation and Troubleshooting

### Step 4: Bazel Sanity Build
Verify that the compiler service and target VM build cleanly under Bazel.

```bash
# Use the explicit absolute path to Bazel
/usr/local/google/home/kevmoo/bin/bazel build //runtime/bin:dartvm
```

### Step 5: Handle Bazel Output Lock and Orphaned Processes
Bazel builds in large workspaces can take substantial memory/CPU and sometimes leave orphaned processes or server locks. If you encounter `Another command is running` or similar hangs:

1. List running Bazel processes:
   ```bash
   ps aux | grep bazel
   ```
2. Force-kill the orphaned client process (if CPU time is 0:00 or it is hung):
   ```bash
   kill -9 <client_pid>
   ```
3. If the server is still stuck holding locks, force-terminate the server process:
   ```bash
   kill -9 <server_pid>
   ```

### Step 6: Handle Visibility Errors on Prebuilt SDK
If you encounter a Bazel visibility error like:
`target '//tools/sdks/dart-sdk:bin/dart' is not visible from target '//tools/bazel/dart:prebuilt_dart_toolchain_impl'`

Ensure that `tools/sdks/dart-sdk/BUILD.bazel` and its tracked snapshot `tools/bazel/out_of_band/snapshot/tools/sdks/dart-sdk/BUILD.bazel.snap` explicitly export the prebuilt binaries:

```bazel
exports_files([
    "bin/dart",
    "bin/dartaotruntime",
])
```

---

## 💾 Committing the Merge

### Step 7: PATH-Aware Git Commit
The repository contains Git pre-commit hooks (e.g., `dart_format_pre_commit.sh`) that automatically format staged files. These hooks require a functional `dart` compiler on the system `PATH`.

Because the host environment might not have `dart` in its global `PATH`, you **must** temporarily prepend the prebuilt Dart SDK to the `PATH` when running the commit command:

```bash
PATH=$PWD/tools/sdks/dart-sdk/bin:$PATH git commit -m "Merge remote-tracking branch 'origin/main' into bazel"
```
