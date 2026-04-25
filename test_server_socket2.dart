import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

void main() async {
  print("Starting ServerSocket2 on port 8081...");
  try {
    var server = await ServerSocket2.bind('localhost', 8081);
    print("Bound to ${server}!");

    // Run client in background
    Future.microtask(() async {
      try {
        print("Client connecting...");
        var client = await Socket2.connect('localhost', 8081);
        print("Client connected!");
        var req = utf8.encode("Hello from client!");
        var buffer = Uint8List.fromList(req);
        await client.write(buffer);
        await client.close();
      } catch (e) {
        print("Client error: $e");
      }
    });

    print("Server waiting for connection...");
    var socket = await server.accept();
    print("Server accepted connection!");

    var buffer = Uint8List(1024);
    var result = await socket.read(buffer);
    print("Server read ${result.bytes} bytes");

    var resString = utf8.decode(Uint8List.sublistView(result.buffer, 0, result.bytes));
    print("Server received: $resString");

    await socket.close();
    await server.close();
    print("All closed.");
  } catch (e, st) {
    print("Error: $e\n$st");
  }
}
