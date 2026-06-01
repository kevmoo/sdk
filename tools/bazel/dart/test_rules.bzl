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

    # Output filepath for temporary JSON dump
    json_output_path = repository_ctx.path("test_metadata_all.json")

    # Run the dynamic metadata dry-run exporter
    suite_args = repository_ctx.attr.suites

    # We execute the exporter natively on the host to extract resolved configurations
    res = repository_ctx.execute([
        str(dart_path),
        str(exporter_path),
        "-m",
        repository_ctx.attr.mode,
        "-c",
        repository_ctx.attr.compiler,
        "-r",
        repository_ctx.attr.runtime,
        "--dump-test-metadata=" + str(json_output_path),
    ] + suite_args)

    if res.return_code != 0:
        fail("Failed to dump test metadata during repository analysis:\n" + res.stderr + "\n" + res.stdout)

    # Read and decode the JSON metadata file
    metadata_str = repository_ctx.read(json_output_path)
    test_cases = json.decode(metadata_str)

    # Generate run_single_test.sh wrapper inside the external repo
    # This script is invoked under Bazel's sh_test and finds execution paths inside the runfiles tree
    repository_ctx.file("run_single_test.sh", content = """#!/bin/bash
# Ensure TEST_SRCDIR is set
if [ -z "$TEST_SRCDIR" ]; then
  echo "Error: TEST_SRCDIR environment variable is not set!"
  exit 2
fi

# Locate prebuilt dart binary and run_single_test.dart inside runfiles by searching from TEST_SRCDIR
DART_BIN=$(find -L "$TEST_SRCDIR" -name dart -type f -perm -u+x | head -n 1)
RUNNER_DART=$(find -L "$TEST_SRCDIR" -name run_single_test.dart -type f | head -n 1)

if [ -z "$DART_BIN" ] || [ -z "$RUNNER_DART" ]; then
  echo "Error: Dynamic launcher was unable to locate dart or run_single_test.dart in runfiles!"
  echo "TEST_SRCDIR: $TEST_SRCDIR"
  echo "PWD: $(pwd)"
  echo "Listing files in TEST_SRCDIR:"
  find -L "$TEST_SRCDIR" -maxdepth 4 || true
  exit 2
fi

export DART_BIN="$DART_BIN"
exec "$DART_BIN" "$RUNNER_DART" "$@"
""", executable = True)

    # Initialize root BUILD.bazel contents
    build_content = 'load("@rules_shell//shell:sh_test.bzl", "sh_test")\n\nexports_files(["run_single_test.sh"])\n\n'

    for test_case in test_cases:
        name = test_case["name"]

        # Replace slashes, dashes, and dots to create a clean, valid Bazel target name
        target_name = name.replace("/", "_").replace("-", "_").replace(".", "_")

        # Write individual test config JSON to the external repository
        json_filename = target_name + ".json"
        repository_ctx.file(json_filename, json.encode(test_case))

        # Resolve test file relative path to the workspace root
        file_path_abs = test_case["file_path"]
        workspace_dir_str = str(workspace_dir)
        external_repo_dir_str = str(repository_ctx.path("."))

        if file_path_abs.startswith(workspace_dir_str):
            relative_path = file_path_abs.replace(workspace_dir_str + "/", "")
            test_file_label = "@//:" + relative_path
        elif file_path_abs.startswith(external_repo_dir_str):
            relative_path = file_path_abs.replace(external_repo_dir_str + "/", "")
            test_file_label = ":" + relative_path
        else:
            fail("Test file is neither in workspace nor in external repository: " + file_path_abs)

        # Generate the individual sh_test target
        build_content += """
sh_test(
    name = "{target_name}",
    srcs = [":run_single_test.sh"],
    data = [
        "@//pkg/test_runner/bin:run_single_test.dart",
        "@//tools/sdks/dart-sdk:sdk_files",
        "@//tools/sdks/dart-sdk:bin/dart",
        "{test_file_label}",
        ":{json_filename}",
    ],
    args = ["--config-json=$(location :{json_filename})"],
)
""".format(
            target_name = target_name,
            test_file_label = test_file_label,
            json_filename = json_filename,
        )

    repository_ctx.file("BUILD.bazel", content = build_content)

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
    },
)

# Bzlmod module extension wrapper to instantiate the test repository
def _test_ext_impl(ctx):
    # 1. VM JIT Release (default)
    dynamic_test_repository(
        name = "dart_tests",
        suites = [
            "language",
            "corelib",
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
        ],
        mode = "debug",
        compiler = "dartk",
        runtime = "vm",
    )

dart_tests_extension = module_extension(implementation = _test_ext_impl)
