// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

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
    exitCode = 2;
    return;
  }

  final debugLog = File('$outputDir/debug.log');
  final debugBuf = StringBuffer();
  debugBuf.writeln('=== Debug Log ===');
  debugBuf.writeln('Workspace Dir: $workspaceDir');
  debugBuf.writeln('Output Dir: $outputDir');
  debugBuf.writeln('Compiler: $compiler');
  debugBuf.writeln('Runtime: $runtime');

  final dartPath = '$workspaceDir/tools/sdks/dart-sdk/bin/dart';
  final exporterPath = '$workspaceDir/pkg/test_runner/bin/test_runner.dart';

  if (!File(dartPath).existsSync()) {
    debugBuf.writeln('Error: Could not locate prebuilt Dart SDK at: $dartPath');
    debugLog.writeAsStringSync(debugBuf.toString());
    exitCode = 2;
    return;
  }
  if (!File(exporterPath).existsSync()) {
    debugBuf.writeln(
        'Error: Could not locate test runner script at: $exporterPath');
    debugLog.writeAsStringSync(debugBuf.toString());
    exitCode = 2;
    return;
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
    debugBuf.writeln(
        'Error: Failed to dump test metadata:\n${res.stderr}\n${res.stdout}');
    debugLog.writeAsStringSync(debugBuf.toString());
    exitCode = 2;
    return;
  }

  final jsonFile = File(jsonOutputPath);
  if (!jsonFile.existsSync()) {
    debugBuf
        .writeln('Error: Test metadata file not created at: $jsonOutputPath');
    debugLog.writeAsStringSync(debugBuf.toString());
    exitCode = 2;
    return;
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

    final testImportsFile = File('$workspaceDir/$pkgDir/test_imports.json');
    final hasFineGrained = testImportsFile.existsSync();

    Map<String, dynamic>? testImportsMap;
    if (hasFineGrained) {
      testImportsMap = jsonDecode(testImportsFile.readAsStringSync())
          as Map<String, dynamic>;
    }

    final filegroups = <String, Set<String>>{};

    // Baseline dependencies (common to all tests in this package)
    final baselineDeps = {
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

    // Find non-Dart package resources and bundle them into a shared filegroup
    if (hasFineGrained) {
      final resources = _findPackageResources(workspaceDir, pkgDir);
      if (resources.isNotEmpty) {
        final fgName = 'fg_package_resources';
        for (final res in resources) {
          filegroups
              .putIfAbsent(fgName, () => {})
              .add(_resolveWorkspaceLabel(workspaceDir, res));
        }
        baselineDeps.add(':$fgName');
      }
    }

    // Map known pubspec package dependencies to their tool entry point files if they exist in root exports
    final toolEntryPoints = {
      'analyzer_cli': '@//:pkg/analyzer_cli/bin/analyzer.dart',
      'front_end': '@//:pkg/front_end/tool/compile.dart',
      'analysis_server': '@//:pkg/analysis_server/bin/server.dart',
      'frontend_server':
          '@//:pkg/frontend_server/bin/frontend_server_starter.dart',
      'dartdev': '@//:pkg/dartdev/bin/dartdev.dart',
      'dds': '@//:pkg/dds/bin/dds.dart',
    };

    // Transitive package closures required by specific tool packages in the sandbox
    final toolExtraPackages = {
      'analyzer_cli': {
        '@//:dart_pkg_analyzer',
        '@//:dart_pkg_convert',
        '@//:dart_pkg_glob',
        '@//:dart_pkg_pub_semver',
        '@//:dart_pkg_source_span',
        '@//:dart_pkg_watcher',
        '@//:dart_pkg_yaml',
      },
      'analyzer': {
        '@//:dart_pkg_convert',
        '@//:dart_pkg_glob',
        '@//:dart_pkg_pub_semver',
        '@//:dart_pkg_source_span',
        '@//:dart_pkg_watcher',
        '@//:dart_pkg_yaml',
      },
    };

    // Dynamically add pubspec dependencies to baselineDeps
    final pubspecPath = '$workspaceDir/$pkgDir/pubspec.yaml';
    debugBuf.writeln('Processing package: $pkgDir');
    debugBuf.writeln('  Pubspec Path: $pubspecPath');

    final pubspecDeps = _parsePubspecDependencies(pubspecPath, debugBuf);
    debugBuf.writeln('  Parsed Deps: $pubspecDeps');

    final parts = pkgDir.split('/');
    final pkgName = parts.length >= 2 ? parts[1] : null;

    for (final dep in pubspecDeps) {
      if (dep == pkgName) continue;
      baselineDeps.add('@//:dart_pkg_$dep');

      final entryPoint = toolEntryPoints[dep];
      if (entryPoint != null) {
        baselineDeps.add(entryPoint);
      }

      final extraPkgs = toolExtraPackages[dep];
      if (extraPkgs != null) {
        baselineDeps.addAll(extraPkgs);
      }
    }

    if (compiler == 'fasta') {
      baselineDeps.addAll({
        '@//:front_end_tool_files',
        '@//:compile_platform_tool',
        '@//runtime/vm:vm_platform',
      });
    }

    if (runtime == 'd8' || compiler == 'dart2wasm') {
      baselineDeps.addAll({
        '@//third_party/d8:d8_files',
        '@//:pkg/dart2wasm/bin/run_wasm.js',
      });
    }

    if (['chrome', 'chromeOnAndroid', 'chromedriver'].contains(runtime)) {
      if (Directory('$workspaceDir/third_party/browsers/chrome').existsSync()) {
        baselineDeps.add('@//third_party/browsers/chrome:chrome_files');
      }
    } else if (['firefox', 'jsshell'].contains(runtime)) {
      if (Directory('$workspaceDir/third_party/browsers/firefox')
          .existsSync()) {
        baselineDeps.add('@//third_party/browsers/firefox:firefox_files');
      }
    } else if (runtime == 'firefox_jsshell') {
      if (Directory('$workspaceDir/third_party/firefox_jsshell').existsSync()) {
        baselineDeps
            .add('@//third_party/firefox_jsshell:firefox_jsshell_files');
      }
    }

    final enrichedCases = <Map<String, dynamic>>[];
    final individualTargets = <String>[];

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
        debugBuf.writeln(
            'Error: Test file is neither in workspace nor in external repository: $filePathAbs');
        debugLog.writeAsStringSync(debugBuf.toString());
        exitCode = 2;
        return;
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

      if (relativePath.contains('socket_sigpipe_test') ||
          relativePath.contains('/ffi/')) {
        activeSoDeps.add('@//runtime/bin:libffi_test_functions.so');
        activeSoDeps.add('@//runtime/bin:libffi_test_dynamic_library.so');
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
      final resolvedResources = <String>{};
      final resourceDeps = <String>{};

      for (final resource in otherResources) {
        final resourcePath = p.posix.normalize('$testDir/$resource');
        if (resourcePath.startsWith(workspaceDir)) {
          final relResPath = resourcePath.substring(workspaceDir.length + 1);
          resolvedResources
              .add(_resolveWorkspaceLabel(workspaceDir, relResPath));
          if (hasFineGrained) {
            final relResInPkg = relResPath.substring(pkgDir.length + 1);
            final resDeps =
                _computeTransitiveClosure(relResInPkg, testImportsMap!);
            for (final dep in resDeps) {
              final fgName = _getFilegroupTargetName(dep);
              final label =
                  _resolveWorkspaceLabel(workspaceDir, '$pkgDir/$dep');
              filegroups.putIfAbsent(fgName, () => {}).add(label);
              resourceDeps.add(':$fgName');
            }
          }
        } else if (resourcePath.startsWith(outputDir)) {
          final relResPath = resourcePath.substring(outputDir.length + 1);
          resolvedResources.add('//:$relResPath');
        }
      }

      if (hasFineGrained) {
        final relPathInPkg = relativePath.substring(pkgDir.length + 1);
        final targetName = _toTargetName(relPathInPkg);

        final targetDeps = <String>{
          ...baselineDeps,
          testFileLabel,
          ...activeSoDeps,
          ...resolvedResources,
          ...resourceDeps,
        };

        final localDeps =
            _computeTransitiveClosure(relPathInPkg, testImportsMap!);
        for (final dep in localDeps) {
          final fgName = _getFilegroupTargetName(dep);
          final label = _resolveWorkspaceLabel(workspaceDir, '$pkgDir/$dep');
          filegroups.putIfAbsent(fgName, () => {}).add(label);
          targetDeps.add(':$fgName');
        }

        // Package-wide tests (such as package static analysis/doc tests) that require the entire lib/ target of the package
        final packageWideTests = {
          'pkg/compiler': {
            'test/analyses/analyze_test.dart',
            'test/analyses/api_dynamic_test.dart',
          },
          'pkg/analyzer': {
            'test/verify_docs_test.dart',
          },
        };
        final pWideTests = packageWideTests[pkgDir];
        if (pWideTests != null && pWideTests.contains(relPathInPkg)) {
          final parts = pkgDir.split('/');
          if (parts.length >= 2) {
            final pkgName = parts[1];
            targetDeps.add('@//:dart_pkg_$pkgName');
          }
        }

        final targetDepsStr = targetDeps.map((d) => '        "$d"').join(',\n');
        individualTargets.add('''sh_test(
    name = "$targetName",
    srcs = ["//:run_single_test.sh"],
    data = [
$targetDepsStr
    ],
    args = [
        "--config-json=\$(location :tests_metadata.json)",
        "--run-only=$relPathInPkg",
    ],
)''');
      }
    }

    if (enrichedCases.isEmpty) continue;

    // Write consolidated JSON metadata file
    final pkgJson = File('$outputDir/$pkgDir/tests_metadata.json');
    pkgJson.writeAsStringSync(jsonEncode(enrichedCases));

    final pkgBuild = File('$outputDir/$pkgDir/BUILD.bazel');

    if (hasFineGrained) {
      final filegroupsStr = StringBuffer();
      final sortedFgNames = filegroups.keys.toList()..sort();
      for (final fgName in sortedFgNames) {
        final srcs = filegroups[fgName]!.toList()..sort();
        final srcsStr = srcs.map((s) => '        "$s"').join(',\n');
        filegroupsStr.writeln('''filegroup(
    name = "$fgName",
    srcs = [
$srcsStr
    ],
)
''');
      }

      final targetsStr = individualTargets.join('\n\n');
      pkgBuild.writeAsStringSync(
          '''load("@rules_shell//shell:sh_test.bzl", "sh_test")
 
$filegroupsStr

$targetsStr
''');
    } else {
      final dataDeps = {
        ...baselineDeps,
      };
      if (pkgDir.startsWith('pkg/')) {
        final parts = pkgDir.split('/');
        if (parts.length >= 2) {
          final pkgName = parts[1];
          dataDeps.add('@//:dart_pkg_$pkgName');
        }
      }

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
          continue;
        }
        dataDeps.add(testFileLabel);

        final sharedObjects =
            List<String>.from(tc['shared_objects'] as List? ?? []);
        for (final so in sharedObjects) {
          if (so == 'ffi_test_functions') {
            dataDeps.add('@//runtime/bin:libffi_test_functions.so');
          } else if (so == 'ffi_test_dynamic_library') {
            dataDeps.add('@//runtime/bin:libffi_test_dynamic_library.so');
          } else if (so == 'ffi_native_test_module') {
            dataDeps.add('@//utils/dart2wasm:ffi_native_test_wasm_module');
          }
        }

        if (relativePath.contains('socket_sigpipe_test') ||
            relativePath.contains('/ffi/')) {
          dataDeps.add('@//runtime/bin:libffi_test_functions.so');
          dataDeps.add('@//runtime/bin:libffi_test_dynamic_library.so');
        }

        final origFilePath = tc['original_file_path'] as String? ?? filePathAbs;
        final testDir = File(origFilePath).parent.path;
        final otherResources =
            List<String>.from(tc['other_resources'] as List? ?? []);
        for (final resource in otherResources) {
          final resourcePath = p.posix.normalize('$testDir/$resource');
          if (resourcePath.startsWith(workspaceDir)) {
            final relResPath = resourcePath.substring(workspaceDir.length + 1);
            dataDeps.add(_resolveWorkspaceLabel(workspaceDir, relResPath));
          } else if (resourcePath.startsWith(outputDir)) {
            final relResPath = resourcePath.substring(outputDir.length + 1);
            dataDeps.add('//:$relResPath');
          }
        }
      }

      final dataListStr = dataDeps.map((d) => '        "$d"').join(',\n');
      var shardCount = enrichedCases.length ~/ 12;
      if (shardCount < 1) {
        shardCount = 1;
      } else if (shardCount > 50) {
        shardCount = 50;
      }

      pkgBuild.writeAsStringSync(
          '''load("@rules_shell//shell:sh_test.bzl", "sh_test")
 
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
  }

  // Clean up temporary full dump JSON to save disk space
  if (jsonFile.existsSync()) {
    jsonFile.deleteSync();
  }

  debugBuf.writeln('=== Generation Completed Successfully ===');
  debugLog.writeAsStringSync(debugBuf.toString());
  return;
}

final _buildDirCache = <String, bool>{};
final _labelCache = <String, String>{};

bool _dirHasBuildFile(String dirPath) {
  return _buildDirCache.putIfAbsent(dirPath, () {
    return File('$dirPath/BUILD.bazel').existsSync() ||
        File('$dirPath/BUILD').existsSync();
  });
}

String _resolveWorkspaceLabel(String workspaceDir, String relResPath) {
  return _labelCache.putIfAbsent(relResPath, () {
    final normPath = p.posix.normalize(relResPath);
    final dirname = p.posix.dirname(normPath);
    final dirParts = (dirname == '.' || dirname.isEmpty)
        ? <String>[]
        : p.posix.split(dirname);

    var bestI = 0;

    for (var i = 1; i <= dirParts.length; i++) {
      final pkgSubPath = p.posix.joinAll(dirParts.sublist(0, i));
      final pkgPath = '$workspaceDir/$pkgSubPath';
      if (_dirHasBuildFile(pkgPath)) {
        bestI = i;
      }
    }

    if (bestI == 0) {
      return '@//:$normPath';
    } else {
      final packageName = p.posix.joinAll(dirParts.sublist(0, bestI));
      final relToPackage = p.posix.relative(normPath, from: packageName);
      return '@//$packageName:$relToPackage';
    }
  });
}

String _toTargetName(String relPath) {
  var name = relPath;
  if (name.endsWith('.dart')) {
    name = name.substring(0, name.length - 5);
  }
  return name.replaceAll('/', '_');
}

Set<String> _parsePubspecDependencies(
    String pubspecPath, StringBuffer debugBuf) {
  final deps = <String>{};
  final file = File(pubspecPath);
  if (!file.existsSync()) {
    debugBuf.writeln('    Pubspec file does not exist at: $pubspecPath');
    return deps;
  }

  final content = file.readAsStringSync();
  final lines = content.split('\n');

  var inDepsSection = false;

  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.startsWith('#')) continue;

    if (line.startsWith('dependencies:') ||
        line.startsWith('dev_dependencies:')) {
      inDepsSection = true;
      continue;
    }

    if (inDepsSection) {
      if (line.isEmpty) continue;

      // If the line is not indented, we have left the dependencies section
      if (!line.startsWith(' ') && !line.startsWith('\t')) {
        inDepsSection = false;
        // It could be that we immediately enter the other deps section
        if (line.startsWith('dependencies:') ||
            line.startsWith('dev_dependencies:')) {
          inDepsSection = true;
        }
        continue;
      }

      final leadingSpaces = line.length - line.trimLeft().length;
      if (leadingSpaces > 3) {
        continue; // Skip nested configuration
      }

      final parts = trimmed.split(':');
      if (parts.isNotEmpty) {
        final depName = parts[0].trim();
        if (depName.isNotEmpty) {
          deps.add(depName);
        }
      }
    }
  }
  return deps;
}

String _getFilegroupTargetName(String dep) {
  final parts = dep.split('/');
  if (parts.length <= 1) {
    return 'fg_root';
  }
  final dirParts = parts.sublist(0, parts.length - 1);
  return 'fg_${dirParts.join('_').replaceAll('.', '_').replaceAll('-', '_')}';
}

List<String> _findPackageResources(String workspaceDir, String pkgDir) {
  final dir = Directory('$workspaceDir/$pkgDir');
  if (!dir.existsSync()) return [];

  final resources = <String>[];
  final allowedExtensions = {
    '.json',
    '.yaml',
    '.options',
    '.config',
    '.txt',
    '.status',
    '.properties',
    '.csv',
    '.xml',
    '.dill',
    '.bin',
    '.dart_fn',
  };

  for (final entity in dir.listSync(recursive: true)) {
    if (entity is File) {
      final path = entity.path.replaceAll('\\', '/');
      final parts = path.split('/');

      // Skip hidden directories or files (starting with .)
      if (parts.any((p) => p.startsWith('.'))) continue;
      if (parts.contains('doc')) continue; // skip docs

      final filename = parts.last;
      if (filename == 'BUILD' ||
          filename == 'BUILD.bazel' ||
          filename == 'OWNERS') {
        continue;
      }

      // Check if the file has a resource extension
      final dotIndex = filename.lastIndexOf('.');
      if (dotIndex != -1) {
        final ext = filename.substring(dotIndex);
        if (allowedExtensions.contains(ext.toLowerCase())) {
          final relPath = path.substring(workspaceDir.length + 1);
          resources.add(relPath);
        }
      }
    }
  }
  return resources;
}

List<String> _computeTransitiveClosure(
    String startFile, Map<String, dynamic> directDepsMap) {
  final closure = <String>{};
  final visiting = <String>{startFile};

  void dfs(String node) {
    final deps = directDepsMap[node] as List?;
    if (deps == null) return;

    for (final dep in deps) {
      final depStr = dep as String;
      if (closure.contains(depStr)) continue;
      if (visiting.contains(depStr)) continue;

      closure.add(depStr);
      visiting.add(depStr);
      dfs(depStr);
      visiting.remove(depStr);
    }
  }

  dfs(startFile);
  return closure.toList()..sort();
}
