import 'dart:io';
import 'dart:typed_data';

/// A throughput test client for [Socket2].
///
/// This client connects to a server and sends a large amount of data
/// as fast as possible using a fixed buffer pool.
void main(List<String> args) async {
  if (args.length < 2) {
    print(
      'Usage: dart socket2_throughput_client.dart <host> <port> [MB_to_send]',
    );
    return;
  }

  final host = args[0];
  final port = int.parse(args[1]);
  final mbToSend = args.length > 2 ? int.parse(args[2]) : 100;
  final totalBytes = mbToSend * 1024 * 1024;

  print('Connecting to $host:$port...');
  final socket = await Socket2.connect(host, port);
  print('Connected. Sending $mbToSend MB...');

  final stopwatch = Stopwatch()..start();
  final buffer = Uint8List(64 * 1024);
  int totalWritten = 0;

  while (totalWritten < totalBytes) {
    final result = await socket.write(buffer);
    totalWritten += result.bytes;
  }

  stopwatch.stop();
  await socket.close();

  final double mbps =
      (totalWritten / (1024 * 1024)) / (stopwatch.elapsedMilliseconds / 1000);
  print('Sent $totalWritten bytes in ${stopwatch.elapsedMilliseconds}ms');
  print('Throughput: ${mbps.toStringAsFixed(2)} MB/s');
}
