// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:args/args.dart';

void main(List<String> args) {
  final parser = ArgParser()..addFlag('verbose', negatable: false);
  final results = parser.parse(args);
  print('Hello from bazel run! verbose=${results['verbose']}');
}
