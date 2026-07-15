// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
//
// White-box tests for _HttpOutgoing's output buffer: the full-capacity
// header handoff that lets headers and body coalesce into a single socket
// write, and _addChunk's ordering and post-drain reallocation.

import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:typed_data";
// ignore: IMPORT_INTERNAL_LIBRARY
import "dart:_http";

import "package:expect/async_helper.dart";
import "package:expect/expect.dart";

const int bufferSize = 8 * 1024;

void testTakeBuffer() {
  // takeBuffer() hands over the full backing store, spare capacity included,
  // unlike takeBytes() which returns a right-sized view.
  var builder = TestingClass$_CopyingBytesBuilder(bufferSize);
  builder.add("hello".codeUnits);
  Expect.equals(5, builder.length);
  var full = builder.takeBuffer();
  Expect.equals(bufferSize, full.length);
  Expect.listEquals("hello".codeUnits, full.sublist(0, 5));
  Expect.equals(0, builder.length);

  var other = TestingClass$_CopyingBytesBuilder(bufferSize);
  other.add("hello".codeUnits);
  Expect.equals(5, other.takeBytes().length);

  // A builder grown past its initial capacity still hands over the whole
  // (power-of-two) backing store.
  var grown = TestingClass$_CopyingBytesBuilder(bufferSize);
  grown.add(Uint8List(bufferSize + 1));
  var grownBuffer = grown.takeBuffer();
  Expect.isTrue(grownBuffer.length > bufferSize);
}

Future<TestingClass$_HttpOutgoing> waitForBufferedHeaders(
  HttpResponse response,
) async {
  var outgoing = (response as TestingClass$_HttpResponse).test$_outgoing;
  while (outgoing.test$_length == 0) {
    await Future.delayed(const Duration(milliseconds: 1));
  }
  return outgoing;
}

Future<void> testHeadersAndBodyShareBuffer() async {
  // After the first write, the status line, headers and the (chunk-framed)
  // body all sit in ONE buffer - the coalescing this design exists for.
  asyncStart();
  final server = await HttpServer.bind("127.0.0.1", 0);
  server.listen((request) async {
    final response = request.response;
    response.write("x");
    var outgoing = await waitForBufferedHeaders(response);
    var buffered = String.fromCharCodes(
      outgoing.test$_buffer!.sublist(0, outgoing.test$_length),
    );
    Expect.isTrue(
      buffered.startsWith("HTTP/1.1 200"),
      "buffer starts with the status line: $buffered",
    );
    Expect.isTrue(
      buffered.contains("\r\nx"),
      "body follows the headers in the same buffer: $buffered",
    );
    await response.close();
  });

  final client = HttpClient();
  final response = await (await client.get(
    "127.0.0.1",
    server.port,
    "/",
  )).close();
  final body = await response.transform(utf8.decoder).join();
  Expect.equals("x", body);
  client.close();
  await server.close();
  asyncEnd();
}

Future<void> testAddChunkOrderingAndRealloc() async {
  // Drive _addChunk directly (with a recording sink) on a live response:
  // an oversized chunk must flush buffered data first, and after
  // drainBuffer() handed the buffer off, a new one is allocated.
  asyncStart();
  final server = await HttpServer.bind("127.0.0.1", 0);
  server.listen((request) async {
    final response = request.response;
    response.write("x");
    var outgoing = await waitForBufferedHeaders(response);

    var events = <List<int>>[];
    void recorder(List<int> data) => events.add(List.of(data));

    // Oversized chunk: buffered bytes are emitted first, then the chunk is
    // written directly - never the other way around.
    var lengthBefore = outgoing.test$_length;
    var oversized = Uint8List(bufferSize + 1);
    outgoing.test$_addChunk(oversized, recorder);
    Expect.equals(2, events.length);
    Expect.equals(lengthBefore, events[0].length);
    Expect.equals(oversized.length, events[1].length);
    Expect.equals(0, outgoing.test$_length);

    // A small chunk is buffered, not emitted.
    outgoing.test$_addChunk("abc".codeUnits, recorder);
    Expect.equals(2, events.length);
    Expect.equals(3, outgoing.test$_length);

    // flush() drains the buffer to the socket (calling drainBuffer directly
    // would throw here: the write("x") data cycle still has the socket sink
    // bound); the next chunk gets a freshly allocated buffer.
    await response.flush();
    Expect.isNull(outgoing.test$_buffer);
    Expect.equals(0, outgoing.test$_length);
    outgoing.test$_addChunk("de".codeUnits, recorder);
    Expect.equals(2, events.length);
    Expect.isNotNull(outgoing.test$_buffer);
    Expect.equals(2, outgoing.test$_length);

    // The wire bytes are mangled by the injected chunks; the raw client
    // below never parses them. Tear the connection down without closing
    // the response normally.
    await server.close(force: true);
    asyncEnd();
  });

  final socket = await Socket.connect("127.0.0.1", server.port);
  socket.write("GET / HTTP/1.1\r\nHost: localhost\r\n\r\n");
  socket.listen((_) {}, onDone: socket.destroy, onError: (_) {});
}

void main() async {
  asyncStart();
  testTakeBuffer();
  await testHeadersAndBodyShareBuffer();
  await testAddChunkOrderingAndRealloc();
  asyncEnd();
}
