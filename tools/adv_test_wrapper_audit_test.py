#!/usr/bin/env python3
# Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
# for details. All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.

import os
import re
import sys

def main():
    repo_dir = "/usr/local/google/home/kevmoo/.cache/bazel/_bazel_kevmoo/ead12c53352f3731a78765b752097237/external/+dart_tests_extension+dart_tests"
    if not os.path.exists(repo_dir):
        print(f"Error: Repository directory {repo_dir} does not exist. Run a bazel test first.")
        return 1

    print("Auditing generated files and Bazel BUILD configuration...")

    # 1. Locate all BUILD.bazel files and verify their glob patterns
    build_files = []
    for root, dirs, files in os.walk(repo_dir):
        for f in files:
            if f == "BUILD.bazel":
                build_files.append(os.path.join(root, f))

    print(f"Found {len(build_files)} BUILD.bazel files.")
    
    # Matching pattern for:
    # name = "tests_<config>"
    # followed by data = glob(["gen_tests/<config>/**/*.dart", "gen_tests/<config>/**/*.html"], allow_empty = True)
    # We allow any content (including newlines and other attributes like srcs) in between.
    # We use a greedy match on target blocks to avoid nested parenthesis issues.
    
    targets_missing_glob = []
    total_targets = 0

    for bf in build_files:
        with open(bf, "r", encoding="utf-8") as f:
            content = f.read()
        
        # Find all occurrences of name = "tests_<config>"
        matches = re.finditer(r'name\s*=\s*"tests_([^"]+)"', content)
        for m in matches:
            config_name = m.group(1)
            total_targets += 1
            
            # Extract a window of text after the name definition (up to 500 chars)
            start_pos = m.start()
            window = content[start_pos:start_pos + 500]
            
            # Build target-specific regex to verify the glob
            # We want to match: data = glob(["gen_tests/<config>/**/*.dart", "gen_tests/<config>/**/*.html"], allow_empty = True)
            expected_glob_re = re.compile(
                r'data\s*=\s*glob\(\s*\[\s*"gen_tests/' + re.escape(config_name) + r'/\*\*/\*\.dart"\s*,\s*"gen_tests/' + re.escape(config_name) + r'/\*\*/\*\.html"\s*\]\s*,\s*allow_empty\s*=\s*True\s*\)'
            )
            
            if not expected_glob_re.search(window):
                targets_missing_glob.append((bf, config_name))

    print(f"Verified {total_targets} test targets.")
    if targets_missing_glob:
        print(f"Error: The following targets are missing the correct HTML glob pattern:")
        for bf, config in targets_missing_glob:
            print(f"  - File: {bf}, Config: {config}")
        return 1
    else:
        print("Success: All sh_test targets have the correct .dart and .html globbing patterns.")

    # 2. Audit all .html files in the repository
    html_files = []
    for root, dirs, files in os.walk(repo_dir):
        for f in files:
            if f.endswith(".html"):
                html_files.append(os.path.join(root, f))

    print(f"Found {len(html_files)} generated .html wrapper files.")
    
    improperly_routed = []
    for hf in html_files:
        rel_path = os.path.relpath(hf, repo_dir)
        parts = rel_path.split(os.sep)
        
        if 'gen_tests' not in parts:
            improperly_routed.append(rel_path)
            continue
        
        if parts[0] == 'out':
            improperly_routed.append(rel_path)

    if improperly_routed:
        print(f"Error: The following .html files are improperly routed:")
        for r in improperly_routed:
            print(f"  - {r}")
        return 1
    else:
        print("Success: All .html files are correctly routed under gen_tests/ subdirectories.")

    # 3. Specifically verify bigint_js_test routing
    expected_bigint_paths = [
        "corelib/gen_tests/wasm_chrome_release/tests_corelib_bigint_js_test/test.html",
        "corelib/gen_tests/wasm_chrome_asserts/tests_corelib_bigint_js_test/test.html",
        "corelib/gen_tests/wasm_chrome_optimized/tests_corelib_bigint_js_test/test.html",
        "corelib/gen_tests/wasm_firefox_release/tests_corelib_bigint_js_test/test.html",
        "corelib/gen_tests/wasm_firefox_asserts/tests_corelib_bigint_js_test/test.html",
    ]
    
    missing_bigint_paths = []
    for p in expected_bigint_paths:
        full_path = os.path.join(repo_dir, p.replace('/', os.sep))
        if not os.path.exists(full_path):
            missing_bigint_paths.append(p)

    if missing_bigint_paths:
        print("Error: The following expected bigint_js_test HTML files are missing:")
        for p in missing_bigint_paths:
            print(f"  - {p}")
        return 1
    else:
        print("Success: Checked skipped bigint_js_test HTML wrappers, all are correctly routed.")

    print("\nAll audits passed successfully!")
    return 0

if __name__ == "__main__":
    sys.exit(main())
