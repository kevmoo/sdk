// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Test creating a large number of socket2 connections and performing I/O.

import "package:expect/async_helper.dart";
import "package:expect/expect.dart";
import "dart:async";
import "dart:io";
import "dart:typed_data";

const connectionsCount = 100;
const messageSize = 1024;

class Socket2ConcurrencyTest {
  static Future<void> run() async {
    final server = await ServerSocket2.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;

    final serverFinished = Completer<void>();
    int connectionsHandled = 0;

    // Server loop
    unawaited(() async {
      for (int i = 0; i < connectionsCount; i++) {
        final socket = await server.accept();
        unawaited(() async {
          // Read a message
          final buffer = Uint8List(messageSize);
          int bytesRead = 0;
          while (bytesRead < messageSize) {
            final view = Uint8List.sublistView(buffer, bytesRead);
            final result = await socket.read(view);
            if (result.bytes == 0) break;
            bytesRead += result.bytes;
          }
          Expect.equals(messageSize, bytesRead);

          // Echo it back
          int bytesWritten = 0;
          while (bytesWritten < messageSize) {
            final view = Uint8List.sublistView(buffer, bytesWritten);
            final result = await socket.write(view);
            if (result.bytes == 0) break;
            bytesWritten += result.bytes;
          }
          Expect.equals(messageSize, bytesWritten);
          
          await socket.close();
          connectionsHandled++;
          if (connectionsHandled == connectionsCount) {
            serverFinished.complete();
          }
        }());
      }
    }());

    // Client loops
    final clientFutures = <Future<void>>[];
    for (int i = 0; i < connectionsCount; i++) {
      clientFutures.add(() async {
        final socket = await Socket2.connect(InternetAddress.loopbackIPv4, port);
        final buffer = Uint8List(messageSize)..fillRange(0, messageSize, i % 256);
        
        // Write message
        int bytesWritten = 0;
        while (bytesWritten < messageSize) {
          final view = Uint8List.sublistView(buffer, bytesWritten);
          final result = await socket.write(view);
          if (result.bytes == 0) break;
          bytesWritten += result.bytes;
        }
        Expect.equals(messageSize, bytesWritten);

        // Read response
        final readBuffer = Uint8List(messageSize);
        int bytesRead = 0;
        while (bytesRead < messageSize) {
          final view = Uint8List.sublistView(readBuffer, bytesRead);
          final result = await socket.read(view);
          if (result.bytes == 0) break;
          bytesRead += result.bytes;
        }
        Expect.equals(messageSize, bytesRead);
        Expect.listEquals(buffer, readBuffer);

        await socket.close();
      }());
    }

    await Future.wait(clientFutures);
    await serverFinished.future;
    await server.close();
  }
}

void main() async {
  asyncStart();
  await Socket2ConcurrencyTest.run();
  asyncEnd();
}
