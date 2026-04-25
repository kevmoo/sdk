import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:expect/expect.dart';

void main() {
  runZonedGuarded(
    () async {
      try {
        print("Running testReadTwiceThrows...");
        await testReadTwiceThrows();
        print("Running testZeroLengthReadWrite...");
        await testZeroLengthReadWrite();
        print("Running testSimultaneousReadWrite...");
        await testSimultaneousReadWrite();
        print("Running testConnectionDropDuringRead...");
        await testConnectionDropDuringRead();
        print("Running testAddressResolution...");
        await testAddressResolution();
        print("Running testPartialWrite...");
        await testPartialWrite();
        print("Running testCloseCancelsPendingRead...");
        await testCloseCancelsPendingRead();
        print("Running testLargeTransfer...");
        await testLargeTransfer();
        print("All tests completed successfully!");

        print("Waiting for 2 seconds to see if background exception occurs...");
        await Future.delayed(Duration(seconds: 2));
        print("Exiting main normally.");
      } catch (e, st) {
        stdout.writeln("Caught exception in main: $e");
        stdout.writeln(st);
        await stdout.flush();
      }
    },
    (error, stackTrace) {
      stdout.writeln("Caught UNHANDLED exception in zone: $error");
      stdout.writeln(stackTrace);
      stdout.flush();
    },
  );
}

Future<void> testReadTwiceThrows() async {
  final server = await ServerSocket2.bind('127.0.0.1', 0);
  final port = server.port;

  final clientFuture = Socket2.connect('127.0.0.1', port);
  final serverSocketFuture = server.accept();

  final client = await clientFuture;
  final serverConnection = await serverSocketFuture;

  final buffer = Uint8List(10);

  final readFuture = client.read(buffer);

  try {
    await client.read(buffer);
    Expect.fail("Should have thrown StateError");
  } catch (e) {
    Expect.isTrue(e is StateError);
    Expect.equals(
      "A read operation is already pending.",
      (e as StateError).message,
    );
  }

  // Handle the error of the first read future, which was cancelled on close.
  final expectReadFuture = readFuture
      .then((_) {
        Expect.fail("Should have thrown SocketException");
      })
      .catchError((e) {
        Expect.isTrue(e is SocketException);
      });

  // Clean up.
  await client.close();
  await expectReadFuture;

  await serverConnection.close();
  await server.close();
}

Future<void> testZeroLengthReadWrite() async {
  final server = await ServerSocket2.bind('127.0.0.1', 0);
  final port = server.port;

  final clientFuture = Socket2.connect('127.0.0.1', port);
  final serverSocketFuture = server.accept();

  final client = await clientFuture;
  final serverConnection = await serverSocketFuture;

  final emptyBuffer = Uint8List(0);

  // Test zero-length write.
  final writeResult = await client.write(emptyBuffer);
  Expect.equals(0, writeResult.bytes);
  Expect.equals(emptyBuffer, writeResult.buffer);

  // Test zero-length read.
  final readResult = await client.read(emptyBuffer);
  Expect.equals(0, readResult.bytes);
  Expect.equals(emptyBuffer, readResult.buffer);

  await client.close();
  await serverConnection.close();
  await server.close();
}

Future<void> testSimultaneousReadWrite() async {
  final server = await ServerSocket2.bind('127.0.0.1', 0);
  final port = server.port;

  final clientFuture = Socket2.connect('127.0.0.1', port);
  final serverSocketFuture = server.accept();

  final client = await clientFuture;
  final serverConnection = await serverSocketFuture;

  final buffer1 = Uint8List(10);
  final buffer2 = Uint8List(10);

  final readFuture = client.read(buffer1);
  final writeFuture = client.write(buffer2);

  final serverBuffer = Uint8List(10);

  Future<void> runServer() async {
    await serverConnection.write(serverBuffer);
    await serverConnection.read(serverBuffer);
  }

  final serverOperationsFuture = runServer();

  await Future.wait([readFuture, writeFuture, serverOperationsFuture]);

  final readResult = await readFuture;
  final writeResult = await writeFuture;

  Expect.isTrue(readResult.bytes > 0);
  Expect.isTrue(writeResult.bytes > 0);

  await client.close();
  await serverConnection.close();
  await server.close();
}

Future<void> testConnectionDropDuringRead() async {
  final server = await ServerSocket2.bind('127.0.0.1', 0);
  final port = server.port;

  final clientFuture = Socket2.connect('127.0.0.1', port);
  final serverSocketFuture = server.accept();

  final client = await clientFuture;
  final serverConnection = await serverSocketFuture;

  final buffer = Uint8List(10);

  // Initiate read on client.
  final readFuture = client.read(buffer);

  final expectReadFuture = readFuture
      .then((_) {
        Expect.fail("Should have thrown SocketException");
      })
      .catchError((e) {
        Expect.isTrue(e is SocketException);
      });

  // Close connection from server side.
  await serverConnection.close();
  await expectReadFuture;

  await client.close();
  await server.close();
}

Future<void> testAddressResolution() async {
  final server = await ServerSocket2.bind('127.0.0.1', 0);
  final port = server.port;

  // Test localhost.
  final client1Future = Socket2.connect('localhost', port);
  final serverSocketFuture1 = server.accept();

  final client1 = await client1Future;
  final serverConnection1 = await serverSocketFuture1;
  await client1.close();
  await serverConnection1.close();

  // Test 127.0.0.1.
  final client2Future = Socket2.connect('127.0.0.1', port);
  final serverSocketFuture2 = server.accept();

  final client2 = await client2Future;
  final serverConnection2 = await serverSocketFuture2;
  await client2.close();
  await serverConnection2.close();

  // Test invalid DNS name.
  try {
    await Socket2.connect('invalid.domain.name.that.does.not.exist', port);
    Expect.fail("Should have thrown SocketException");
  } catch (e) {
    Expect.isTrue(e is SocketException);
  }

  await server.close();
}

Future<void> testPartialWrite() async {
  final server = await ServerSocket2.bind('127.0.0.1', 0);
  final port = server.port;

  final clientFuture = Socket2.connect('127.0.0.1', port);
  final serverSocketFuture = server.accept();

  final client = await clientFuture;
  final serverConnection = await serverSocketFuture;

  // 1MB buffer to force partial writes.
  final largeBuffer = Uint8List(1 * 1024 * 1024);
  for (int i = 0; i < largeBuffer.length; i++) {
    largeBuffer[i] = i % 256;
  }

  // Server reads in background to drain the buffer.
  // START THIS BEFORE CLIENT WRITES!
  final serverReadFuture = Future(() async {
    int totalRead = 0;
    final serverBuffer = Uint8List(1024 * 1024); // 1MB chunks
    while (totalRead < largeBuffer.lengthInBytes) {
      stdout.writeln("Server trying to read...");
      await stdout.flush();
      final result = await serverConnection.read(serverBuffer);
      stdout.writeln("Server read ${result.bytes} bytes");
      await stdout.flush();
      if (result.bytes == 0) break; // Socket closed
      totalRead += result.bytes;
    }
    return totalRead;
  });

  // Initiate write on client.
  final writeResult = await client.write(largeBuffer);
  stdout.writeln("Initial bytes written: ${writeResult.bytes}");
  await stdout.flush();

  int totalWritten = writeResult.bytes;

  // Client continues writing the rest.
  while (totalWritten < largeBuffer.lengthInBytes) {
    final view = Uint8List.sublistView(largeBuffer, totalWritten);
    stdout.writeln("Client trying to write...");
    await stdout.flush();

    // Yield control to allow the server read future to start/continue!
    await Future.delayed(Duration.zero);

    final result = await client.write(view);
    stdout.writeln("Client wrote ${result.bytes} bytes");
    await stdout.flush();
    totalWritten += result.bytes;
  }

  Expect.equals(largeBuffer.lengthInBytes, totalWritten);

  final totalRead = await serverReadFuture;
  Expect.equals(largeBuffer.lengthInBytes, totalRead);

  await client.close();
  await serverConnection.close();
  await server.close();
}

Future<void> testCloseCancelsPendingRead() async {
  final server = await ServerSocket2.bind('127.0.0.1', 0);
  final port = server.port;

  final clientFuture = Socket2.connect('127.0.0.1', port);
  final serverSocketFuture = server.accept();

  final client = await clientFuture;
  final serverConnection = await serverSocketFuture;

  final buffer = Uint8List(10);

  // Initiate read.
  final readFuture = client.read(buffer);

  // Attach listener immediately to avoid unhandled exception on yield during close.
  final expectFuture = readFuture
      .then((_) {
        Expect.fail("Should have thrown SocketException");
      })
      .catchError((e) {
        Expect.isTrue(e is SocketException);
        Expect.equals("Socket closed", (e as SocketException).message);
      });

  // Close client.
  await client.close();

  // Wait for the expectation to be verified.
  await expectFuture;

  await serverConnection.close();
  await server.close();
}

Future<void> testLargeTransfer() async {
  final server = await ServerSocket2.bind('127.0.0.1', 0);
  final port = server.port;

  final totalBytes = 5 * 1024 * 1024; // 5MB
  final buffer = Uint8List(64 * 1024);

  final serverFuture = Future(() async {
    final socket = await server.accept();
    int totalRead = 0;
    while (totalRead < totalBytes) {
      final result = await socket.read(buffer);
      if (result.bytes == 0) break;
      totalRead += result.bytes;
    }
    await socket.close();
    await server.close();
    return totalRead;
  });

  final client = await Socket2.connect('127.0.0.1', port);
  int totalWritten = 0;
  while (totalWritten < totalBytes) {
    final result = await client.write(buffer);
    totalWritten += result.bytes;
  }
  await client.close();

  final totalRead = await serverFuture;
  Expect.equals(totalBytes, totalRead);
  Expect.equals(totalBytes, totalWritten);
}
