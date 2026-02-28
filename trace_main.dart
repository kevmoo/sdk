import 'dart:io';
import 'package:kernel/kernel.dart';
import 'package:kernel/visitor.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    print('Usage: dart trace_main.dart <path_to_dill>');
    exit(1);
  }

  final dillPath = args[0];
  print('Loading $dillPath...');
  final component = loadComponentFromBinary(dillPath);

  final mainMethod = component.mainMethod;
  if (mainMethod == null) {
    print('No main method found in component.');
    return;
  }

  print('Found entry point: ${mainMethod.enclosingLibrary.importUri} :: ${mainMethod.name}');

  print('\nTracing call graph (depth limited):');
  final tracer = RecursiveCallTracer();
  tracer.trace(mainMethod);
}

class RecursiveCallTracer extends RecursiveVisitor {
  final Set<Reference> _visited = {};
  int _indent = 0;
  final int maxDepth = 10;

  void trace(Member member) {
    if (_visited.contains(member.reference)) return;
    if (_indent > maxDepth) return;
    
    _visited.add(member.reference);

    final libUri = member.enclosingLibrary.importUri;
    print('${"  " * _indent}${member.runtimeType}: $libUri :: ${member.name}');
    
    _indent++;
    member.accept(this);
    _indent--;
  }

  @override
  void visitStaticInvocation(StaticInvocation node) {
    trace(node.target);
  }

  @override
  void visitConstructorInvocation(ConstructorInvocation node) {
    trace(node.target);
  }

  @override
  void visitStaticGet(StaticGet node) {
    final target = node.target;
    if (target is Member) {
      trace(target);
    }
  }
}
