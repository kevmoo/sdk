// Copyright (c) 2026, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:dartdev/src/unified_analytics.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  group('collectPubspecTelemetry', () {
    late Directory tempDir;
    late Directory originalCurrentDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('dartdev_analytics_test_');
      originalCurrentDir = Directory.current;
    });

    tearDown(() {
      Directory.current = originalCurrentDir;
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {
        // Ignore cleanup errors
      }
    });

    test('returns null when no pubspec.yaml exists in parent hierarchy', () {
      Directory.current = tempDir;
      expect(collectPubspecTelemetry(), isNull);
    });

    test('returns null when pubspec.yaml is more than 5 levels deep', () {
      File(path.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: test_project
dependencies:
  path: ^1.8.0
''');

      var deepDir = tempDir;
      for (var i = 0; i < 6; i++) {
        deepDir = Directory(path.join(deepDir.path, 'level_$i'))..createSync();
      }

      Directory.current = deepDir;
      expect(collectPubspecTelemetry(), isNull);
    });

    test('finds pubspec.yaml when up to 5 levels deep', () {
      File(path.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: test_project
environment:
  sdk: ^3.0.0
dependencies:
  path: ^1.8.0
''');

      var deepDir = tempDir;
      for (var i = 0; i < 5; i++) {
        deepDir = Directory(path.join(deepDir.path, 'level_$i'))..createSync();
      }

      Directory.current = deepDir;
      final telemetry = collectPubspecTelemetry();
      expect(telemetry, isNotNull);
      expect(telemetry!.publicDependencies, {'path'});
      expect(telemetry.hasFlutterSdk, isFalse);
      expect(telemetry.environmentSdk, '^3.0.0');
    });

    test('returns null when pubspec.yaml is malformed', () {
      Directory.current = tempDir;
      File(path.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: test_project
dependencies:
  invalid: [yaml: structure
''');

      expect(collectPubspecTelemetry(), isNull);
    });

    test('handles missing dependencies block', () {
      Directory.current = tempDir;
      File(path.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: test_project
''');

      final telemetry = collectPubspecTelemetry();
      expect(telemetry, isNotNull);
      expect(telemetry!.publicDependencies, isEmpty);
      expect(telemetry.hasFlutterSdk, isFalse);
      expect(telemetry.environmentSdk, isNull);
    });

    test('categorizes public and private dependencies correctly', () {
      Directory.current = tempDir;
      File(path.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: test_project
dependencies:
  # Public dependencies
  path: ^1.8.0
  meta:
  args: { hosted: 'https://pub.dev' }
  charcode: { hosted: { name: 'charcode', url: 'https://pub.dartlang.org' } }

  # Private / non-public dependencies
  private_git:
    git:
      url: git://github.com/foo/bar.git
  private_path:
    path: ../some_path
  private_sdk:
    sdk: flutter
  private_custom_hosted:
    hosted: 'https://private-pub.example.com'
  private_custom_hosted_map:
    hosted:
      name: private_custom_hosted_map
      url: 'https://private-pub.example.com'
''');

      final telemetry = collectPubspecTelemetry();
      expect(telemetry, isNotNull);
      expect(telemetry!.publicDependencies, {
        'path',
        'meta',
        'args',
        'charcode',
      });
      expect(telemetry.hasFlutterSdk, isFalse);
    });

    test(
      'detects Flutter SDK dependency and excludes it from public dependencies',
      () {
        Directory.current = tempDir;
        File(path.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: test_project
dependencies:
  path: ^1.8.0
  flutter:
    sdk: flutter
''');

        final telemetry = collectPubspecTelemetry();
        expect(telemetry, isNotNull);
        expect(telemetry!.publicDependencies, {'path'});
        expect(telemetry.hasFlutterSdk, isTrue);
      },
    );

    test(
      'fails silently and returns null when pubspec.yaml is a directory',
      () {
        Directory.current = tempDir;
        Directory(path.join(tempDir.path, 'pubspec.yaml')).createSync();

        expect(collectPubspecTelemetry(), isNull);
      },
    );

    test('extracts environment sdk constraint correctly', () {
      Directory.current = tempDir;
      File(path.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: test_project
environment:
  sdk: '>=2.19.0 <4.0.0'
''');

      final telemetry = collectPubspecTelemetry();
      expect(telemetry, isNotNull);
      expect(telemetry!.environmentSdk, '>=2.19.0 <4.0.0');
    });

    test(
      'truncates environment sdk constraint if longer than 100 characters',
      () {
        Directory.current = tempDir;
        final longConstraint = '>=3.0.0 ${'a' * 100}';
        File(path.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: test_project
environment:
  sdk: "$longConstraint"
''');

        final telemetry = collectPubspecTelemetry();
        expect(telemetry, isNotNull);
        expect(telemetry!.environmentSdk!.length, 100);
        expect(telemetry.environmentSdk, longConstraint.substring(0, 100));
      },
    );
  });
}
