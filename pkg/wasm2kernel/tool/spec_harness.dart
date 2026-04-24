
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

void main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart tool/spec_harness.dart <test.json> [--limit=N] [--concurrency=N]');
    exit(1);
  }

  final jsonPath = p.absolute(args[0]);
  int limit = 100;
  int concurrency = 12;
  for (var arg in args) {
    if (arg.startsWith('--limit=')) {
      limit = int.parse(arg.split('=')[1]);
    }
    if (arg.startsWith('--concurrency=')) {
      concurrency = int.parse(arg.split('=')[1]);
    }
  }

  final jsonDir = p.dirname(jsonPath);
  final manifest = jsonDecode(File(jsonPath).readAsStringSync());
  
  String? currentWasm;
  int passed = 0;
  int failed = 0;
  int skipped = 0;

  final commands = manifest['commands'] as List;
  
  var currentModuleWasm = '';
  var assertionQueue = <Map>[];

  Future<void> flushQueue() async {
    if (assertionQueue.isEmpty) return;
    print('\nTesting Module: ${p.basename(currentModuleWasm)} (${assertionQueue.length} assertions)');
    
    var localPassed = 0;
    var localFailed = 0;
    
    for (var i = 0; i < assertionQueue.length; i += concurrency) {
      if (failed + localFailed >= limit) break;
      
      var chunk = assertionQueue.sublist(i, (i + concurrency > assertionQueue.length) ? assertionQueue.length : i + concurrency);
      var results = await Future.wait(chunk.map((cmd) => runAssertion(currentModuleWasm, cmd)));
      
      for (var j = 0; j < results.length; j++) {
        if (results[j]) {
          localPassed++;
          stdout.write('.');
        } else {
          localFailed++;
          var cmd = chunk[j];
          print('\n[Line ${cmd["line"]}] FAIL: ${cmd["action"]["field"]}');
          // Re-run sequentially for detail
          await runAssertion(currentModuleWasm, cmd, verbose: true);
        }
      }
    }
    passed += localPassed;
    failed += localFailed;
    assertionQueue.clear();
  }

  for (var command in commands) {
    final type = command['type'];

    if (type == 'module') {
      await flushQueue();
      currentModuleWasm = p.join(jsonDir, command['filename']);
    } else if (type == 'assert_return') {
      if (currentModuleWasm.isEmpty) continue;
      final action = command['action'];
      if (action['type'] == 'invoke') {
        assertionQueue.add(command);
      }
    } else {
      skipped++;
    }
    
    if (failed >= limit) break;
  }
  await flushQueue();

  print('\n\n--- Spec Results ---');
  print('Passed: $passed');
  print('Failed: $failed');
  print('Skipped: $skipped');
}

Future<bool> runAssertion(String wasmPath, Map command, {bool verbose = false}) async {
  final action = command['action'];
  final funcName = action['field'];
  final args = action['args'] as List;
  final expected = command['expected'] as List;
  final line = command['line'];

  final tempDill = wasmPath + '.line$line.temp.dill';
  final scriptDir = p.dirname(Platform.script.toFilePath());
  final binPath = p.join(p.dirname(scriptDir), 'bin', 'wasm2kernel.dart');

  List<String> stringArgs = [];
  for (var arg in args) {
    stringArgs.add(arg['value'].toString());
  }

  final translateResult = await Process.run('dart', [
    binPath,
    wasmPath,
    tempDill,
    funcName,
    ...stringArgs
  ]);

  if (translateResult.exitCode != 0) {
    if (verbose) print('      Translation error: ${translateResult.stderr}');
    return false;
  }

  final runResult = await Process.run('dart', [tempDill]);
  try { await File(tempDill).delete(); } catch (_) {}

  if (runResult.exitCode != 0) {
    if (verbose) print('      Runtime error: ${runResult.stderr}');
    return false;
  }

  final actualOutput = runResult.stdout.toString().trim();
  if (expected.isEmpty) return true;

  final expectedRaw = expected[0]['value'].toString();
  final expectedInt = BigInt.parse(expectedRaw).toSigned(64);
  final actualInt = BigInt.tryParse(actualOutput)?.toSigned(64);

  bool success = false;
  if (actualInt != null) {
    success = actualInt == expectedInt;
  } else {
    success = actualOutput == expectedRaw;
  }

  if (!success && verbose) {
    print('      Expected: $expectedInt (raw: $expectedRaw)');
    print('      Actual:   $actualOutput');
  }

  return success;
}
