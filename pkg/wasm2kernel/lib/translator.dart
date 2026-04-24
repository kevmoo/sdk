
import 'dart:io';
import 'dart:typed_data';
import 'package:kernel/ast.dart';
import 'package:kernel/kernel.dart';
import 'package:kernel/core_types.dart';
import 'package:kernel/library_index.dart';
import 'package:wasm_builder/wasm_builder.dart' as wasm;

class WasmToKernel {
  final wasm.Module wasmModule;
  final Component component;
  final Library library;
  late final Class moduleClass;
  final Uri _dummyUri = Uri.parse('org-dartlang:///module.dart');
  
  late final CoreTypes coreTypes;
  late final LibraryIndex index;

  final Map<wasm.BaseFunction, Procedure> _functionMap = {};
  final Map<String, Procedure> _helpers = {};

  WasmToKernel(this.wasmModule, Component platformComponent)
      : component = Component(nameRoot: platformComponent.root),
        library = Library(Uri.parse('package:wasm_module/module.dart'), fileUri: Uri.parse('org-dartlang:///module.dart')) {
    
    component.libraries.add(library);
    library.parent = component;
    
    coreTypes = CoreTypes(platformComponent);
    index = LibraryIndex(platformComponent, ['dart:core', 'dart:typed_data']);

    moduleClass = Class(
      name: 'WasmModule', 
      supertype: coreTypes.objectClass.asRawSupertype,
      fileUri: _dummyUri,
    );
    moduleClass.addConstructor(Constructor(FunctionNode(Block([])), name: Name('', library), fileUri: _dummyUri));
    library.addClass(moduleClass);
  }

  void translate({String? testFuncName, List<Expression>? testArgs}) {
    // 1. Create helpers
    _getPopcntHelper(true);
    _getPopcntHelper(false);
    _getClzHelper(true);
    _getClzHelper(false);
    _getCtzHelper(true);
    _getCtzHelper(false);

    // 2. Translate functions
    for (var i = 0; i < wasmModule.functions.defined.length; i++) {
      var wasmFunc = wasmModule.functions.defined[i];
      var procedure = _translateFunction(wasmFunc);
      moduleClass.addProcedure(procedure);
      _functionMap[wasmFunc] = procedure;
    }

    if (testFuncName != null) {
      _addMain(targetName: testFuncName, args: testArgs ?? []);
    }
  }

  void _addMain({required String targetName, required List<Expression> args}) {
    var statements = <Statement>[];
    
    var constructor = moduleClass.constructors.first;
    var moduleVar = VariableDeclaration('m', 
        type: InterfaceType(moduleClass, Nullability.nonNullable),
        initializer: ConstructorInvocation(constructor, Arguments([])));
    statements.add(moduleVar);

    Procedure? procedure;
    try {
      final export = wasmModule.exports.exported.firstWhere((e) => e.name == targetName) as wasm.FunctionExport;
      procedure = _functionMap[export.function];
    } catch (_) {
      try {
        procedure = moduleClass.procedures.firstWhere((p) => p.name.text == targetName);
      } catch (_) {}
    }

    if (procedure == null) return;

    statements.add(ExpressionStatement(StaticInvocation(
      index.getTopLevelProcedure('dart:core', 'print'),
      Arguments([
        InstanceInvocation(
          InstanceAccessKind.Instance,
          VariableGet(moduleVar),
          procedure.name,
          Arguments(args),
          interfaceTarget: procedure,
          functionType: procedure.function.computeFunctionType(Nullability.nonNullable),
        )
      ])
    )));

    var mainProcedure = Procedure(
      Name('main', library),
      ProcedureKind.Method,
      FunctionNode(
        Block(statements),
        returnType: VoidType(),
      ),
      isStatic: true,
      fileUri: _dummyUri,
    );
    library.addProcedure(mainProcedure);
    component.setMainMethodAndMode(mainProcedure.reference, true);
  }

  Procedure _translateFunction(wasm.DefinedFunction wasmFunc) {
    var name = wasmFunc.functionName ?? 'func${wasmFunc.finalizableIndex.value}';
    
    var variableDeclarations = <VariableDeclaration>[];
    for (var i = 0; i < wasmFunc.type.inputs.length; i++) {
      var inputType = wasmFunc.type.inputs[i];
      variableDeclarations.add(VariableDeclaration(
        'p$i',
        type: _mapType(inputType),
      ));
    }

    var stack = <Expression>[];

    for (var instr in wasmFunc.body.instructions) {
      if (instr is wasm.LocalGet) {
        stack.add(VariableGet(variableDeclarations[instr.local.index]));
      } else if (instr is wasm.I32Add || instr is wasm.I64Add) {
        var right = stack.removeLast();
        var left = stack.removeLast();
        stack.add(_binOp(left, '+', right, isI32: instr is wasm.I32Add));
      } else if (instr is wasm.I32Sub || instr is wasm.I64Sub) {
        var right = stack.removeLast();
        var left = stack.removeLast();
        stack.add(_binOp(left, '-', right, isI32: instr is wasm.I32Sub));
      } else if (instr is wasm.I32Mul || instr is wasm.I64Mul) {
        var right = stack.removeLast();
        var left = stack.removeLast();
        stack.add(_binOp(left, '*', right, isI32: instr is wasm.I32Mul));
      } else if (instr is wasm.I32DivS || instr is wasm.I64DivS) {
        var right = stack.removeLast();
        var left = stack.removeLast();
        stack.add(_binOp(left, '~/', right, isI32: instr is wasm.I32DivS));
      } else if (instr is wasm.I32DivU || instr is wasm.I64DivU) {
        var right = stack.removeLast();
        var left = stack.removeLast();
        stack.add(_binOpUnsigned(left, '~/', right, isI32: instr is wasm.I32DivU));
      } else if (instr is wasm.I32RemS || instr is wasm.I64RemS) {
        var right = stack.removeLast();
        var left = stack.removeLast();
        stack.add(_binOp(left, '%', right, isI32: instr is wasm.I32RemS));
      } else if (instr is wasm.I32RemU || instr is wasm.I64RemU) {
        var right = stack.removeLast();
        var left = stack.removeLast();
        stack.add(_binOpUnsigned(left, '%', right, isI32: instr is wasm.I32RemU));
      } else if (instr is wasm.I32And || instr is wasm.I64And) {
        var right = stack.removeLast();
        var left = stack.removeLast();
        stack.add(_bitwiseOp(left, '&', right, isI32: instr is wasm.I32And));
      } else if (instr is wasm.I32Or || instr is wasm.I64Or) {
        var right = stack.removeLast();
        var left = stack.removeLast();
        stack.add(_bitwiseOp(left, '|', right, isI32: instr is wasm.I32Or));
      } else if (instr is wasm.I32Xor || instr is wasm.I64Xor) {
        var right = stack.removeLast();
        var left = stack.removeLast();
        stack.add(_bitwiseOp(left, '^', right, isI32: instr is wasm.I32Xor));
      } else if (instr is wasm.I32Shl || instr is wasm.I64Shl) {
        var right = stack.removeLast();
        var left = stack.removeLast();
        stack.add(_bitwiseOp(left, '<<', _maskShift(right, instr is wasm.I32Shl), isI32: instr is wasm.I32Shl));
      } else if (instr is wasm.I32ShrS || instr is wasm.I64ShrS) {
        var right = stack.removeLast();
        var left = stack.removeLast();
        stack.add(_bitwiseOp(left, '>>', _maskShift(right, instr is wasm.I32ShrS), isI32: instr is wasm.I32ShrS));
      } else if (instr is wasm.I32ShrU || instr is wasm.I64ShrU) {
        var right = stack.removeLast();
        var left = stack.removeLast();
        stack.add(_bitwiseOp(left, '>>>', _maskShift(right, instr is wasm.I32ShrU), isI32: instr is wasm.I32ShrU));
      } else if (instr is wasm.I32Eq || instr is wasm.I64Eq) {
        var right = stack.removeLast();
        var left = stack.removeLast();
        stack.add(_compare(left, '==', right));
      } else if (instr is wasm.I32Ne || instr is wasm.I64Ne) {
        var right = stack.removeLast();
        var left = stack.removeLast();
        stack.add(_boolToInt(Not(_compare(left, '==', right, wrapInBoolToInt: false))));
      } else if (instr is wasm.I32LtS || instr is wasm.I64LtS) {
        var right = stack.removeLast();
        var left = stack.removeLast();
        stack.add(_compare(left, '<', right));
      } else if (instr is wasm.I32LtU || instr is wasm.I64LtU) {
        var right = stack.removeLast();
        var left = stack.removeLast();
        stack.add(_compareUnsigned(left, '<', right, isI32: instr is wasm.I32LtU));
      } else if (instr is wasm.I32GtS || instr is wasm.I64GtS) {
        var right = stack.removeLast();
        var left = stack.removeLast();
        stack.add(_compare(left, '>', right));
      } else if (instr is wasm.I32GtU || instr is wasm.I64GtU) {
        var right = stack.removeLast();
        var left = stack.removeLast();
        stack.add(_compareUnsigned(left, '>', right, isI32: instr is wasm.I32GtU));
      } else if (instr is wasm.I32LeS || instr is wasm.I64LeS) {
        var right = stack.removeLast();
        var left = stack.removeLast();
        stack.add(_compare(left, '<=', right));
      } else if (instr is wasm.I32LeU || instr is wasm.I64LeU) {
        var right = stack.removeLast();
        var left = stack.removeLast();
        stack.add(_compareUnsigned(left, '<=', right, isI32: instr is wasm.I32LeU));
      } else if (instr is wasm.I32GeS || instr is wasm.I64GeS) {
        var right = stack.removeLast();
        var left = stack.removeLast();
        stack.add(_compare(left, '>=', right));
      } else if (instr is wasm.I32GeU || instr is wasm.I64GeU) {
        var right = stack.removeLast();
        var left = stack.removeLast();
        stack.add(_compareUnsigned(left, '>=', right, isI32: instr is wasm.I32GeU));
      } else if (instr is wasm.I32Eqz || instr is wasm.I64Eqz) {
        var val = stack.removeLast();
        stack.add(_boolToInt(InstanceInvocation(InstanceAccessKind.Instance, val, Name('==', library), Arguments([_intConst(0)]),
          interfaceTarget: _getOperator('num', '=='),
          functionType: _getOperator('num', '==').getterType as FunctionType)));
      } else if (instr is wasm.I32Clz || instr is wasm.I64Clz) {
        stack.add(StaticInvocation(_getClzHelper(instr is wasm.I32Clz), Arguments([stack.removeLast()])));
      } else if (instr is wasm.I32Ctz || instr is wasm.I64Ctz) {
        stack.add(StaticInvocation(_getCtzHelper(instr is wasm.I32Ctz), Arguments([stack.removeLast()])));
      } else if (instr is wasm.I32Popcnt || instr is wasm.I64Popcnt) {
        stack.add(StaticInvocation(_getPopcntHelper(instr is wasm.I32Popcnt), Arguments([stack.removeLast()])));
      } else if (instr is wasm.I32Rotl || instr is wasm.I64Rotl) {
        var amount = stack.removeLast();
        var val = stack.removeLast();
        stack.add(_rotl(val, amount, instr is wasm.I32Rotl));
      } else if (instr is wasm.I32Rotr || instr is wasm.I64Rotr) {
        var amount = stack.removeLast();
        var val = stack.removeLast();
        stack.add(_rotr(val, amount, instr is wasm.I32Rotr));
      } else if (instr is wasm.I32Extend8S || instr is wasm.I64Extend8S) {
        stack.add(_wrapToSigned8(stack.removeLast()));
      } else if (instr is wasm.I32Extend16S || instr is wasm.I64Extend16S) {
        stack.add(_wrapToSigned16(stack.removeLast()));
      } else if (instr is wasm.I64Extend32S) {
        stack.add(_wrapToSigned32(stack.removeLast()));
      } else if (instr is wasm.I32Const) {
        stack.add(_intConst(instr.value.toSigned(32)));
      } else if (instr is wasm.I64Const) {
        stack.add(_intConst(instr.value.toSigned(64)));
      } else if (instr is wasm.End) {
      }
    }

    var body = stack.isNotEmpty 
        ? ReturnStatement(stack.last)
        : ReturnStatement();

    return Procedure(
      Name(name, library),
      ProcedureKind.Method,
      FunctionNode(
        Block([body]),
        positionalParameters: variableDeclarations,
        returnType: wasmFunc.type.outputs.isNotEmpty 
            ? _mapType(wasmFunc.type.outputs.first) 
            : VoidType(),
      ),
      isStatic: false,
      fileUri: _dummyUri,
    );
  }

  Expression _maskShift(Expression amount, bool isI32) {
    var target = _getOperator('int', '&');
    return InstanceInvocation(InstanceAccessKind.Instance, amount, Name('&', library), Arguments([_intConst(isI32 ? 31 : 63)]),
        interfaceTarget: target,
        functionType: target.getterType as FunctionType);
  }

  Expression _binOp(Expression left, String op, Expression right, {required bool isI32}) {
     var target = _getOperator('num', op);
     var call = InstanceInvocation(InstanceAccessKind.Instance, left, Name(op, library), Arguments([right]),
          interfaceTarget: target,
          functionType: target.getterType as FunctionType);
     return isI32 ? _wrapToSigned32(call) : _wrapToSigned64(call);
  }

  Expression _binOpUnsigned(Expression left, String op, Expression right, {required bool isI32}) {
     var uLeft = isI32 ? _wrapToUnsigned32(left) : _wrapToUnsigned64(left);
     var uRight = isI32 ? _wrapToUnsigned32(right) : _wrapToUnsigned64(right);
     var target = _getOperator('num', op);
     var call = InstanceInvocation(InstanceAccessKind.Instance, uLeft, Name(op, library), Arguments([uRight]),
          interfaceTarget: target,
          functionType: target.getterType as FunctionType);
     return isI32 ? _wrapToSigned32(call) : _wrapToSigned64(call);
  }

  Expression _bitwiseOp(Expression left, String op, Expression right, {required bool isI32}) {
     var target = _getOperator('int', op);
     var call = InstanceInvocation(InstanceAccessKind.Instance, left, Name(op, library), Arguments([right]),
          interfaceTarget: target,
          functionType: target.getterType as FunctionType);
     return isI32 ? _wrapToSigned32(call) : _wrapToSigned64(call);
  }

  Expression _compare(Expression left, String op, Expression right, {bool wrapInBoolToInt = true}) {
    var target = _getOperator('num', op);
    var call = InstanceInvocation(InstanceAccessKind.Instance, left, Name(op, library), Arguments([right]),
        interfaceTarget: target,
        functionType: target.getterType as FunctionType);
    return wrapInBoolToInt ? _boolToInt(call) : call;
  }

  Expression _compareUnsigned(Expression left, String op, Expression right, {required bool isI32}) {
    var minInt = isI32 ? _intConst(0x80000000) : _intConst(-9223372036854775808);
    var a = _bitwiseOp(left, '^', minInt, isI32: isI32);
    var b = _bitwiseOp(right, '^', minInt, isI32: isI32);
    return _compare(a, op, b);
  }

  Expression _wrapToSigned32(Expression expr) {
     var toSigned = index.getProcedure('dart:core', 'int', 'toSigned');
     return InstanceInvocation(InstanceAccessKind.Instance, expr, Name('toSigned', library), Arguments([_intConst(32)]),
          interfaceTarget: toSigned,
          functionType: toSigned.getterType as FunctionType);
  }

  Expression _wrapToUnsigned32(Expression expr) {
     var toUnsigned = index.getProcedure('dart:core', 'int', 'toUnsigned');
     return InstanceInvocation(InstanceAccessKind.Instance, expr, Name('toUnsigned', library), Arguments([_intConst(32)]),
          interfaceTarget: toUnsigned,
          functionType: toUnsigned.getterType as FunctionType);
  }

  Expression _wrapToSigned64(Expression expr) {
     var toSigned = index.getProcedure('dart:core', 'int', 'toSigned');
     return InstanceInvocation(InstanceAccessKind.Instance, expr, Name('toSigned', library), Arguments([_intConst(64)]),
          interfaceTarget: toSigned,
          functionType: toSigned.getterType as FunctionType);
  }

  Expression _wrapToUnsigned64(Expression expr) {
     var toUnsigned = index.getProcedure('dart:core', 'int', 'toUnsigned');
     return InstanceInvocation(InstanceAccessKind.Instance, expr, Name('toUnsigned', library), Arguments([_intConst(64)]),
          interfaceTarget: toUnsigned,
          functionType: toUnsigned.getterType as FunctionType);
  }

  Expression _wrapToSigned8(Expression expr) {
     var toSigned = index.getProcedure('dart:core', 'int', 'toSigned');
     return InstanceInvocation(InstanceAccessKind.Instance, expr, Name('toSigned', library), Arguments([_intConst(8)]),
          interfaceTarget: toSigned,
          functionType: toSigned.getterType as FunctionType);
  }

  Expression _wrapToSigned16(Expression expr) {
     var toSigned = index.getProcedure('dart:core', 'int', 'toSigned');
     return InstanceInvocation(InstanceAccessKind.Instance, expr, Name('toSigned', library), Arguments([_intConst(16)]),
          interfaceTarget: toSigned,
          functionType: toSigned.getterType as FunctionType);
  }

  Expression _intConst(int val) {
    return ConstantExpression(IntConstant(val));
  }

  Procedure _getPopcntHelper(bool isI32) {
    final name = isI32 ? '_popcnt32' : '_popcnt64';
    if (_helpers.containsKey(name)) return _helpers[name]!;

    final param = VariableDeclaration('x', type: coreTypes.intNonNullableRawType);
    final countVar = VariableDeclaration('count', initializer: _intConst(0), type: coreTypes.intNonNullableRawType);
    final xVar = VariableDeclaration('val', initializer: VariableGet(param), type: coreTypes.intNonNullableRawType);
    
    final body = Block([
      countVar,
      xVar,
      WhileStatement(
        Not(InstanceInvocation(InstanceAccessKind.Instance, VariableGet(xVar), Name('==', library), Arguments([_intConst(0)]),
          interfaceTarget: _getOperator('num', '=='),
          functionType: _getOperator('num', '==').getterType as FunctionType)),
        Block([
          ExpressionStatement(VariableSet(xVar, _bitwiseOp(VariableGet(xVar), '&', _binOp(VariableGet(xVar), '-', _intConst(1), isI32: false), isI32: false))),
          ExpressionStatement(VariableSet(countVar, _binOp(VariableGet(countVar), '+', _intConst(1), isI32: false))),
        ])
      ),
      ReturnStatement(VariableGet(countVar)),
    ]);

    final proc = Procedure(Name(name, library), ProcedureKind.Method, FunctionNode(body, positionalParameters: [param], returnType: coreTypes.intNonNullableRawType), isStatic: true, fileUri: _dummyUri);
    moduleClass.addProcedure(proc);
    _helpers[name] = proc;
    return proc;
  }

  Procedure _getClzHelper(bool isI32) {
    final name = isI32 ? '_clz32' : '_clz64';
    if (_helpers.containsKey(name)) return _helpers[name]!;

    final param = VariableDeclaration('x', type: coreTypes.intNonNullableRawType);
    final val = VariableGet(param);
    
    // Wasm clz behavior: 
    // if x == 0 return 64
    // if x < 0 return 0 (sign bit set)
    // else return 64 - x.bitLength
    final body = ReturnStatement(ConditionalExpression(
      _compare(val, '==', _intConst(0), wrapInBoolToInt: false),
      _intConst(isI32 ? 32 : 64),
      ConditionalExpression(
        _compare(val, '<', _intConst(0), wrapInBoolToInt: false),
        _intConst(0),
        _binOp(_intConst(isI32 ? 32 : 64), '-', 
          InstanceGet(InstanceAccessKind.Instance, isI32 ? _wrapToUnsigned32(val) : val, Name('bitLength', library), 
            interfaceTarget: _getOperator('int', 'get:bitLength'), resultType: coreTypes.intNonNullableRawType),
          isI32: isI32),
        coreTypes.intNonNullableRawType
      ),
      coreTypes.intNonNullableRawType
    ));

    final proc = Procedure(Name(name, library), ProcedureKind.Method, FunctionNode(body, positionalParameters: [param], returnType: coreTypes.intNonNullableRawType), isStatic: true, fileUri: _dummyUri);
    moduleClass.addProcedure(proc);
    _helpers[name] = proc;
    return proc;
  }

  Procedure _getCtzHelper(bool isI32) {
    final name = isI32 ? '_ctz32' : '_ctz64';
    if (_helpers.containsKey(name)) return _helpers[name]!;

    final param = VariableDeclaration('x', type: coreTypes.intNonNullableRawType);
    final val = VariableGet(param);
    
    // Wasm ctz behavior:
    // if x == 0 return 64
    // else return ((x & -x) - 1).bitLength
    final body = ReturnStatement(ConditionalExpression(
      _compare(val, '==', _intConst(0), wrapInBoolToInt: false),
      _intConst(isI32 ? 32 : 64),
      InstanceGet(InstanceAccessKind.Instance, 
        _binOp(_bitwiseOp(val, '&', _binOp(_intConst(0), '-', val, isI32: isI32), isI32: isI32), '-', _intConst(1), isI32: isI32),
        Name('bitLength', library), interfaceTarget: _getOperator('int', 'get:bitLength'), resultType: coreTypes.intNonNullableRawType),
      coreTypes.intNonNullableRawType
    ));

    final proc = Procedure(Name(name, library), ProcedureKind.Method, FunctionNode(body, positionalParameters: [param], returnType: coreTypes.intNonNullableRawType), isStatic: true, fileUri: _dummyUri);
    moduleClass.addProcedure(proc);
    _helpers[name] = proc;
    return proc;
  }

  Expression _rotl(Expression val, Expression amount, bool isI32) {
    var mask = _intConst(isI32 ? 31 : 63);
    var bits = _intConst(isI32 ? 32 : 64);
    var maskedAmount = _bitwiseOp(amount, '&', mask, isI32: isI32);
    var leftShift = _bitwiseOp(val, '<<', maskedAmount, isI32: isI32);
    var rightAmount = _binOp(bits, '-', maskedAmount, isI32: isI32);
    var rightShift = _bitwiseOp(val, '>>>', rightAmount, isI32: isI32);
    return _bitwiseOp(leftShift, '|', rightShift, isI32: isI32);
  }

  Expression _rotr(Expression val, Expression amount, bool isI32) {
    var mask = _intConst(isI32 ? 31 : 63);
    var bits = _intConst(isI32 ? 32 : 64);
    var maskedAmount = _bitwiseOp(amount, '&', mask, isI32: isI32);
    var rightShift = _bitwiseOp(val, '>>>', maskedAmount, isI32: isI32);
    var leftAmount = _binOp(bits, '-', maskedAmount, isI32: isI32);
    var leftShift = _bitwiseOp(val, '<<', leftAmount, isI32: isI32);
    return _bitwiseOp(rightShift, '|', leftShift, isI32: isI32);
  }

  Expression _boolToInt(Expression boolExpr) {
    return ConditionalExpression(boolExpr, _intConst(1), _intConst(0), coreTypes.intNonNullableRawType);
  }

  Procedure _getOperator(String className, String op) {
    try {
      return index.getProcedure('dart:core', className, op);
    } catch (e) {
      if (className == 'int') {
        return index.getProcedure('dart:core', 'num', op);
      }
      rethrow;
    }
  }

  DartType _mapType(wasm.ValueType type) {
    if (type is wasm.NumType) {
      if (type == wasm.NumType.i32 || type == wasm.NumType.i64) {
        return coreTypes.intNonNullableRawType;
      }
      if (type == wasm.NumType.f32 || type == wasm.NumType.f64) {
        return coreTypes.doubleNonNullableRawType;
      }
    }
    return DynamicType();
  }
}
