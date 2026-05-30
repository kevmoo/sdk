# Bazel dev tooling (branch: kevmoo/bazel-m1-cc-toolchain)

Scope: third-party tools for working *on* the Bazel migration — formatting
and editing `BUILD.bazel`/`.bzl` files, and (later) understanding build
performance and the cache. Branch-local — not intended for upstream.

For running the Bazel-built `dartvm`, see `_bazel_run_instructions.md`.

## Installed

| Tool | What it's for | Install |
|---|---|---|
| `buildifier` | Format + lint `BUILD.bazel` / `.bzl` files | `brew install buildifier` (or `go install github.com/bazelbuild/buildtools/buildifier@latest`) |
| `buildozer` | Scripted, programmatic edits to BUILD targets | `brew install buildozer` (or `go install github.com/bazelbuild/buildtools/buildozer@latest`) |

Both are language-agnostic (they operate on Starlark, not on `cc_*` vs
`java_*` semantics), so they apply cleanly to this C++-heavy tree and to the
generated `gen_targets.bzl` / hand-authored overlay `BUILD.bazel` files.

## buildifier — read-only first

`buildifier` **rewrites files in place by default**. Use `--mode=check` to
audit without touching anything:

```bash
# Report which files would reformat + lint warnings — writes nothing.
buildifier --mode=check --lint=warn build/config/BUILD.bazel runtime/bin/BUILD.bazel

# Show the exact diff it would apply — still writes nothing.
buildifier --mode=diff path/to/BUILD.bazel
```

Only run the rewriting form deliberately, on files you mean to change:

```bash
buildifier --lint=fix path/to/BUILD.bazel        # format + auto-fixable lints
```

`--lint=warn` catches real issues (e.g. it flagged an unused
`cc_shared_library` load in `runtime/bin/BUILD.bazel`). Note: the overlay's
generated `gen_targets.bzl` is machine-emitted by the translator — reformat
the *translator's output*, not the committed file by hand, or the next regen
will diff against your manual edits.

## buildozer — edits in place

`buildozer` applies a command to matched targets and writes the BUILD file.
Use `print` (read-only) to inspect before mutating:

```bash
# Read-only: list deps of a target.
buildozer 'print deps' //runtime/bin:dartvm

# Mutating: add a dep (writes the BUILD file).
buildozer 'add deps //some:lib' //runtime/bin:dartvm
```

## Evaluated and skipped (rationale for later)

- **BuildBuddy `bb`** (`bb explain` = "why did this action re-run / miss
  cache" via execution-log diff): genuinely useful, but skipped for now. It's
  a bazelisk-replacement wrapper, its name collides with depot_tools' `bb`
  (which is earlier on `PATH`), and the official installer wants sudo. If a
  cache-miss mystery comes up, install the release binary from the
  `buildbuddy-io/bazel` repo into `~/.local/bin` under a distinct name to
  dodge both snags.
- **EngFlow Bazel Invocation Analyzer** (profile → speed-up suggestions):
  skipped. No system Java; either run it via `bazel run` from its repo (no
  Java install needed) or upload `command.profile.gz` to
  analyzer.engflow.com.
- **`unused_deps`**: intentionally *not* installed — it only analyzes
  `java_library` targets, so it's useless for this C++ build.

## The data Bazel already emits (no extra tools)

- JSON trace profile: `command.profile.gz` is auto-written to the output base
  (`/var/tmp/bazel-dart-sdk/<hash>/`) every build. Load it into
  `chrome://tracing` or ui.perfetto.dev, or `bazel analyze-profile <file>`.
- Why an action re-ran: `bazel build … --explain=explain.log --verbose_explanations`.
- Cache state: `bazel dump --action_cache`.
