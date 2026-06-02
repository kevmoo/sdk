---
trigger: always_on
description: Enforce formatting and static analysis cleanliness before committing Dart files
---

# 🧼 DART CODE QUALITY GATES

To maintain high code quality standards and keep the Dart SDK codebase clean, you MUST satisfy the following quality gates before executing any git commit containing Dart changes:

1. **Formatting Gate (`dart format`):**
   - Every modified or newly created `.dart` file MUST be perfectly formatted using `dart format`.
   - Run `dart format <file>` or check formatting before preparing the commit. Do not commit unformatted code.

2. **Static Analysis Gate (`dart analyze`):**
   - Every modified or newly created `.dart` file MUST be completely clean of any analyzer errors, warnings, or lints.
   - Run `dart analyze <file_or_directory>` on your changes. You are **PROHIBITED** from committing any code that introduces analysis issues.
   - If there are pre-existing analysis warnings in adjacent files that your change did not create, you are not required to fix them (adhere to Surgical Changes rule), but your own changed lines must be 100% clean.
