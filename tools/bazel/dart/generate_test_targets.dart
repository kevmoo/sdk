// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Dynamic Bazel test target generator.
///
/// This script runs the Dart test runner in dry-run mode for various configurations,
/// discovers tests, and generates `BUILD.bazel` files in the external repository
/// to define sharded test targets.
///
/// Invocation:
/// dart generate_test_targets.dart --workspace-dir=`<dir>` --output-dir=`<dir>` [--suite=`<suite>`...]
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

void main(List<String> args) async {
  String? workspaceDir;
  String? outputDir;
  final suites = <String>[];

  for (final arg in args) {
    if (arg.startsWith('--workspace-dir=')) {
      workspaceDir = arg.substring('--workspace-dir='.length);
    } else if (arg.startsWith('--output-dir=')) {
      outputDir = arg.substring('--output-dir='.length);
    } else if (arg.startsWith('--suite=')) {
      suites.add(arg.substring('--suite='.length));
    }
  }

  if (workspaceDir == null || outputDir == null) {
    print(
      'Usage: generate_test_targets.dart --workspace-dir=<dir> --output-dir=<dir> [--suite=<suite>...]',
    );
    exitCode = 2;
    return;
  }

  final debugLog = File('$outputDir/debug.log');
  final debugBuf = StringBuffer();
  debugBuf.writeln('=== Debug Log ===');
  debugBuf.writeln('Workspace Dir: $workspaceDir');
  debugBuf.writeln('Output Dir: $outputDir');
  debugBuf.writeln('Suites from Starlark: $suites');

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
      'Error: Could not locate test runner script at: $exporterPath',
    );
    debugLog.writeAsStringSync(debugBuf.toString());
    exitCode = 2;
    return;
  }

  // 2. Run dry-run exporter natively for all configurations in parallel
  final futures = _configs.map((config) async {
    final activeSuites =
        config.suites.where((s) => suites.contains(s)).toList();
    if (activeSuites.isEmpty) {
      debugBuf.writeln('No active suites for config ${config.name}, skipping.');
      return (config: config, testCases: <Map<String, dynamic>>[]);
    }
    final jsonOutputPath = '$outputDir/test_metadata_${config.name}.json';
    final processArgs = [
      exporterPath,
      '-m',
      config.mode,
      '-c',
      config.compiler,
      '-r',
      config.runtime,
      '--dump-test-metadata=$jsonOutputPath',
      '--build-directory=$outputDir/out/${config.name}',
      ...config.extraFlags,
      ...activeSuites,
    ];
    debugBuf.writeln(
      'Running discovery for ${config.name}: $dartPath ${processArgs.join(' ')}',
    );
    final res = await Process.run(dartPath, processArgs);
    if (res.exitCode != 0) {
      throw Exception(
        'Failed to dump metadata for ${config.name}:\n${res.stderr}\n${res.stdout}',
      );
    }
    final jsonFile = File(jsonOutputPath);
    if (!jsonFile.existsSync()) {
      throw Exception(
        'Metadata file not created for ${config.name} at $jsonOutputPath',
      );
    }
    final content = jsonFile.readAsStringSync();
    final dynamic decoded = jsonDecode(content);
    final testCases = List<Map<String, dynamic>>.from(
      decoded.map((dynamic x) => x as Map<String, dynamic>),
    );
    jsonFile.deleteSync();
    return (config: config, testCases: testCases);
  });

  List<_ConfigResult> results;
  try {
    results = await Future.wait(futures);
  } catch (e) {
    debugBuf.writeln('Error during parallel discovery: $e');
    debugLog.writeAsStringSync(debugBuf.toString());
    exitCode = 2;
    return;
  }

  // 3. Move generated files to configuration-specific package subdirectories and group
  final packageGroups = <String, Map<String, List<Map<String, dynamic>>>>{};
  for (final res in results) {
    final configName = res.config.name;
    for (final tc in res.testCases) {
      final name = tc['name'] as String;
      if (name == 'standalone/check_for_aot_snapshot_jit_test') continue;

      final parts = name.split('/');
      String pkgDir;
      const coarseSuites = {'corelib', 'standalone', 'ffi', 'language'};
      if (parts.isNotEmpty && coarseSuites.contains(parts[0])) {
        pkgDir = parts[0];
      } else if (parts.length >= 2) {
        pkgDir = '${parts[0]}/${parts[1]}';
      } else {
        pkgDir = '${parts[0]}/misc';
      }

      // Move generated files
      final filePathAbs = tc['file_path'] as String;
      final generatedPrefix = '$outputDir/out/$configName/generated_tests/';
      if (filePathAbs.startsWith(generatedPrefix)) {
        final relativeToGenerated =
            filePathAbs.substring(generatedPrefix.length);
        final slashIndex = relativeToGenerated.indexOf('/');
        final relativePathFromSuite =
            relativeToGenerated.substring(slashIndex + 1);

        final destDir = '$outputDir/$pkgDir/gen_tests/$configName';
        final destPath = '$destDir/$relativePathFromSuite';

        Directory(p.dirname(destPath)).createSync(recursive: true);
        final file = File(filePathAbs);
        if (file.existsSync()) {
          file.renameSync(destPath);
        }

        tc['file_path'] = destPath;

        // Update arguments in commands
        final commands = tc['commands'] as List;
        for (final cmd in commands) {
          if (cmd is Map) {
            final args = cmd['arguments'] as List?;
            if (args != null) {
              for (var i = 0; i < args.length; i++) {
                if (args[i] == filePathAbs) {
                  args[i] = destPath;
                } else if (args[i].toString().contains(filePathAbs)) {
                  args[i] =
                      args[i].toString().replaceAll(filePathAbs, destPath);
                }
              }
            }
          }
        }
      }

      packageGroups
          .putIfAbsent(pkgDir, () => {})
          .putIfAbsent(configName, () => [])
          .add(tc);
    }

    // Move any remaining auxiliary files in out/ to their destinations
    final genDir = Directory('$outputDir/out/$configName/generated_tests');
    if (genDir.existsSync()) {
      for (final entity in genDir.listSync(recursive: true)) {
        if (entity is File) {
          final filePathAbs = entity.path.replaceAll('\\', '/');
          final relativeToGenerated =
              filePathAbs.substring(genDir.path.length + 1);
          final parts = relativeToGenerated.split('/');

          String pkgDir;
          String relativePathFromSuite;
          const coarseSuites = {'corelib', 'standalone', 'ffi', 'language'};

          if (parts.length >= 2 && coarseSuites.contains(parts[0])) {
            pkgDir = parts[0];
            relativePathFromSuite = parts.sublist(1).join('/');
          } else if (parts.length >= 2) {
            pkgDir = '${parts[0]}/${parts[1]}';
            relativePathFromSuite = parts.sublist(2).join('/');
          } else {
            pkgDir = '${parts[0]}/misc';
            relativePathFromSuite = parts.sublist(1).join('/');
          }

          final destDir = '$outputDir/$pkgDir/gen_tests/$configName';
          final destPath = '$destDir/$relativePathFromSuite';

          Directory(p.dirname(destPath)).createSync(recursive: true);
          entity.renameSync(destPath);
        }
      }
      try {
        genDir.deleteSync(recursive: true);
        final configOutDir = Directory('$outputDir/out/$configName');
        if (configOutDir.existsSync() && configOutDir.listSync().isEmpty) {
          configOutDir.deleteSync();
        }
        final outDir = Directory('$outputDir/out');
        if (outDir.existsSync() && outDir.listSync().isEmpty) {
          outDir.deleteSync();
        }
      } catch (_) {}
    }
  }

  // 4. Write directory BUILD.bazel and tests_metadata_<config>.json files
  for (final entry in packageGroups.entries) {
    final pkgDir = entry.key;
    final configsMap = entry.value;
    final packageWorkspaceFiles = <String>{};

    // Ensure package directory exists
    Directory('$outputDir/$pkgDir').createSync(recursive: true);

    final testImportsFile = File('$workspaceDir/$pkgDir/test_imports.json');
    final hasFineGrained = testImportsFile.existsSync();
    final useIndividualTargets = hasFineGrained;

    Map<String, dynamic>? testImportsMap;
    if (hasFineGrained) {
      testImportsMap = jsonDecode(
        testImportsFile.readAsStringSync(),
      ) as Map<String, dynamic>;
    }

    final filegroups = <String, Set<String>>{};

    // Package-wide resources (config-independent)
    if (hasFineGrained) {
      final resources = _findPackageResources(workspaceDir, pkgDir);
      if (resources.isNotEmpty) {
        final fgName = 'fg_package_resources';
        for (final res in resources) {
          filegroups
              .putIfAbsent(fgName, () => {})
              .add(_resolveWorkspaceLabel(workspaceDir, res));
        }
      }
    }

    final pubspecPath = '$workspaceDir/$pkgDir/pubspec.yaml';
    final pubspecDeps = _parsePubspecDependencies(pubspecPath, debugBuf);

    final parts = pkgDir.split('/');
    final pkgName = parts.length >= 2 ? parts[1] : null;

    final individualTargets = <String>[];
    final shardedTargets = <String>[];

    for (final configEntry in configsMap.entries) {
      final configName = configEntry.key;
      final cases = configEntry.value;
      final config = _configs.firstWhere((c) => c.name == configName);

      // Compute baseline deps for this config
      final baselineDeps = <String>{
        ':tests_metadata_$configName.json',
        '@//:dart_pkg_async_helper',
        '@//:dart_pkg_dart2js_tools',
        '@//:dart_pkg_expect',
        '@//:dart_pkg_ffi',
        '@//:dart_pkg_js',
        '@//:dart_pkg_meta',
        '@//:dart_pkg_path',
        '@//:dart_pkg_source_maps',
        '@//:package_config_json',
        '@//pkg/test_runner/bin:run_single_test.dart',
        '@//sdk:create_sdk',
      };

      if (filegroups.containsKey('fg_package_resources')) {
        baselineDeps.add(':fg_package_resources');
      }

      // Add pubspec deps
      for (final dep in pubspecDeps) {
        if (dep == pkgName) continue;
        baselineDeps.add('@//:dart_pkg_$dep');

        final toolEntryPoints = {
          'analyzer_cli': '@//:pkg/analyzer_cli/bin/analyzer.dart',
          'front_end': '@//:pkg/front_end/tool/compile.dart',
          'analysis_server': '@//:pkg/analysis_server/bin/server.dart',
          'frontend_server':
              '@//:pkg/frontend_server/bin/frontend_server_starter.dart',
          'dartdev': '@//:pkg/dartdev/bin/dartdev.dart',
          'dds': '@//:pkg/dds/bin/dds.dart',
        };
        final entryPoint = toolEntryPoints[dep];
        if (entryPoint != null) {
          baselineDeps.add(entryPoint);
        }

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
        final extraPkgs = toolExtraPackages[dep];
        if (extraPkgs != null) {
          baselineDeps.addAll(extraPkgs);
        }
      }

      if (config.compiler == 'fasta') {
        baselineDeps.addAll({
          '@//:front_end_tool_files',
          '@//:compile_platform_tool',
          '@//runtime/vm:vm_platform',
        });
      }

      if (config.runtime == 'd8' || config.compiler == 'dart2wasm') {
        baselineDeps.addAll({
          '@//third_party/d8:d8_files',
          '@//:pkg/dart2wasm/bin/run_wasm.js',
        });
      }

      if ([
        'chrome',
        'chromeOnAndroid',
        'chromedriver',
      ].contains(config.runtime)) {
        if (Directory(
          '$workspaceDir/third_party/browsers/chrome',
        ).existsSync()) {
          baselineDeps.add('@//third_party/browsers/chrome:chrome_files');
        }
      } else if (['firefox', 'jsshell'].contains(config.runtime)) {
        if (Directory(
          '$workspaceDir/third_party/browsers/firefox',
        ).existsSync()) {
          baselineDeps.add('@//third_party/browsers/firefox:firefox_files');
        }
      } else if (config.runtime == 'firefox_jsshell') {
        if (Directory(
          '$workspaceDir/third_party/firefox_jsshell',
        ).existsSync()) {
          baselineDeps.add(
            '@//third_party/firefox_jsshell:firefox_jsshell_files',
          );
        }
      }

      final enrichedCases = <Map<String, dynamic>>[];
      final seenTargets = <String>{};
      final workspaceFiles = <String>{};
      final otherDeps = <String>{};

      for (final tc in cases) {
        final filePathAbs = tc['file_path'] as String;
        String testFileLabel;
        String relativePath;

        if (filePathAbs.startsWith(workspaceDir)) {
          relativePath = filePathAbs.substring(workspaceDir.length + 1);
          testFileLabel = _resolveWorkspaceLabel(workspaceDir, relativePath);
        } else if (filePathAbs.startsWith('$outputDir/$pkgDir/gen_tests/')) {
          relativePath = filePathAbs.substring('$outputDir/$pkgDir/'.length);
          testFileLabel = ':$relativePath';
        } else if (filePathAbs.startsWith(outputDir)) {
          relativePath = filePathAbs.substring(outputDir.length + 1);
          testFileLabel = '//:$relativePath';
        } else {
          continue;
        }

        // Map test-declared shared objects dynamically
        var hasUnsupportedSo = false;
        final sharedObjects = List<String>.from(
          tc['shared_objects'] as List? ?? [],
        );
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

        final relativePathForChecks = filePathAbs.startsWith(workspaceDir)
            ? filePathAbs.substring(workspaceDir.length + 1)
            : filePathAbs.substring(outputDir.length + 1);
        if (relativePathForChecks.contains('socket_sigpipe_test') ||
            relativePathForChecks.contains('/ffi/')) {
          activeSoDeps.add('@//runtime/bin:libffi_test_functions.so');
          activeSoDeps.add('@//runtime/bin:libffi_test_dynamic_library.so');
        }

        // Enrich and add test case copy
        final tcCopy = Map<String, dynamic>.from(tc);
        tcCopy['relative_file_path'] = relativePath;
        tcCopy['compiler'] = config.compiler;
        enrichedCases.add(tcCopy);

        final origFilePath = tc['original_file_path'] as String? ?? filePathAbs;
        final testDir = File(origFilePath).parent.path;
        final otherResources = List<String>.from(
          tc['other_resources'] as List? ?? [],
        );
        final resolvedResources = <String>{};
        final resourceDeps = <String>{};

        for (final resource in otherResources) {
          final resourcePath = p.posix.normalize('$testDir/$resource');
          if (resourcePath.startsWith(workspaceDir)) {
            final relResPath = resourcePath.substring(workspaceDir.length + 1);
            resolvedResources.add(
              _resolveWorkspaceLabel(workspaceDir, relResPath),
            );
            if (hasFineGrained) {
              final relResInPkg = relResPath.substring(pkgDir.length + 1);
              final resDeps = _computeTransitiveClosure(
                relResInPkg,
                testImportsMap!,
              );
              for (final dep in resDeps) {
                final fgName = _getFilegroupTargetName(dep);
                final label = _resolveWorkspaceLabel(
                  workspaceDir,
                  '$pkgDir/$dep',
                );
                filegroups.putIfAbsent(fgName, () => {}).add(label);
                resourceDeps.add(':$fgName');
              }
            }
          } else if (resourcePath.startsWith(outputDir)) {
            final relResPath = resourcePath.substring(outputDir.length + 1);
            resolvedResources.add('//:$relResPath');
          }
        }

        if (useIndividualTargets) {
          String relPathInPkg;
          if (const {
            'corelib',
            'standalone',
            'ffi',
            'language',
          }.contains(pkgDir)) {
            if (relativePath.startsWith('tests/')) {
              relPathInPkg = relativePath.substring(
                'tests/'.length + pkgDir.length + 1,
              );
            } else {
              final pkgIndex = relativePath.indexOf('$pkgDir/');
              if (pkgIndex != -1) {
                relPathInPkg = relativePath.substring(
                  pkgIndex + pkgDir.length + 1,
                );
              } else {
                relPathInPkg = relativePath.substring(pkgDir.length + 1);
              }
            }
          } else {
            relPathInPkg = relativePath.substring(pkgDir.length + 1);
          }
          final targetName = '${_toTargetName(relPathInPkg)}_$configName';

          if (seenTargets.add(targetName)) {
            final targetDeps = <String>{
              ...baselineDeps,
              testFileLabel,
              ...activeSoDeps,
              ...resolvedResources,
              ...resourceDeps,
            };

            if (hasFineGrained) {
              final localDeps = _computeTransitiveClosure(
                relPathInPkg,
                testImportsMap!,
              );
              for (final dep in localDeps) {
                final fgName = _getFilegroupTargetName(dep);
                final label = _resolveWorkspaceLabel(
                  workspaceDir,
                  '$pkgDir/$dep',
                );
                filegroups.putIfAbsent(fgName, () => {}).add(label);
                targetDeps.add(':$fgName');
              }
            }

            // Package-wide tests
            final packageWideTests = {
              'pkg/compiler': {
                'test/analyses/analyze_test.dart',
                'test/analyses/api_dynamic_test.dart',
              },
              'pkg/analyzer': {'test/verify_docs_test.dart'},
            };
            final pWideTests = packageWideTests[pkgDir];
            if (pWideTests != null && pWideTests.contains(relPathInPkg)) {
              if (pkgName != null) {
                targetDeps.add('@//:dart_pkg_$pkgName');
              }
            }

            final targetDepsStr =
                targetDeps.map((d) => '        "$d"').join(',\n');
            individualTargets.add('''sh_test(
    name = "$targetName",
    srcs = ["//:run_single_test.sh"],
    data = [
$targetDepsStr
    ],
    args = [
        "--config-json=\$(location :tests_metadata_$configName.json)",
        "--run-only=$relPathInPkg",
    ],
)''');
          }
        } else {
          if (filePathAbs.startsWith(workspaceDir)) {
            workspaceFiles.add(testFileLabel);
            packageWorkspaceFiles.add(testFileLabel);
          }
          otherDeps.addAll(activeSoDeps);
          otherDeps.addAll(resolvedResources);
        }
      }

      if (enrichedCases.isNotEmpty) {
        final pkgJson = File(
          '$outputDir/$pkgDir/tests_metadata_$configName.json',
        );
        pkgJson.writeAsStringSync(jsonEncode(enrichedCases));

        if (!useIndividualTargets) {
          if (pkgDir.startsWith('pkg/') && pkgName != null) {
            otherDeps.add('@//:dart_pkg_$pkgName');
          }

          final baselineDepsSet = baselineDeps
              .where((d) => !d.startsWith(':tests_metadata'))
              .toSet();
          baselineDepsSet.addAll(otherDeps);
          final baselineDepsList = baselineDepsSet.toList()..sort();

          final dataListStr =
              baselineDepsList.map((d) => '        "$d",').join('\n');

          var shardCount = enrichedCases.length ~/ 12;
          if (shardCount < 1) {
            shardCount = 1;
          } else if (shardCount > 50) {
            shardCount = 50;
          }
          shardedTargets.add('''sh_test(
    name = "tests_$configName",
    srcs = ["//:run_single_test.sh"],
    data = glob(["gen_tests/$configName/**/*.dart"], allow_empty = True) + [
        ":workspace_files",
        ":tests_metadata_$configName.json",
$dataListStr
    ],
    args = ["--config-json=\$(location :tests_metadata_$configName.json)"],
    shard_count = $shardCount,
)''');
        }
      }
    }

    final pkgBuild = File('$outputDir/$pkgDir/BUILD.bazel');

    final filegroupsStr = StringBuffer();
    if (hasFineGrained) {
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
    }

    if (useIndividualTargets) {
      if (individualTargets.isNotEmpty) {
        final targetsStr = individualTargets.join('\n\n');
        pkgBuild.writeAsStringSync(
          '''load("@rules_shell//shell:sh_test.bzl", "sh_test")

$filegroupsStr

$targetsStr
''',
        );
      }
    } else {
      if (shardedTargets.isNotEmpty) {
        final sortedWorkspaceFiles = packageWorkspaceFiles.toList()..sort();
        final workspaceFilesStr =
            sortedWorkspaceFiles.map((f) => '        "$f",').join('\n');

        final targetsStr = shardedTargets.join('\n\n');
        pkgBuild.writeAsStringSync(
          '''load("@rules_shell//shell:sh_test.bzl", "sh_test")

filegroup(
    name = "workspace_files",
    srcs = [
$workspaceFilesStr
    ],
)

$targetsStr
''',
        );
      }
    }
  }

  // Write root BUILD.bazel with explicit exports to avoid expensive globbing
  final rootBuild = File('$outputDir/BUILD.bazel');
  rootBuild.writeAsStringSync('''exports_files([
        "run_single_test.sh",
])
''');

  debugBuf.writeln('=== Generation Completed Successfully ===');
  debugLog.writeAsStringSync(debugBuf.toString());
  return;
}

typedef _TestConfig = ({
  String name,
  String mode,
  String compiler,
  String runtime,
  List<String> suites,
  List<String> extraFlags,
});

const _configs = <_TestConfig>[
  (
    name: 'vm_release',
    mode: 'release',
    compiler: 'dartk',
    runtime: 'vm',
    suites: ['language', 'corelib', 'standalone', 'ffi', 'pkg'],
    extraFlags: [],
  ),
  (
    name: 'vm_debug',
    mode: 'debug',
    compiler: 'dartk',
    runtime: 'vm',
    suites: ['language', 'corelib', 'standalone'],
    extraFlags: [],
  ),
  (
    name: 'vm_product',
    mode: 'product',
    compiler: 'dartk',
    runtime: 'vm',
    suites: ['language', 'corelib', 'standalone', 'ffi'],
    extraFlags: [],
  ),
  (
    name: 'wasm_release',
    mode: 'release',
    compiler: 'dart2wasm',
    runtime: 'd8',
    suites: ['language', 'corelib', 'web/wasm'],
    extraFlags: [],
  ),
  (
    name: 'wasm_asserts',
    mode: 'release',
    compiler: 'dart2wasm',
    runtime: 'd8',
    suites: ['language', 'corelib', 'web/wasm'],
    extraFlags: ['--enable-asserts', '--dart2wasm-options=-O0'],
  ),
  (
    name: 'wasm_optimized',
    mode: 'release',
    compiler: 'dart2wasm',
    runtime: 'd8',
    suites: ['language', 'corelib', 'web/wasm'],
    extraFlags: ['--dart2wasm-options=-O1'],
  ),
  (
    name: 'cfe_release',
    mode: 'release',
    compiler: 'fasta',
    runtime: 'none',
    suites: ['language', 'corelib', 'standalone', 'ffi'],
    extraFlags: [],
  ),
];

typedef _ConfigResult = ({
  _TestConfig config,
  List<Map<String, dynamic>> testCases,
});

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
  return relPath
      .replaceAll('/', '_')
      .replaceAll('\\', '_')
      .replaceAll('.', '_');
}

String _getFilegroupTargetName(String depPath) {
  final norm = p.posix.normalize(depPath);
  final dir = p.posix.dirname(norm);
  if (dir == '.' || dir.isEmpty) {
    return 'fg_root_files';
  }
  final target = dir.replaceAll('/', '_');
  return 'fg_$target';
}

List<String> _findPackageResources(String workspaceDir, String pkgDir) {
  final resources = <String>[];
  final dir = Directory('$workspaceDir/$pkgDir');
  if (!dir.existsSync()) return resources;

  final allowedExtensions = {
    '.json',
    '.yaml',
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

      if (parts.any((p) => p.startsWith('.'))) continue;
      if (parts.contains('doc')) continue;

      final filename = parts.last;
      if (filename == 'BUILD' ||
          filename == 'BUILD.bazel' ||
          filename == 'OWNERS') {
        continue;
      }

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
  String startFile,
  Map<String, dynamic> directDepsMap,
) {
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

Set<String> _parsePubspecDependencies(
  String pubspecPath,
  StringBuffer debugBuf,
) {
  final deps = <String>{};
  final file = File(pubspecPath);
  if (!file.existsSync()) {
    return deps;
  }

  var inDepsSection = false;
  for (var line in file.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.startsWith('#')) continue;

    if (trimmed == 'dependencies:' || trimmed == 'dev_dependencies:') {
      inDepsSection = true;
      continue;
    }

    if (inDepsSection) {
      if (line.isEmpty) continue;

      if (!line.startsWith(' ') && !line.startsWith('\t')) {
        inDepsSection = false;
        if (line.startsWith('dependencies:') ||
            line.startsWith('dev_dependencies:')) {
          inDepsSection = true;
        }
        continue;
      }

      final leadingSpaces = line.length - line.trimLeft().length;
      if (leadingSpaces > 3) {
        continue;
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
