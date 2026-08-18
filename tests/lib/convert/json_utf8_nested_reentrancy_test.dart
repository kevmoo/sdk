// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:async";
import "dart:convert";
import "dart:isolate";
import "dart:typed_data";

import "package:expect/async_helper.dart";
import "package:expect/expect.dart";

void main() {
  asyncStart();
  testDeepToJsonRecursion();
  testBinaryTreeEncoding();
  testNonCopyingSinkSafety();
  testConcurrentIsolates().then((_) {
    asyncEnd();
  });
}

class AutoRecursionNode {
  final int depth;
  final AutoRecursionNode? child;
  AutoRecursionNode(this.depth, [this.child]);

  Map<String, Object?> toJson() {
    return {
      'level': depth,
      if (child != null) 'child': child,
      if (child == null) 'leaf': true,
    };
  }
}

void testDeepToJsonRecursion() {
  // Build a 50-level deep toJson() recursion chain (within 64-level nesting limit)
  AutoRecursionNode? current;
  for (var i = 50; i >= 0; i--) {
    current = AutoRecursionNode(i, current);
  }
  final root = current!;

  // 1. Test jsonUtf8Encode and jsonUtf8Decode
  final encoded = jsonUtf8Encode(root);
  Expect.type<Uint8List>(encoded);

  final decoded = jsonUtf8Decode(encoded) as Map<String, dynamic>;
  var node = decoded;
  for (var i = 0; i < 50; i++) {
    Expect.equals(i, node['level']);
    Expect.isNotNull(node['child']);
    node = node['child'] as Map<String, dynamic>;
  }
  Expect.equals(50, node['level']);
  Expect.equals(true, node['leaf']);

  // 2. Test codec parity with standard jsonEncode / jsonDecode
  final stdJson = jsonEncode(root);
  final stdDecoded = jsonDecode(stdJson);
  Expect.deepEquals(stdDecoded, decoded);

  // 3. Test jsonUtf8.encode and jsonUtf8.decode
  final codecEncoded = jsonUtf8.encode(root);
  final codecDecoded = jsonUtf8.decode(codecEncoded);
  Expect.deepEquals(decoded, codecDecoded);
}

class TreeNode {
  final int id;
  final TreeNode? left;
  final TreeNode? right;
  TreeNode(this.id, {this.left, this.right});

  static TreeNode build(int depth, int id) {
    if (depth <= 0) return TreeNode(id);
    return TreeNode(
      id,
      left: build(depth - 1, id * 2),
      right: build(depth - 1, id * 2 + 1),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    if (left != null) 'left': left,
    if (right != null) 'right': right,
  };
}

void _verifyTree(TreeNode original, Map<String, dynamic> decoded) {
  Expect.equals(original.id, decoded['id']);
  if (original.left != null) {
    Expect.isNotNull(decoded['left']);
    _verifyTree(original.left!, decoded['left'] as Map<String, dynamic>);
  } else {
    Expect.isNull(decoded['left']);
  }
  if (original.right != null) {
    Expect.isNotNull(decoded['right']);
    _verifyTree(original.right!, decoded['right'] as Map<String, dynamic>);
  } else {
    Expect.isNull(decoded['right']);
  }
}

void testBinaryTreeEncoding() {
  // Build a binary tree of depth 10 (2047 total nodes)
  final tree = TreeNode.build(10, 1);

  final encoded = jsonUtf8Encode(tree);
  Expect.type<Uint8List>(encoded);

  final decoded = jsonUtf8Decode(encoded) as Map<String, dynamic>;
  _verifyTree(tree, decoded);

  // Cross-verify with jsonEncode / jsonDecode
  final stdDecoded = jsonDecode(jsonEncode(tree)) as Map<String, dynamic>;
  Expect.deepEquals(stdDecoded, decoded);
}

class ReentrantPayload {
  final int id;
  final Object? nestedData;
  ReentrantPayload(this.id, this.nestedData);
}

void testNonCopyingSinkSafety() {
  // 1. Reentrant serialization inside toEncodable callback
  final toEncodable = (Object? obj) {
    if (obj is ReentrantPayload) {
      // Reentrantly encode and decode nested data during active encoding
      final nestedBytes = jsonUtf8Encode(obj.nestedData);
      final decodedNested = jsonUtf8Decode(nestedBytes);
      return {'id': obj.id, 'nested': decodedNested};
    }
    throw 'Cannot encode $obj';
  };

  final encoder = JsonUtf8Encoder(null, toEncodable);
  final root = {
    'item1': ReentrantPayload(1, {
      'sub': 'alpha',
      'values': [1, 2, 3],
    }),
    'item2': ReentrantPayload(2, {
      'sub': 'beta',
      'values': [4.5, 6.7],
    }),
    'item3': ReentrantPayload(3, [
      'x',
      'y',
      'z',
      {'nested': true},
    ]),
  };

  final encoded = encoder.convert(root);
  final decoded = jsonUtf8Decode(encoded) as Map<String, dynamic>;
  Expect.equals(1, (decoded['item1'] as Map)['id']);
  Expect.equals('alpha', ((decoded['item1'] as Map)['nested'] as Map)['sub']);
  Expect.equals(2, (decoded['item2'] as Map)['id']);
  Expect.equals(3, (decoded['item3'] as Map)['id']);

  // 2. Chunked conversion with non-copying sink
  final chunks = <List<int>>[];
  final sink = JsonUtf8Encoder().startChunkedConversion(
    ChunkedConversionSink.withCallback((List<List<int>> values) {
      chunks.addAll(values);
    }),
  );
  sink.add({
    'a': 1,
    'b': 2,
    'c': [3, 4, 5],
  });
  Expect.throwsStateError(() => sink.add({'second': 'doc'}));
  sink.close();
  Expect.isTrue(chunks.isNotEmpty);
  final combined = chunks.expand((c) => c).toList();
  Expect.equals('{"a":1,"b":2,"c":[3,4,5]}', utf8.decode(combined));
}

void _isolateWorker(SendPort replyPort) {
  try {
    for (var iter = 0; iter < 50; iter++) {
      final data = {
        'id': iter,
        'name': 'Isolate Worker $iter',
        'metrics': [1.23, 4.56, 7.89, -100.5],
        'flags': {'active': true, 'debug': false, 'nullVal': null},
        'unicode': '🚀 Multi-isolate test € 😀 \uD83D\uDE00',
        'nested': List.generate(20, (i) => {'index': i, 'val': i * 1.5}),
      };

      final bytes = jsonUtf8Encode(data);
      final decoded = jsonUtf8Decode(bytes) as Map<String, dynamic>;
      Expect.equals(iter, decoded['id']);
      Expect.equals('Isolate Worker $iter', decoded['name']);
      Expect.equals('🚀 Multi-isolate test € 😀 😀', decoded['unicode']);
      Expect.equals(20, (decoded['nested'] as List).length);

      // Verify token reader and writer concurrently
      final reader = JsonTokenReader.fromBytes(
        Uint8List.fromList(utf8.encode('  3.14159265  ')),
      );
      final dVal = reader.readDouble();
      Expect.equals(3.14159265, dVal);

      final w = JsonTokenWriter.toBuffer();
      w.writeString('concurrent_str');
      final outBytes = w.toBytes();
      Expect.equals(16, outBytes.length);
      Expect.equals('"concurrent_str"', utf8.decode(outBytes));
    }
    replyPort.send('OK');
  } catch (e, st) {
    replyPort.send('Error: $e\n$st');
  }
}

Future<void> testConcurrentIsolates() async {
  if (!bool.fromEnvironment("dart.library.isolate")) {
    return;
  }
  try {
    final testPort = ReceivePort();
    testPort.listen((_) {}).cancel();
    testPort.close();
  } on UnsupportedError {
    // Isolates are not supported on this platform (e.g. dart2wasm / JS).
    return;
  }

  const isolateCount = 16;
  final futures = <Future<void>>[];

  for (var i = 0; i < isolateCount; i++) {
    final receivePort = ReceivePort();
    final completer = Completer<void>();

    receivePort.listen((message) {
      if (message == 'OK') {
        completer.complete();
      } else {
        completer.completeError(Exception('Isolate $i failed: $message'));
      }
      receivePort.close();
    });

    try {
      await Isolate.spawn(_isolateWorker, receivePort.sendPort);
      futures.add(completer.future);
    } on UnsupportedError {
      receivePort.close();
      return;
    }
  }

  await Future.wait(futures);
}
