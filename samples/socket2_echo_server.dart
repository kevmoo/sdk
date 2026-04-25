import 'dart:io';
import 'dart:typed_data';

/// A high-performance echo server using [ServerSocket2] and [Socket2].
///
/// This example demonstrates how to use a buffer pool with [Socket2] to
/// achieve high-throughput without steady-state memory allocations.
void main() async {
  final server = await ServerSocket2.bind(InternetAddress.anyIPv4, 8080);
  print('Echo server listening on port ${server.port}');

  while (true) {
    try {
      final socket = await server.accept();
      print(
        'Accepted connection from ${socket}',
      ); // Note: Socket2 toString pending implementation
      _handleConnection(socket);
    } catch (e) {
      print('Error accepting connection: $e');
    }
  }
}

/// Handles a single connection by echoing all data back to the client.
Future<void> _handleConnection(Socket2 socket) async {
  // Use a 64KB buffer for transfers.
  // In a real application, this buffer would be returned to a pool.
  var buffer = Uint8List(64 * 1024);

  try {
    while (true) {
      // 1. Give ownership of the buffer to the socket for reading.
      final readResult = await socket.read(buffer);

      // 2. The socket returns ownership of the buffer in the record.
      buffer = readResult.buffer as Uint8List;
      final bytesRead = readResult.bytes;

      if (bytesRead == 0) {
        print('Client closed connection');
        break;
      }

      // 3. Give ownership of the buffer to the socket for writing.
      // We only write the bytes we actually read.
      final writeResult = await socket.write(
        Uint8List.sublistView(buffer, 0, bytesRead),
      );

      // 4. The socket returns ownership of the buffer.
      // Note: sublistView creates a view, so the underlying buffer is still the same.
      // In this specific completion API, the record returns the TypedData passed in.
      buffer = writeResult.buffer as Uint8List;
    }
  } catch (e) {
    print('Connection error: $e');
  } finally {
    await socket.close();
  }
}
