// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "package:expect/async_helper.dart";
import "package:expect/expect.dart";
import "dart:async";
import "dart:io";
import "dart:typed_data";

class Socket2BatchWriteTest {
  static Future<void> run() async {
    final server = await ServerSocket2.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;

    final serverFinished = Completer<void>();
    final serverReceivedData = <int>[];

    // Server loop
    unawaited(() async {
      final socket = await server.accept();
      
      final buffer = Uint8List(1024);
      while (true) {
        final result = await socket.read(buffer);
        if (result.bytes == 0) break;
        serverReceivedData.addAll(Uint8List.sublistView(result.buffer, 0, result.bytes));
      }
      
      await socket.close();
      serverFinished.complete();
    }());

    // Client
    final socket = await Socket2.connect(InternetAddress.loopbackIPv4, port);
    
    // Create multiple buffers
    final b1 = Uint8List.fromList([1, 2, 3, 4]);
    final b2 = Uint8List.fromList([5, 6, 7]);
    final b3 = Uint8List.fromList([8, 9, 10, 11, 12]);
    
    final buffers = [b1, b2, b3];
    int totalBytesExpected = b1.length + b2.length + b3.length;
    
    var currentBuffers = buffers;
    while (currentBuffers.isNotEmpty) {
      final result = await socket.writeList(currentBuffers);
      if (result.bytes == 0) break;
      
      var remaining = result.bytes;
      var newBuffers = <Uint8List>[];
      for (var b in result.buffers) {
        if (remaining == 0) {
          newBuffers.add(b);
        } else if (remaining >= b.lengthInBytes) {
          remaining -= b.lengthInBytes;
        } else {
          newBuffers.add(Uint8List.sublistView(b, remaining));
          remaining = 0;
        }
      }
      currentBuffers = newBuffers;
    }
    
    await socket.close();
    
    await serverFinished.future;
    
    Expect.equals(totalBytesExpected, serverReceivedData.length);
    for (int i = 0; i < totalBytesExpected; i++) {
      Expect.equals(i + 1, serverReceivedData[i]);
    }
    
    await server.close();
  }
}

void main() async {
  asyncStart();
  runZonedGuarded(() async {
    await Socket2BatchWriteTest.run();
    asyncEnd();
  }, (e, st) {
    print("Caught unhandled: $e\n$st");
  });
}
