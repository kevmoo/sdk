import 'dart:convert';

void main() {
  // Generate a large ASCII one-byte JSON string (~5MB)
  final list = List.generate(
    100000,
    (i) => {
      'id': i,
      'name': 'user_$i',
      'active': i % 2 == 0,
      'scores': [10, 20, 30],
    },
  );
  final asciiJson = jsonEncode(list);
  final asciiBytes = utf8.encode(asciiJson);

  // Generate a two-byte JSON string (containing non-ASCII characters)
  final unicodeList = List.generate(
    50000,
    (i) => {
      'id': i,
      'name': 'ユーザー_$i',
      'active': i % 2 == 0,
      'scores': [10, 20, 30],
    },
  );
  final unicodeJson = jsonEncode(unicodeList);
  final unicodeBytes = utf8.encode(unicodeJson);

  final utf8JsonDecoder = utf8.decoder.fuse(json.decoder);

  print('Warmup...');
  for (var i = 0; i < 3; i++) {
    jsonDecode(asciiJson);
    utf8JsonDecoder.convert(asciiBytes);
    jsonDecode(unicodeJson);
    utf8JsonDecoder.convert(unicodeBytes);
  }

  const iterations = 20;

  // Benchmark String Decoding
  final stopwatch = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    jsonDecode(asciiJson);
  }
  stopwatch.stop();
  print(
    'String Decode (ASCII): ${stopwatch.elapsedMilliseconds / iterations} ms per iteration',
  );

  // Benchmark UTF-8 Direct Byte Decoding
  stopwatch.reset();
  stopwatch.start();
  for (var i = 0; i < iterations; i++) {
    utf8JsonDecoder.convert(asciiBytes);
  }
  stopwatch.stop();
  print(
    'UTF-8 Direct Byte Decode (ASCII): ${stopwatch.elapsedMilliseconds / iterations} ms per iteration',
  );
}
