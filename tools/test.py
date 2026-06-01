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


def ResolveConfig(named_config):
    repo_name = 'dart_tests'
    injected_flags = []

    if not named_config:
        return repo_name, injected_flags

    config_lower = named_config.lower()

    is_wasm = 'wasm' in config_lower or 'dart2wasm' in config_lower
    is_debug = 'debug' in config_lower
    is_product = 'product' in config_lower

    if is_wasm:
        repo_name = 'dart_tests_wasm_d8'
    elif is_debug:
        repo_name = 'dart_tests_vm_debug'
        injected_flags.append('--//build/config:dart_debug=true')
    elif is_product:
        repo_name = 'dart_tests_vm_product'
        injected_flags.append('--//build/config:dart_product=true')
    else:
        repo_name = 'dart_tests'

    return repo_name, injected_flags


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

    repo_name, injected_flags = ResolveConfig(named_config)

    selectors = []
    bazel_flags = []
    i = 0
    while i < len(remaining_args):
        arg = remaining_args[i]
        if arg == '-v' or arg == '--verbose':
            bazel_flags.append('--test_output=streamed')
            i += 1
        elif arg == '--test-output=all':
            bazel_flags.append('--test_output=all')
            i += 1
        elif arg == '--test-output=errors':
            bazel_flags.append('--test_output=errors')
            i += 1
        elif arg.startswith('--test-output='):
            val = arg.split('=', 1)[1]
            bazel_flags.append(f'--test_output={val}')
            i += 1
        elif arg == '-j' or arg == '--workers':
            if i + 1 < len(remaining_args):
                bazel_flags.append(f'--local_test_jobs={remaining_args[i+1]}')
                i += 2
            else:
                i += 1
        elif arg.startswith('--workers='):
            val = arg.split('=', 1)[1]
            bazel_flags.append(f'--local_test_jobs={val}')
            i += 1
        elif arg.startswith('-j'):
            val = arg[2:]
            bazel_flags.append(f'--local_test_jobs={val}')
            i += 1
        elif arg == '--test-filter':
            if i + 1 < len(remaining_args):
                bazel_flags.append(f'--test_filter={remaining_args[i+1]}')
                i += 2
            else:
                i += 1
        elif arg.startswith('--test-filter='):
            val = arg.split('=', 1)[1]
            bazel_flags.append(f'--test_filter={val}')
            i += 1
        elif arg == '--repeat':
            if i + 1 < len(remaining_args):
                bazel_flags.append(f'--runs_per_test={remaining_args[i+1]}')
                i += 2
            else:
                i += 1
        elif arg.startswith('--repeat='):
            val = arg.split('=', 1)[1]
            bazel_flags.append(f'--runs_per_test={val}')
            i += 1
        elif arg.startswith('-'):
            # Skip unsupported test runner flags
            i += 1
        else:
            selectors.append(arg)
            i += 1

    if not selectors:
        print("Error: Bazel test delegation requires at least one test selector (e.g., 'web/wasm/simd/vector_test').")
        return 1

    # Query all targets in the dynamic test repository
    query_command = [utils.ResolveBazelPath(), 'query', f'@{repo_name}//:all']
    process = subprocess.Popen(query_command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    out, err = process.communicate()
    if process.returncode != 0:
        print(f"Error: Failed to query Bazel targets for repository '@{repo_name}'. Make sure the named configuration is valid.")
        return 1
    all_targets = [t.strip() for t in out.decode('utf-8').splitlines() if t.strip()]

    bazel_targets = []
    for selector in selectors:
        name = selector
        if name.startswith('tests/'):
            name = name[len('tests/'):]
        if name.endswith('.dart'):
            name = name[:-len('.dart')]

        target_name = name.replace("/", "_").replace("-", "_").replace(".", "_")
        
        exact_target = f"@{repo_name}//:{target_name}"
        prefix_target = f"@{repo_name}//:{target_name}_"
        
        if exact_target in all_targets:
            bazel_targets.append(exact_target)
        else:
            # Check if the selector acts as a directory prefix
            matches = [t for t in all_targets if t.startswith(prefix_target)]
            if matches:
                bazel_targets.extend(matches)
            else:
                print(f"Warning: No matching Bazel test targets found for selector '{selector}' under configuration '{repo_name}'")

    if not bazel_targets:
        print("Error: No valid Bazel test targets were resolved from the selectors.")
        return 1

    bazel_command = [utils.ResolveBazelPath(), 'test'] + injected_flags + bazel_flags + bazel_targets
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
