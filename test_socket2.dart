import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

void main() async {
  print("Connecting...");
  try {
    var socket = await Socket2.connect("google.com", 80);
    print("Connected to Google!");
    
    // Write request
    var reqString = "GET / HTTP/1.1\r\nHost: google.com\r\nConnection: close\r\n\r\n";
    var reqBytes = utf8.encode(reqString);
    var reqBuffer = Uint8List.fromList(reqBytes).buffer;
    
    print("Writing request...");
    var writeResult = await socket.write(reqBuffer);
    print("Wrote ${writeResult.$1} bytes");

    // Read response
    print("Reading response...");
    var resBuffer = Uint8List(1024).buffer;
    var readResult = await socket.read(resBuffer);
    print("Read ${readResult.$1} bytes");
    
    if (readResult.$1 > 0) {
      var resString = utf8.decode(Uint8List.view(readResult.$2, 0, readResult.$1));
      print("Response:\n$resString");
    }

    await socket.close();
    print("Closed.");
  } catch (e, st) {
    print("Error: $e\n$st");
  }
}
