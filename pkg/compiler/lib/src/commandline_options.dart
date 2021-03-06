// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library dart2js.cmdline.options;

/// Commandline flags used in `dart2js.dart` and/or `apiimpl.dart`.
class Flags {
  static const String allowMockCompilation = '--allow-mock-compilation';
  static const String allowNativeExtensions = '--allow-native-extensions';
  static const String analyzeAll = '--analyze-all';
  static const String analyzeMain = '--analyze-main';
  static const String analyzeOnly = '--analyze-only';
  static const String analyzeSignaturesOnly = '--analyze-signatures-only';
  static const String disableDiagnosticColors = '--disable-diagnostic-colors';
  static const String disableNativeLiveTypeAnalysis =
      '--disable-native-live-type-analysis';
  static const String disableTypeInference = '--disable-type-inference';
  static const String dumpInfo = '--dump-info';
  static const String enableAssertMessage = '--assert-message';
  static const String enableCheckedMode = '--enable-checked-mode';
  static const String enableConcreteTypeInference =
      '--enable-concrete-type-inference';
  static const String enableDiagnosticColors = '--enable-diagnostic-colors';
  static const String enableExperimentalMirrors =
      '--enable-experimental-mirrors';
  static const String fastStartup = '--fast-startup';
  static const String fatalWarnings = '--fatal-warnings';
  static const String generateCodeWithCompileTimeErrors =
      '--generate-code-with-compile-time-errors';
  static const String incrementalSupport = '--incremental-support';
  static const String minify = '--minify';
  static const String noFrequencyBasedMinification =
      '--no-frequency-based-minification';
  static const String noSourceMaps = '--no-source-maps';
  static const String preserveComments = '--preserve-comments';
  static const String preserveUris = '--preserve-uris';
  static const String showPackageWarnings = '--show-package-warnings';
  static const String suppressHints = '--suppress-hints';
  static const String suppressWarnings = '--suppress-warnings';
  static const String terse = '--terse';
  static const String testMode = '--test-mode';
  static const String trustPrimitives = '--trust-primitives';
  static const String trustTypeAnnotations = '--trust-type-annotations';
  static const String useContentSecurityPolicy = '--csp';
  static const String useCpsIr = '--use-cps-ir';
  static const String verbose = '--verbose';
  static const String version = '--version';
}
