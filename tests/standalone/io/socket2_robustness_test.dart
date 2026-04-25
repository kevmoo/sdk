import 'dart:io';
import 'dart:typed_data';

import 'package:expect/expect.dart';

void main() async {
  await testReadTwiceThrows();
  await testZeroLengthReadWrite();
  await testSimultaneousReadWrite();
  await testConnectionDropDuringRead();
  await testAddressResolution();
  await testPartialWrite();
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
    Expect.equals("A read operation is already pending.",
        (e as StateError).message);
  }
  
  await client.close();
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
  
  // Initiate read and write simultaneously on the client.
  final readFuture = client.read(buffer1);
  final writeFuture = client.write(buffer2);
  
  // Server needs to write something so the read completes,
  // and read something so the write completes.
  final serverBuffer = Uint8List(10);
  await serverConnection.write(serverBuffer);
  await serverConnection.read(serverBuffer);
  
  final results = await Future.wait([readFuture, writeFuture]);
  
  final readResult = results[0];
  final writeResult = results[1];
  
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
  
  // Close connection from server side.
  await serverConnection.close();
  
  try {
    await readFuture;
    Expect.fail("Should have thrown SocketException");
  } catch (e) {
    Expect.isTrue(e is SocketException);
  }
  
  await client.close();
  await server.close();
}

Future<void> testAddressResolution() async {
  final server = await ServerSocket2.bind('127.0.0.1', 0);
  final port = server.port;
  
  // Test localhost.
  final client1 = await Socket2.connect('localhost', port);
  await client1.close();
  
  // Test 127.0.0.1.
  final client2 = await Socket2.connect('127.0.0.1', port);
  await client2.close();
  
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
  
  // 1MB buffer to reduce timeout risk while still forcing partial writes.
  final largeBuffer = Uint8List(1 * 1024 * 1024);
  for (int i = 0; i < largeBuffer.length; i++) {
    largeBuffer[i] = i % 256;
  }
  
  // Initiate write on client.
  final writeResult = await client.write(largeBuffer);
  stdout.writeln("Initial bytes written: ${writeResult.bytes}");
  await stdout.flush();
  
  int totalWritten = writeResult.bytes;
  
  // Server reads in background to drain the buffer.
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
