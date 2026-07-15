// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
//
// Tests that flush() on HttpResponse and HttpClientRequest delivers
// buffered data to the peer instead of holding it until the message is
// closed, and that an un-awaited flush() followed by more writes does not
// raise an unhandled error (regression test).
//
// VMOptions=
// VMOptions=--short_socket_read
// VMOptions=--short_socket_write
// VMOptions=--short_socket_read --short_socket_write

import "dart:async";
import "dart:convert";
import "dart:io";

import "package:expect/async_helper.dart";
import "package:expect/expect.dart";

Future<void> testResponseFlushDeliversBeforeClose() async {
  // The handler writes part1 and flushes, then parks; the client must
  // receive part1 while the response is still open. Releasing the handler
  // writes part2 (exercising the buffer-reallocation path after a drain)
  // and closes.
  asyncStart();
  final part1Seen = Completer<void>();
  final release = Completer<void>();
  final server = await HttpServer.bind("127.0.0.1", 0);
  server.listen((request) async {
    final response = request.response;
    response.write("part1");
    await response.flush();
    await release.future;
    response.write("part2");
    await response.close();
  });

  final socket = await Socket.connect("127.0.0.1", server.port);
  final received = StringBuffer();
  final done = Completer<void>();
  socket.listen((data) {
    received.write(String.fromCharCodes(data));
    if (!part1Seen.isCompleted && received.toString().contains("part1")) {
      part1Seen.complete();
    }
  }, onDone: () => done.complete());
  socket.write(
    "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
  );

  // Arrives due to flush(), while the server still holds the response open.
  await part1Seen.future;
  Expect.isFalse(received.toString().contains("part2"));
  release.complete();

  await done.future;
  Expect.isTrue(received.toString().contains("part2"));
  socket.destroy();
  await server.close();
  asyncEnd();
}

Future<void> testUnawaitedFlushThenWrite() async {
  // Regression test: an un-awaited flush() immediately followed by a
  // synchronous write() must not raise an unhandled StateError from the
  // deferred buffer drain; the body must still arrive intact.
  asyncStart();
  final server = await HttpServer.bind("127.0.0.1", 0);
  server.listen((request) async {
    final response = request.response;
    response.write("a");
    await response.flush();
    response.flush(); // Un-awaited: fast path, drain deferred.
    response.write("b"); // Binds the socket sink before the drain runs.
    await response.close();
  });

  final client = HttpClient();
  final response = await (await client.get(
    "127.0.0.1",
    server.port,
    "/",
  )).close();
  final body = await response.transform(utf8.decoder).join();
  Expect.equals("ab", body);
  client.close();
  await server.close();
  asyncEnd();
}

Future<void> testFlushBeforeAnyWrite() async {
  // flush() with nothing written yet completes and does not corrupt the
  // response.
  asyncStart();
  final server = await HttpServer.bind("127.0.0.1", 0);
  server.listen((request) async {
    final response = request.response;
    await response.flush();
    response.write("body");
    await response.close();
  });

  final client = HttpClient();
  final response = await (await client.get(
    "127.0.0.1",
    server.port,
    "/",
  )).close();
  final body = await response.transform(utf8.decoder).join();
  Expect.equals("body", body);
  client.close();
  await server.close();
  asyncEnd();
}

Future<void> testClientRequestFlushDeliversBeforeClose() async {
  // The client writes a body chunk and flushes; a raw server must see the
  // chunk while the request is still open.
  asyncStart();
  final part1Seen = Completer<void>();
  final server = await ServerSocket.bind("127.0.0.1", 0);
  server.listen((socket) {
    final received = StringBuffer();
    socket.listen((data) {
      received.write(String.fromCharCodes(data));
      if (!part1Seen.isCompleted && received.toString().contains("part1")) {
        part1Seen.complete();
      }
      if (received.toString().endsWith("part2")) {
        socket.write("HTTP/1.1 200 OK\r\ncontent-length: 2\r\n\r\nok");
        socket.close();
      }
    });
  });

  final client = HttpClient();
  final request = await client.post("127.0.0.1", server.port, "/");
  request.contentLength = 10;
  request.write("part1");
  await request.flush();
  // Arrives due to flush(), while the request is still open.
  await part1Seen.future;
  request.write("part2");
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  Expect.equals("ok", body);
  client.close();
  await server.close();
  asyncEnd();
}

void main() async {
  asyncStart();
  await testResponseFlushDeliversBeforeClose();
  await testUnawaitedFlushThenWrite();
  await testFlushBeforeAnyWrite();
  await testClientRequestFlushDeliversBeforeClose();
  asyncEnd();
}
