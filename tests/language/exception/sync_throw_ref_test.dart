// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:expect/expect.dart';

@pragma('vm:never-inline')
@pragma('dart2js:noInline')
@pragma('wasm:never-inline')
void _customFunctionNameToCheckMinification() {
  // Add a unique instruction structure to prevent body-merging or folding
  if (identical(1, 2)) return;
  throw 'sentinel_minification_check';
}

bool _hasSymbolicStackTrace() {
  try {
    _customFunctionNameToCheckMinification();
  } catch (e, s) {
    return '$s'.contains('_customFunctionNameToCheckMinification');
  }
  return false;
}

@pragma('vm:never-inline')
@pragma('dart2js:noInline')
@pragma('wasm:never-inline')
void exception1(String e) {
  if (e == "FORCE_DIFFERENT_BODY_1") return;
  throw e;
}

@pragma('vm:never-inline')
@pragma('dart2js:noInline')
@pragma('wasm:never-inline')
void exception2(String e) {
  if (e == "FORCE_DIFFERENT_BODY_2") return;
  throw e;
}

@pragma('vm:never-inline')
@pragma('dart2js:noInline')
@pragma('wasm:never-inline')
void doSyncThrow1() {
  try {
    exception1('outer');
  } on Object {
    try {
      exception2('inner');
    } on Object {
      // ignore
    }
    rethrow;
  }
}

@pragma('vm:never-inline')
@pragma('dart2js:noInline')
@pragma('wasm:never-inline')
void doSyncThrow2() {
  try {
    exception2('outer');
  } on Object {
    try {
      exception1('inner');
    } on Object {
      try {
        exception1('more inner');
      } on Object {
        // ignore
      }
    }
    rethrow;
  }
}

@pragma('vm:never-inline')
@pragma('dart2js:noInline')
@pragma('wasm:never-inline')
void doSyncThrow3() {
  try {
    exception1('outer');
  } on Object {
    try {
      // don't throw
    } on Object {
      try {
        // also don't throw
      } on Object {
        // ignore
      }
    }
    rethrow;
  }
}

@pragma('vm:never-inline')
@pragma('dart2js:noInline')
@pragma('wasm:never-inline')
void doSyncThrow4() {
  try {
    exception1('outer');
  } on Object {
    try {
      exception2('inner');
    } on bool {}
    rethrow;
  }
}

@pragma('vm:never-inline')
@pragma('dart2js:noInline')
@pragma('wasm:never-inline')
void doSyncThrowFinally() {
  try {
    exception1('outer');
  } finally {
    // empty finalizer
  }
}

@pragma('vm:never-inline')
@pragma('dart2js:noInline')
@pragma('wasm:never-inline')
void doSyncThrowNestedFinally() {
  try {
    exception1('outer');
  } finally {
    try {
      exception2('inner');
    } on Object {
      // ignore
    }
  }
}

void main() {
  final bool hasSymbolic = _hasSymbolicStackTrace();

  try {
    doSyncThrow1();
    Expect.fail('should throw');
  } catch (e, s) {
    Expect.equals(e, 'outer');
    if (hasSymbolic) {
      // Verify stack trace integrity of the rethrow when symbols are preserved
      Expect.isTrue('$s'.contains('exception1'));
      Expect.isTrue('$s'.contains('doSyncThrow1'));
    }
  }

  try {
    doSyncThrow2();
    Expect.fail('should throw');
  } catch (e, s) {
    Expect.equals(e, 'outer');
    if (hasSymbolic) {
      Expect.isTrue('$s'.contains('exception2'));
      Expect.isTrue('$s'.contains('doSyncThrow2'));
    }
  }

  try {
    doSyncThrow3();
    Expect.fail('should throw');
  } catch (e, s) {
    Expect.equals(e, 'outer');
    if (hasSymbolic) {
      Expect.isTrue('$s'.contains('exception1'));
      Expect.isTrue('$s'.contains('doSyncThrow3'));
    }
  }

  try {
    doSyncThrow4();
    Expect.fail('should throw');
  } catch (e, s) {
    Expect.equals(e, 'inner');
    if (hasSymbolic) {
      Expect.isTrue('$s'.contains('exception2'));
      Expect.isTrue('$s'.contains('doSyncThrow4'));
    }
  }

  try {
    doSyncThrowFinally();
    Expect.fail('should throw');
  } catch (e, s) {
    Expect.equals(e, 'outer');
    if (hasSymbolic) {
      Expect.isTrue('$s'.contains('exception1'));
      Expect.isTrue('$s'.contains('doSyncThrowFinally'));
    }
  }

  try {
    doSyncThrowNestedFinally();
    Expect.fail('should throw');
  } catch (e, s) {
    Expect.equals(e, 'outer');
    if (hasSymbolic) {
      Expect.isTrue('$s'.contains('exception1'));
      Expect.isTrue('$s'.contains('doSyncThrowNestedFinally'));
    }
  }
}
