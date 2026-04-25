import 'dart:io';
import 'dart:typed_data';

import 'package:expect/expect.dart';

void main() async {
  await testReadTwiceThrows();
  await testZeroLengthReadWrite();
  await testSimultaneousReadWrite();
  await testConnectionDropDuringRead();
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
