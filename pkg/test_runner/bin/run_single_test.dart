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

    final executable = cmd['executable'] as String;
    final arguments = List<String>.from(cmd['arguments'] as List);
    final workingDirectory = cmd['working_directory'] as String?;
    final environment = cmd['environment'] != null
        ? Map<String, String>.from(cmd['environment'] as Map)
        : null;

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
