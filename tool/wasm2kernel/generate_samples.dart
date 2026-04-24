
import 'dart:io';
import 'dart:typed_data';
import '../../pkg/wasm_builder/lib/wasm_builder.dart';

void main() {
  final builder = ModuleBuilder('test_module', null);
  
  // Define function type: (i32, i32) -> i32
  final addType = builder.types.defineFunction(
    [NumType.i32, NumType.i32],
    [NumType.i32],
  );

  // Define the 'add' function
  final addFunction = builder.functions.define(addType, 'add');
  final b = addFunction.body;
  b.local_get(addFunction.locals[0]);
  b.local_get(addFunction.locals[1]);
  b.i32_add();
  b.end();

  // Export it
  builder.exports.export('add', addFunction);

  // Serialize to bytes
  final module = builder.build();
  final serializer = Serializer();
  module.serialize(serializer);
  final bytes = serializer.data;

  // Write to file
  File('add.wasm').writeAsBytesSync(bytes);
  print('Generated add.wasm (${bytes.length} bytes)');
  
  // TODO: Add more samples like factorial or memory access
}
