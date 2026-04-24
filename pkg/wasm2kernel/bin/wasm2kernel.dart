
import 'dart:io';
import 'package:kernel/ast.dart';
import 'package:kernel/kernel.dart';
import 'package:wasm_builder/wasm_builder.dart' as wasm;
import 'package:wasm2kernel/translator.dart';

void main(List<String> args) {
  if (args.length < 2) {
    print('Usage: wasm2kernel <input.wasm> <output.dill> [funcName] [arg1 arg2 ...]');
    exit(1);
  }

  final inputPath = args[0];
  final outputPath = args[1];
  final String? testFuncName = args.length > 2 ? args[2] : null;
  
  final List<Expression> testArgs = [];
  if (args.length > 3) {
    for (var i = 3; i < args.length; i++) {
      // Use BigInt to handle full 64-bit range from CLI
      var val = BigInt.parse(args[i]).toSigned(64);
      testArgs.add(ConstantExpression(IntConstant(val.toInt())));
    }
  }

  final platformDillPath = '/Users/kevmoo/github/flutter/bin/cache/dart-sdk/lib/_internal/vm_platform_strong.dill';
  final platformComponent = loadComponentFromBinary(platformDillPath);

  final bytes = File(inputPath).readAsBytesSync();
  final deserializer = wasm.Deserializer(bytes);
  final wasmModule = wasm.Module.deserialize(deserializer);

  final translator = WasmToKernel(wasmModule, platformComponent);
  translator.translate(testFuncName: testFuncName, testArgs: testArgs);

  writeComponentToBinary(translator.component, outputPath);
}
