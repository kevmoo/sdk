# Conductor Infrastructure Cheat Sheet

This file documents the commands and infrastructure details for building and
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
