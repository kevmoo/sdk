import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

const int BUFFER_SIZE = 64 * 1024;
const int TOTAL_BYTES = 100 * 1024 * 1024; // 100MB

void main() async {
  final server = await ServerSocket2.bind('127.0.0.1', 0);
  final port = server.port;

  print('Starting 100MB throughput benchmark...');

  final stopwatch = Stopwatch()..start();

  // Server: Read
  Future<int> runServer() async {
    print('Server: Waiting for accept...');
    final socket = await server.accept();
    print('Server: Accepted connection');
    final buffer = Uint8List(BUFFER_SIZE);
    int totalRead = 0;
    while (totalRead < TOTAL_BYTES) {
      final result = await socket.read(buffer);
      if (result.bytes == 0) {
        print('Server: EOF reached at $totalRead bytes');
        break;
      }
      totalRead += result.bytes;
      if (totalRead % (1024 * 1024) == 0) {
        print('Server: Read $totalRead bytes...');
      }
    }
    print('Server: Closing socket...');
    await socket.close();
    await server.close();
    return totalRead;
  }

  final serverFuture = runServer();

  // Client: Write
  print('Client: Connecting to $port...');
  final client = await Socket2.connect('127.0.0.1', port);
  print('Client: Connected');
  final buffer = Uint8List(BUFFER_SIZE);
  int totalWritten = 0;
  while (totalWritten < TOTAL_BYTES) {
    final result = await client.write(buffer);
    totalWritten += result.bytes;
    if (totalWritten % (1024 * 1024) == 0) {
      print('Client: Wrote $totalWritten bytes...');
    }
  }
  print('Client: Finished writing $totalWritten bytes, closing...');
  await client.close();

  final totalRead = await serverFuture;
  stopwatch.stop();

  final double mbps =
      (totalRead / (1024 * 1024)) / (stopwatch.elapsedMilliseconds / 1000);
  print('Completed in ${stopwatch.elapsedMilliseconds}ms');
  print('Throughput: ${mbps.toStringAsFixed(2)} MB/s');
  print('Total bytes read: $totalRead');
}
