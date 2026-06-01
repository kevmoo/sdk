#!/usr/bin/env python3
# Copyright (c) 2011, the Dart project authors.  Please see the AUTHORS file
# for details. All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.

from contextlib import ExitStack
import os
import string
import subprocess
import sys

import utils


def TestWithBazel(args):
    named_config = None
    remaining_args = []
    i = 0
    while i < len(args):
        arg = args[i]
        if arg == '-n' or arg == '--named-configuration':
            if i + 1 < len(args):
                named_config = args[i+1]
                i += 2
                continue
        elif arg.startswith('--named-configuration='):
            named_config = arg.split('=', 1)[1]
            i += 1
            continue
        remaining_args.append(arg)
        i += 1

    repo_name = 'dart_tests'
    if named_config:
        if 'wasm' in named_config or 'dart2wasm' in named_config:
            repo_name = 'dart_tests_wasm_d8'
        elif 'debug' in named_config and ('vm' in named_config or 'dartk' in named_config):
            repo_name = 'dart_tests_vm_debug'
        elif 'release' in named_config:
            repo_name = 'dart_tests'

    selectors = []
    for arg in remaining_args:
        if not arg.startswith('-'):
            selectors.append(arg)

    if not selectors:
        print("Error: Bazel test delegation requires at least one test selector (e.g., 'web/wasm/simd/vector_test').")
        return 1

    bazel_targets = []
    for selector in selectors:
        name = selector
        if name.startswith('tests/'):
            name = name[len('tests/'):]
        if name.endswith('.dart'):
            name = name[:-len('.dart')]

        target_name = name.replace("/", "_").replace("-", "_").replace(".", "_")
        bazel_targets.append(f"@{repo_name}//:{target_name}")

    bazel_command = ['bazel', 'test'] + bazel_targets
    print('Running Bazel Tests: ' + ' '.join(bazel_command))
    process = subprocess.Popen(bazel_command)
    process.wait()
    return process.returncode


def Main():
    args = sys.argv[1:]

    use_bazel = False
    if '--bazel' in args:
        args.remove('--bazel')
        use_bazel = True

    if use_bazel:
        return TestWithBazel(args)

    cleanup_dart = False
    if '--cleanup-dart-processes' in args:
        args.remove('--cleanup-dart-processes')
        cleanup_dart = True

    tools_dir = os.path.dirname(os.path.realpath(__file__))
    repo_dir = os.path.dirname(tools_dir)
    dart_test_script = os.path.join(repo_dir, 'pkg', 'test_runner', 'bin',
                                    'test_runner.dart')
    command = [utils.CheckedInSdkExecutable(), dart_test_script] + args

    # The testing script potentially needs the android platform tools in PATH so
    # we do that in ./tools/test.py (a similar logic exists in ./tools/build.py).
    android_platform_tools = os.path.normpath(
        os.path.join(tools_dir,
                     '../third_party/android_tools/sdk/platform-tools'))
    if os.path.isdir(android_platform_tools):
        os.environ['PATH'] = '%s%s%s' % (os.environ['PATH'], os.pathsep,
                                         android_platform_tools)

    with utils.FileDescriptorLimitIncreaser():
        with ExitStack() as stack:
            for ctx in utils.CoreDumpArchiver(args):
                stack.enter_context(ctx)
            exit_code = subprocess.call(command)

    if cleanup_dart:
        cleanup_command = [
            sys.executable,
            os.path.join(tools_dir, 'task_kill.py'), '--kill_dart=True',
            '--kill_vc=False'
        ]
        subprocess.call(cleanup_command)

    utils.DiagnoseExitCode(exit_code, command)
    return exit_code


if __name__ == '__main__':
    sys.exit(Main())
