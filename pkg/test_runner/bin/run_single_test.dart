// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

/// A standalone zero-dependency runner that executes a single test configuration
/// and maps process exit codes to expectations, returning exit code 0 on match
/// and 1 on mismatch.
void main(List<String> args) async {
  String? configPath;
  for (var i = 0; i < args.length; i++) {
    if (args[i].startsWith('--config-json=')) {
      configPath = args[i].substring('--config-json='.length);
    }
  }

  if (configPath == null) {
    print(
      'Usage: run_single_test.dart --config-json=<path-to-test-metadata-json>',
    );
    exit(2);
  }

  final file = File(configPath);
  if (!await file.exists()) {
    print('Error: Config file not found: $configPath');
    exit(2);
  }

  final content = await file.readAsString();
  final dynamic decoded = jsonDecode(content);
  Map<String, dynamic> testCase;
  if (decoded is List) {
    if (decoded.isEmpty) {
      print('Error: Empty test metadata list.');
      exit(2);
    }
    testCase = decoded.first as Map<String, dynamic>;
  } else {
    testCase = decoded as Map<String, dynamic>;
  }

  final testName = testCase['name'] as String;
  final filePath = testCase['file_path'] as String;
  final expectedOutcomes = List<String>.from(
    testCase['expected_outcome'] as List,
  );
  final commands = testCase['commands'] as List;

  print(
    '======================================================================',
  );
  print('Running Test: $testName');
  print('File Path:    $filePath');
  print('Expected:     $expectedOutcomes');
  print(
    '======================================================================',
  );

  var actualOutcome = 'Pass';

  for (var i = 0; i < commands.length; i++) {
    final cmd = commands[i] as Map<String, dynamic>;
    if (!cmd.containsKey('executable')) {
      print(
        'Warning: Command ${i + 1} is not executable directly: ${cmd['displayName'] ?? cmd}',
      );
      continue;
    }

    var executable = cmd['executable'] as String;
    var arguments = List<String>.from(cmd['arguments'] as List);
    final dartBinEnv = Platform.environment['DART_BIN'];
    final testSrcdir = Platform.environment['TEST_SRCDIR'];

    if (executable == 'pkg/dart2wasm/tool/compile_benchmark' &&
        testSrcdir != null) {
      final sdkDir = '$testSrcdir/_main/tools/sdks/dart-sdk';
      executable = '$sdkDir/bin/dartaotruntime';
      final newArgs = [
        '$sdkDir/bin/snapshots/dart2wasm_product.snapshot',
        '--platform=$sdkDir/lib/_internal/dart2wasm_platform.dill',
      ];
      for (final arg in arguments) {
        if (arg.startsWith('--extra-compiler-option=')) {
          newArgs.add(arg.substring('--extra-compiler-option='.length));
        } else {
          newArgs.add(arg);
        }
      }
      arguments = newArgs;
    } else if (executable == 'pkg/dart2wasm/tool/run_benchmark' &&
        testSrcdir != null) {
      final d8Bin = '$testSrcdir/_main/third_party/d8/linux/x64/d8';
      final runWasmJs = '$testSrcdir/_main/pkg/dart2wasm/bin/run_wasm.js';
      executable = d8Bin;

      var shellOptions = <String>[];
      String? wasmFile;

      for (final arg in arguments) {
        if (arg == '--d8') continue;
        if (arg.startsWith('--shell-option=')) {
          shellOptions.add(arg.substring('--shell-option='.length));
        } else if (arg.endsWith('.wasm')) {
          wasmFile = arg;
        }
      }

      if (wasmFile != null) {
        final mjsFile = wasmFile.replaceAll(RegExp(r'\.wasm$'), '.mjs');
        final newArgs = [...shellOptions, runWasmJs, '--', mjsFile, wasmFile];
        arguments = newArgs;
      }
    } else if (dartBinEnv != null) {
      if (executable == 'out/ReleaseX64/dart' || executable.endsWith('/dart')) {
        executable = dartBinEnv;
      } else if (executable.endsWith('/dartaotruntime')) {
        final sdkBinDir = File(dartBinEnv).parent.path;
        executable = '$sdkBinDir/dartaotruntime';
      }
    }
    var workingDirectory = cmd['working_directory'] as String?;
    var environment = cmd['environment'] != null
        ? Map<String, String>.from(cmd['environment'] as Map)
        : null;

    final testTmpdir = Platform.environment['TEST_TMPDIR'];
    if (testTmpdir != null) {
      arguments = arguments
          .map((arg) => _rewriteSandboxPath(arg, testTmpdir))
          .toList();
      if (workingDirectory != null) {
        workingDirectory = _rewriteSandboxPath(workingDirectory, testTmpdir);
      }
      if (environment != null) {
        final newEnv = <String, String>{};
        for (final entry in environment.entries) {
          newEnv[entry.key] = _rewriteSandboxPath(entry.value, testTmpdir);
        }
        environment = newEnv;
      }
    }

    print(
      '\n[Command ${i + 1}/${commands.length}]: $executable ${arguments.join(' ')}',
    );
    if (workingDirectory != null) {
      print('Working Directory: $workingDirectory');
    }
    if (environment != null) {
      print('Environment Overrides: $environment');
    }

    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );

    final stdoutFuture = stdout.addStream(process.stdout);
    final stderrFuture = stderr.addStream(process.stderr);
    await Future.wait([stdoutFuture, stderrFuture]);

    final exitCode = await process.exitCode;
    print('[Command ${i + 1} exited with code $exitCode]');

    if (exitCode != 0) {
      // Map non-zero exit codes to test Expectations
      if (exitCode == 254) {
        actualOutcome = 'CompileTimeError';
      } else if (exitCode < 0 || exitCode == 253 || exitCode == 252) {
        actualOutcome = 'Crash';
      } else {
        actualOutcome = 'RuntimeError';
      }
      print('\nCommand failed. Resolved actual test outcome: $actualOutcome');
      break;
    }
  }

  print('\nTest execution finished.');
  print('Actual Outcome:    $actualOutcome');
  print('Expected Outcomes: $expectedOutcomes');

  if (expectedOutcomes.contains(actualOutcome)) {
    print('RESULT: SUCCESS (Outcome matches expectations)');
    exit(0);
  } else {
    print(
      'RESULT: FAILURE (Outcome $actualOutcome does NOT match expectations)',
    );
    exit(1);
  }
}

String _rewriteSandboxPath(String path, String testTmpdir) {
  if (!path.contains('/generated_compilations/')) {
    return path;
  }

  final outReleaseIndex = path.indexOf('/out/ReleaseX64/');
  if (outReleaseIndex != -1) {
    final relativePart = path.substring(
      outReleaseIndex + '/out/ReleaseX64/'.length,
    );
    final rewritten = '$testTmpdir/out_ReleaseX64/$relativePart';
    Directory(File(rewritten).parent.path).createSync(recursive: true);
    return rewritten;
  }

  final outDebugIndex = path.indexOf('/out/DebugX64/');
  if (outDebugIndex != -1) {
    final relativePart = path.substring(
      outDebugIndex + '/out/DebugX64/'.length,
    );
    final rewritten = '$testTmpdir/out_DebugX64/$relativePart';
    Directory(File(rewritten).parent.path).createSync(recursive: true);
    return rewritten;
  }

  return path;
}
