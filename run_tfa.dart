import 'dart:io';
import 'package:kernel/kernel.dart';
import 'package:kernel/target/targets.dart';
import 'package:kernel/core_types.dart';
import 'package:kernel/type_environment.dart';
import 'package:kernel/class_hierarchy.dart';
import 'package:kernel/library_index.dart';
import 'package:kernel/visitor.dart';
import 'package:vm/transformations/type_flow/transformer.dart' as tfa;
import 'package:vm/transformations/type_flow/analysis.dart' as tfa;
import 'package:vm/transformations/type_flow/calls.dart' as tfa;
import 'package:vm/transformations/type_flow/config.dart';
import 'package:vm/modular/target/vm.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    print('Usage: dart run_tfa.dart <path_to_dill>');
    exit(1);
  }

  final dillPath = args[0];
  print('Loading $dillPath...');
  final component = loadComponentFromBinary(dillPath);
  final coreTypes = CoreTypes(component);
  final hierarchy = ClassHierarchy(component, coreTypes) as ClosedWorldClassHierarchy;
  final environment = TypeEnvironment(coreTypes, hierarchy);
  final libraryIndex = LibraryIndex.all(component);

  print('Running TFA...');
  final config = TFAConfiguration();
  
  final analysis = tfa.TypeFlowAnalysis(
    config,
    VmTarget(TargetFlags()),
    component,
    coreTypes,
    hierarchy,
    tfa.GenericInterfacesInfoImpl(coreTypes, hierarchy),
    environment,
    libraryIndex,
    null, // protobufHandler
    null, // matcher
  );

  final mainMethod = component.mainMethod;
  if (mainMethod == null) {
    print('No main method.');
    return;
  }

  analysis.addRawCall(tfa.DirectSelector(mainMethod));
  
  for (final lib in component.libraries) {
    for (final cls in lib.classes) {
      analysis.addAllocatedClass(cls);
    }
  }

  print('Processing...');
  analysis.process();

  print('\nAnalyzing Virtual Calls in non-SDK code:');
  final visitor = VirtualCallTracer(analysis);
  for (final lib in component.libraries) {
    if (lib.importUri.scheme == 'dart') continue;
    lib.accept(visitor);
  }
}

class VirtualCallTracer extends RecursiveVisitor {
  final tfa.TypeFlowAnalysis analysis;
  VirtualCallTracer(this.analysis);

  @override
  void visitInstanceInvocation(InstanceInvocation node) {
    final callSite = analysis.callSite(node);
    final targets = callSite.targets;
    
    final member = node.enclosingMember;
    print('Virtual Call at ${member?.enclosingLibrary.importUri} :: ${member?.name}');
    print('  Selector: ${node.name}');
    print('  Possible Targets:');
    if (targets.isEmpty) {
      print('    <none or unknown>');
    } else {
      for (var target in targets) {
        print('    -> ${target.enclosingLibrary.importUri} :: ${target.name}');
      }
    }
    super.visitInstanceInvocation(node);
  }

  @override
  void visitDynamicInvocation(DynamicInvocation node) {
    final callSite = analysis.callSite(node);
    final targets = callSite.targets;
    
    final member = node.enclosingMember;
    print('Dynamic Call at ${member?.enclosingLibrary.importUri} :: ${member?.name}');
    print('  Selector: ${node.name}');
    print('  Possible Targets:');
    if (targets.isEmpty) {
      print('    <none or unknown>');
    } else {
      for (var target in targets) {
        print('    -> ${target.enclosingLibrary.importUri} :: ${target.name}');
      }
    }
    super.visitDynamicInvocation(node);
  }
}
