# GOALS

- Complete `SHIPPING_PLAN.md` with a high quality implementation and tests.
- DOCUMENT THE PROCESS WELL!
  - This is a BIG project where an AI agent will have to pick up where I left off.
  - We want to get better at doing this type of thing. So documenting will help us gett better at it.

# Critical rules to follow

- DON'T CHEAT! We want real tests and real benchmarks for REAL WORLD usage of this Socket2 implementation.
  - Don't take the easy way out on a benchmark or a test.
- OFTEN update STUMBLES.md  and BREAKTHROUGHTS.md - but ONLY ADD to these files!!
- NEVER change git history (amend, rebase, etc.)
- NEVER push code without explicit permission
- ALWAYS tell the user EXPLICITLY when you are "tired" (large context window,
  loss of coherence, etc.) instead of being passive aggressive ("Ready to call it a day?", etc.)
- OFTEN commit all changes in the `socket2` branch.
- CONSIDER updating `cheat_sheet_for_the_agent.md` to better reflect your workflow.
- Keep Markdown files well formatted! (80 chars per line, etc.)
- Feel free to "Just GO!!!" No need to stop and ask for permission for every little thing.

# Conductor Infrastructure Cheat Sheet

Commands and infrastructure details for building and
testing the Dart SDK, specifically for Project Socket2.

## Building the SDK

To build the runtime in release mode (as mentioned in `SHIPPING_PLAN.md`):
```bash
./tools/build.py -m release runtime
```

## Running Tests

### Core SDK Tests
Core library tests (like `dart:io`) are typically run using the SDK's custom
test runner.
```bash
./tools/test.py
```
*Note: We need to verify the exact flags and path for Socket2 tests.*

### Package Tests (from GEMINI.md)
For tests in specific packages, use standard `dart test`:
```bash
dart test pkg/linter/test/rules/prefer_relative_imports_test.dart
```

## Presubmit Hooks

To run the presubmit hooks locally (using the `PRESUBMIT.py` in the root):
```bash
git cl presubmit
```
*Note: This requires `depot_tools` to be installed and in your PATH.*
