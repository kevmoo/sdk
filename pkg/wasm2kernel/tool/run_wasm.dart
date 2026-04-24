import 'dart:io';
import 'package:path/path.dart' as p;

void main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart tool/run_wasm.dart <file.wat|file.wasm>');
    exit(1);
  }

  final inputPath = p.absolute(args[0]);
  final extension = p.extension(inputPath);
  final dir = p.dirname(inputPath);
  final basename = p.basenameWithoutExtension(inputPath);

  String wasmPath;
  if (extension == '.wat') {
    wasmPath = p.join(dir, '$basename.wasm');
    print('Compiling $inputPath to $wasmPath...');
    final result = await Process.run('wat2wasm', [inputPath, '-o', wasmPath]);
    if (result.exitCode != 0) {
      print('wat2wasm failed:');
      print(result.stderr);
      exit(result.exitCode);
    }
  } else if (extension == '.wasm') {
    wasmPath = inputPath;
  } else {
    print('Unsupported file extension: $extension');
    exit(1);
  }

  final dillPath = p.join(dir, '$basename.dill');
  final scriptDir = p.dirname(Platform.script.toFilePath());
  final binPath = p.join(p.dirname(scriptDir), 'bin', 'wasm2kernel.dart');

  print('Translating $wasmPath to $dillPath...');
  final translateResult = await Process.run(
    'dart',
    [binPath, wasmPath, dillPath],
    workingDirectory: p.dirname(binPath),
  );
  if (translateResult.exitCode != 0) {
    print('Translation failed:');
    print(translateResult.stdout);
    print(translateResult.stderr);
    exit(translateResult.exitCode);
  }

  print('Running $dillPath...');
  final runResult = await Process.run('dart', [dillPath]);
  print('--- Output ---');
  print(runResult.stdout);
  if (runResult.stderr.toString().isNotEmpty) {
    print('--- Errors ---');
    print(runResult.stderr);
  }
}
