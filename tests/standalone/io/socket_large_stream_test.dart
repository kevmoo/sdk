// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "package:expect/async_helper.dart";
import "package:expect/expect.dart";
import "dart:async";
import "dart:io";
import "dart:typed_data";

// Regression test for legacy Socket large streaming performance and stability.

void main() {
  asyncStart();
  testLargeStream();
}

Future<void> testLargeStream() async {
  final int totalBytes = 100 * 1024 * 1024; // 100MB
  final int chunkSize = 64 * 1024; // 64KB chunks

  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = server.port;

  final serverFuture = server.first.then((socket) async {
    int received = 0;
    final completer = Completer<int>();
    socket.listen(
      (data) {
        received += data.length;
        if (received == totalBytes) {
          completer.complete(received);
        }
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete(received);
      },
      onError: (e) => completer.completeError(e),
    );
    final result = await completer.future;
    await socket.close();
    return result;
  });

  final client = await Socket.connect(InternetAddress.loopbackIPv4, port);
  final data = Uint8List(chunkSize);
  
  int sent = 0;
  while (sent < totalBytes) {
    client.add(data);
    sent += data.length;
    if (sent % (1024 * 1024) == 0) {
       // Yield periodically to allow server to drain
       await Future.delayed(Duration.zero);
    }
  }
  await client.flush();
  await client.close();

  final received = await serverFuture;
  Expect.equals(totalBytes, received);
  await server.close();
  asyncEnd();
}
