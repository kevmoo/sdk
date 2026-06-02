# Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
# for details. All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.

"""Dynamic Bazel test discovery and target generation rules."""



def _dynamic_test_repo_impl(repository_ctx):
    # repo_ctx.workspace_root is the main repository root (requires Bazel 7+)
    workspace_dir = repository_ctx.workspace_root

    # Locate the prebuilt Dart SDK executable and exporter script
    dart_path = workspace_dir.get_child("tools").get_child("sdks").get_child("dart-sdk").get_child("bin").get_child("dart")
    exporter_path = workspace_dir.get_child("pkg").get_child("test_runner").get_child("bin").get_child("test_runner.dart")

    if not dart_path.exists:
        fail("Could not locate prebuilt Dart SDK at: " + str(dart_path))
    if not exporter_path.exists:
        fail("Could not locate test runner script at: " + str(exporter_path))

    # Define the generator script path
    generator_path = workspace_dir.get_child("tools").get_child("bazel").get_child("dart").get_child("generate_test_targets.dart")

    # Generate run_single_test.sh wrapper inside the external repo
    repository_ctx.file("run_single_test.sh", content = """#!/bin/bash
if [ -z "$TEST_SRCDIR" ]; then
  echo "Error: TEST_SRCDIR environment variable is not set!"
  exit 2
fi

DART_BIN=$(find -L "$TEST_SRCDIR" -name dart -type f -perm -u+x | head -n 1)
RUNNER_DART=$(find -L "$TEST_SRCDIR" -name run_single_test.dart -type f | head -n 1)

if [ -z "$DART_BIN" ] || [ -z "$RUNNER_DART" ]; then
  echo "Error: Dynamic launcher was unable to locate dart or run_single_test.dart in runfiles!"
  exit 2
fi

export DART_BIN="$DART_BIN"
exec "$DART_BIN" "$RUNNER_DART" "$@"
""", executable = True)

    # Run the dynamic generator natively
    generator_args = [
        str(dart_path),
        str(generator_path),
        "--workspace-dir=" + str(workspace_dir),
        "--output-dir=" + str(repository_ctx.path(".")),
        "--mode=" + repository_ctx.attr.mode,
        "--compiler=" + repository_ctx.attr.compiler,
        "--runtime=" + repository_ctx.attr.runtime,
    ]
    for s in repository_ctx.attr.suites:
        generator_args.append("--suite=" + s)
    for f in repository_ctx.attr.extra_flags:
        generator_args.append("--extra-flag=" + f)

    res = repository_ctx.execute(generator_args)

    if res.return_code != 0:
        fail("Failed to generate test targets:\n" + res.stderr + "\n" + res.stdout)

# Define the dynamic repository rule. Marked as local because it parses files
# on the local filesystem that change during development.
dynamic_test_repository = repository_rule(
    implementation = _dynamic_test_repo_impl,
    local = True,
    attrs = {
        "mode": attr.string(default = "release"),
        "compiler": attr.string(default = "dartk"),
        "runtime": attr.string(default = "vm"),
        "suites": attr.string_list(mandatory = True),
        "extra_flags": attr.string_list(default = []),
    },
)

# Bzlmod module extension wrapper to instantiate the test repository
def _test_ext_impl(_ctx):
    # 1. VM JIT Release (default)
    dynamic_test_repository(
        name = "dart_tests",
        suites = [
            "language",
            "corelib",
            "standalone",
            "ffi",
            "pkg",
        ],
        mode = "release",
        compiler = "dartk",
        runtime = "vm",
    )

    # 2. VM JIT Debug
    dynamic_test_repository(
        name = "dart_tests_vm_debug",
        suites = [
            "language",
            "corelib",
            "standalone",
        ],
        mode = "debug",
        compiler = "dartk",
        runtime = "vm",
    )

    # 3. Dart2Wasm on D8 Release
    dynamic_test_repository(
        name = "dart_tests_wasm_d8",
        suites = [
            "language",
            "corelib",
            "web/wasm",
        ],
        mode = "release",
        compiler = "dart2wasm",
        runtime = "d8",
    )

    # 3a. Dart2Wasm on D8 with Asserts
    dynamic_test_repository(
        name = "dart_tests_wasm_asserts_d8",
        suites = [
            "language",
            "corelib",
            "web/wasm",
        ],
        mode = "release",
        compiler = "dart2wasm",
        runtime = "d8",
        extra_flags = [
            "--enable-asserts",
            "--dart2wasm-options=-O0",
        ],
    )

    # 3b. Dart2Wasm on D8 Optimized
    dynamic_test_repository(
        name = "dart_tests_wasm_optimized_d8",
        suites = [
            "language",
            "corelib",
            "web/wasm",
        ],
        mode = "release",
        compiler = "dart2wasm",
        runtime = "d8",
        extra_flags = [
            "--dart2wasm-options=-O1",
            "--dart2wasm-options=--no-strip-wasm",
        ],
    )

    # 4. VM JIT Product
    dynamic_test_repository(
        name = "dart_tests_vm_product",
        suites = [
            "language",
            "corelib",
            "standalone",
        ],
        mode = "product",
        compiler = "dartk",
        runtime = "vm",
    )

    # 5. CFE (Fasta)
    dynamic_test_repository(
        name = "dart_tests_cfe",
        suites = [
            "language",
        ],
        mode = "release",
        compiler = "fasta",
        runtime = "none",
    )

dart_tests_extension = module_extension(implementation = _test_ext_impl)
