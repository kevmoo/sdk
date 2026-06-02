// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

void main(List<String> args) async {
  String? workspaceDir;
  String? outputDir;
  String? mode;
  String? compiler;
  String? runtime;
  final suites = <String>[];
  final extraFlags = <String>[];

  for (final arg in args) {
    if (arg.startsWith('--workspace-dir=')) {
      workspaceDir = arg.substring('--workspace-dir='.length);
    } else if (arg.startsWith('--output-dir=')) {
      outputDir = arg.substring('--output-dir='.length);
    } else if (arg.startsWith('--mode=')) {
      mode = arg.substring('--mode='.length);
    } else if (arg.startsWith('--compiler=')) {
      compiler = arg.substring('--compiler='.length);
    } else if (arg.startsWith('--runtime=')) {
      runtime = arg.substring('--runtime='.length);
    } else if (arg.startsWith('--suite=')) {
      suites.add(arg.substring('--suite='.length));
    } else if (arg.startsWith('--extra-flag=')) {
      extraFlags.add(arg.substring('--extra-flag='.length));
    }
  }

  if (workspaceDir == null ||
      outputDir == null ||
      mode == null ||
      compiler == null ||
      runtime == null) {
    print(
        'Usage: generate_test_targets.dart --workspace-dir=<dir> --output-dir=<dir> --mode=<mode> --compiler=<compiler> --runtime=<runtime>');
    exit(2);
  }

  final dartPath = '$workspaceDir/tools/sdks/dart-sdk/bin/dart';
  final exporterPath = '$workspaceDir/pkg/test_runner/bin/test_runner.dart';

  if (!File(dartPath).existsSync()) {
    print('Error: Could not locate prebuilt Dart SDK at: $dartPath');
    exit(2);
  }
  if (!File(exporterPath).existsSync()) {
    print('Error: Could not locate test runner script at: $exporterPath');
    exit(2);
  }

  // 1. Write root BUILD.bazel to outputDir
  final rootBuild = File('$outputDir/BUILD.bazel');
  rootBuild.writeAsStringSync('''exports_files(
    glob(
        [
            "run_single_test.sh",
            "xcodebuild/**/*.dart",
            "xcodebuild/**/*.json",
            "out/**/*.dart",
            "out/**/*.json",
        ],
        allow_empty = True,
    ),
)
''');

  // 2. Run dry-run exporter natively
  final jsonOutputPath = '$outputDir/test_metadata_all.json';
  final processArgs = [
    exporterPath,
    '-m',
    mode,
    '-c',
    compiler,
    '-r',
    runtime,
    '--dump-test-metadata=$jsonOutputPath',
    ...extraFlags,
    ...suites,
  ];

  final res = await Process.run(dartPath, processArgs);
  if (res.exitCode != 0) {
    print('Error: Failed to dump test metadata:\n${res.stderr}\n${res.stdout}');
    exit(2);
  }

  final jsonFile = File(jsonOutputPath);
  if (!jsonFile.existsSync()) {
    print('Error: Test metadata file not created at: $jsonOutputPath');
    exit(2);
  }

  // 3. Parse test cases (extremely fast in Dart!)
  final content = jsonFile.readAsStringSync();
  final dynamic decoded = jsonDecode(content);
  final testCases = List<Map<String, dynamic>>.from(
      decoded.map((dynamic x) => x as Map<String, dynamic>));

  // 4. Group test cases by parent directory package (max 2 levels)
  final groups = <String, List<Map<String, dynamic>>>{};
  for (final tc in testCases) {
    final name = tc['name'] as String;
    if (name == 'standalone/check_for_aot_snapshot_jit_test') continue;

    final parts = name.split('/');
    String pkgDir;
    if (parts.length >= 2) {
      pkgDir = '${parts[0]}/${parts[1]}';
    } else {
      pkgDir = '${parts[0]}/misc';
    }

    groups.putIfAbsent(pkgDir, () => []).add(tc);
  }

  // 5. Write directory BUILD.bazel and tests_metadata.json files
  for (final entry in groups.entries) {
    final pkgDir = entry.key;
    final cases = entry.value;

    // Ensure package directory exists
    Directory('$outputDir/$pkgDir').createSync(recursive: true);

    // Gather distinct data dependencies
    final dataDeps = {
      ':tests_metadata.json',
      '@//:dart_pkg_async_helper',
      '@//:dart_pkg_dart2js_tools',
      '@//:dart_pkg_engine',
      '@//:dart_pkg_expect',
      '@//:dart_pkg_ffi',
      '@//:dart_pkg_flute',
      '@//:dart_pkg_js',
      '@//:dart_pkg_meta',
      '@//:dart_pkg_path',
      '@//:dart_pkg_source_maps',
      '@//:package_config_json',
      '@//pkg/test_runner/bin:run_single_test.dart',
      '@//sdk:create_sdk',
    };

    if (compiler == 'fasta') {
      dataDeps.addAll({
        '@//:front_end_tool_files',
        '@//:compile_platform_tool',
        '@//runtime/vm:vm_platform',
      });
    }

    final enrichedCases = <Map<String, dynamic>>[];

    for (final tc in cases) {
      final filePathAbs = tc['file_path'] as String;
      String testFileLabel;
      String relativePath;

      if (filePathAbs.startsWith(workspaceDir)) {
        relativePath = filePathAbs.substring(workspaceDir.length + 1);
        testFileLabel = _resolveWorkspaceLabel(workspaceDir, relativePath);
      } else if (filePathAbs.startsWith(outputDir)) {
        relativePath = filePathAbs.substring(outputDir.length + 1);
        testFileLabel = '//:$relativePath';
      } else {
        print(
            'Error: Test file is neither in workspace nor in external repository: $filePathAbs');
        exit(2);
      }

      // Map test-declared shared objects dynamically
      var hasUnsupportedSo = false;
      final sharedObjects =
          List<String>.from(tc['shared_objects'] as List? ?? []);
      final activeSoDeps = <String>{};
      for (final so in sharedObjects) {
        if (so == 'ffi_test_functions') {
          activeSoDeps.add('@//runtime/bin:libffi_test_functions.so');
        } else if (so == 'ffi_test_dynamic_library') {
          activeSoDeps.add('@//runtime/bin:libffi_test_dynamic_library.so');
        } else if (so == 'ffi_native_test_module') {
          activeSoDeps.add('@//utils/dart2wasm:ffi_native_test_wasm_module');
        } else {
          hasUnsupportedSo = true;
          break;
        }
      }
      if (hasUnsupportedSo) continue;

      dataDeps.add(testFileLabel);
      dataDeps.addAll(activeSoDeps);

      if (relativePath.contains('socket_sigpipe_test') ||
          relativePath.contains('/ffi/')) {
        dataDeps.add('@//runtime/bin:libffi_test_functions.so');
        dataDeps.add('@//runtime/bin:libffi_test_dynamic_library.so');
      }

      // Enrich and add test case copy
      final tcCopy = Map<String, dynamic>.from(tc);
      tcCopy['relative_file_path'] = relativePath;
      tcCopy['compiler'] = compiler;
      enrichedCases.add(tcCopy);

      final origFilePath = tc['original_file_path'] as String? ?? filePathAbs;
      final testDir = File(origFilePath).parent.path;
      final otherResources =
          List<String>.from(tc['other_resources'] as List? ?? []);

      for (final resource in otherResources) {
        final resourcePath = _normalizeAbsolutePath('$testDir/$resource');
        if (resourcePath.startsWith(workspaceDir)) {
          final relResPath = resourcePath.substring(workspaceDir.length + 1);
          dataDeps.add(_resolveWorkspaceLabel(workspaceDir, relResPath));
        } else if (resourcePath.startsWith(outputDir)) {
          final relResPath = resourcePath.substring(outputDir.length + 1);
          dataDeps.add('//:$relResPath');
        }
      }
    }

    if (enrichedCases.isEmpty) continue;

    // Write consolidated JSON metadata file
    final pkgJson = File('$outputDir/$pkgDir/tests_metadata.json');
    pkgJson.writeAsStringSync(jsonEncode(enrichedCases));

    if (runtime == 'd8' || compiler == 'dart2wasm') {
      dataDeps.addAll({
        '@//third_party/d8:d8_files',
        '@//:pkg/dart2wasm/bin/run_wasm.js',
      });
    }

    if (['chrome', 'chromeOnAndroid', 'chromedriver'].contains(runtime)) {
      if (Directory('$workspaceDir/third_party/browsers/chrome').existsSync()) {
        dataDeps.add('@//third_party/browsers/chrome:chrome_files');
      }
    } else if (['firefox', 'jsshell'].contains(runtime)) {
      if (Directory('$workspaceDir/third_party/browsers/firefox')
          .existsSync()) {
        dataDeps.add('@//third_party/browsers/firefox:firefox_files');
      }
    } else if (runtime == 'firefox_jsshell') {
      if (Directory('$workspaceDir/third_party/firefox_jsshell').existsSync()) {
        dataDeps.add('@//third_party/firefox_jsshell:firefox_jsshell_files');
      }
    }

    final dataListStr = dataDeps.map((d) => '        "$d"').join(',\n');
    var shardCount = enrichedCases.length ~/ 12;
    if (shardCount < 1) {
      shardCount = 1;
    } else if (shardCount > 50) {
      shardCount = 50;
    }

    final pkgBuild = File('$outputDir/$pkgDir/BUILD.bazel');
    pkgBuild
        .writeAsStringSync('''load("@rules_shell//shell:sh_test.bzl", "sh_test")

sh_test(
    name = "tests",
    srcs = ["//:run_single_test.sh"],
    data = [
$dataListStr
    ],
    args = ["--config-json=\$(location :tests_metadata.json)"],
    shard_count = $shardCount,
)
''');
  }

  // Clean up temporary full dump JSON to save disk space
  if (jsonFile.existsSync()) {
    jsonFile.deleteSync();
  }

  exit(0);
}

String _resolveWorkspaceLabel(String workspaceDir, String relResPath) {
  final parts = relResPath.split('/');
  final dirParts = parts.sublist(0, parts.length - 1);

  var bestI = 0;

  for (var i = 1; i <= dirParts.length; i++) {
    final pkgPath = '$workspaceDir/${dirParts.sublist(0, i).join('/')}';
    if (File('$pkgPath/BUILD.bazel').existsSync() ||
        File('$pkgPath/BUILD').existsSync()) {
      bestI = i;
    }
  }

  if (bestI == 0) {
    return '@//:$relResPath';
  } else {
    final packageName = dirParts.sublist(0, bestI).join('/');
    final relToPackage = parts.sublist(bestI).join('/');
    return '@//$packageName:$relToPackage';
  }
}

String _normalizeAbsolutePath(String path) {
  final parts = path.split('/');
  final result = <String>[];
  for (final part in parts) {
    if (part == '..') {
      if (result.isNotEmpty) {
        result.removeLast();
      }
    } else if (part == '.' || part == '') {
      // skip
    } else {
      result.add(part);
    }
  }
  return '/' + result.join('/');
}
