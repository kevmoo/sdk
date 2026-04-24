// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

int test(List<int> list) {
  return switch (list) {
    [var a] => 1,
    [var a, var b] => 2,
    [var a, var b, var c] => 3,
    [var a, var b, var c, var d] => 4,
    [var a, var b, var c, var d, var e] => 5,
    _ => 0,
  };
}

void main() {
  print(test([1]));
  print(test([1, 2]));
  print(test([1, 2, 3]));
  print(test([1, 2, 3, 4]));
  print(test([1, 2, 3, 4, 5]));
  print(test([1, 2, 3, 4, 5, 6]));
}
