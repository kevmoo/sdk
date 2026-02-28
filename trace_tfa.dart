import 'dart:io';
import 'package:kernel/kernel.dart';
import 'package:kernel/target/targets.dart';
import 'package:kernel/core_types.dart';
import 'package:kernel/type_environment.dart';
import 'package:kernel/class_hierarchy.dart';
import 'package:kernel/library_index.dart';
import 'package:vm/transformations/type_flow/analysis.dart' as tfa;
import 'package:vm/transformations/type_flow/calls.dart' as tfa;
import 'package:vm/transformations/type_flow/config.dart';
import 'package:vm/modular/target/vm.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    print('Usage: dart trace_tfa.dart <path_to_dill>');
    exit(1);
  }

  final dillPath = args[0];
  print('Loading $dillPath...');
  final component = loadComponentFromBinary(dillPath);
  final coreTypes = CoreTypes(component);
  final hierarchy = ClassHierarchy(component, coreTypes) as ClosedWorldClassHierarchy;
  final environment = TypeEnvironment(coreTypes, hierarchy);
  final libraryIndex = LibraryIndex.all(component);

  print('Running Type Flow Analysis (TFA)...');
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

  // 1. Add entry point
  analysis.addRawCall(tfa.DirectSelector(mainMethod));
  
  // 2. Add all potentially allocated classes (simplified RTA)
  for (final lib in component.libraries) {
    for (final cls in lib.classes) {
      analysis.addAllocatedClass(cls);
    }
  }

  // 3. Process to convergence
  print('Processing call graph flow...');
  analysis.process();

  // 4. Report reachable members
  print('\nReachable members found by TFA:');
  int count = 0;
  for (final lib in component.libraries) {
    if (lib.importUri.scheme == 'dart') continue;
    
    bool libHeaderPrinted = false;

    void printLib() {
      if (!libHeaderPrinted) {
        print('\nLibrary: ${lib.importUri}');
        libHeaderPrinted = true;
      }
    }

    for (final member in lib.members) {
      if (analysis.isMemberUsed(member)) {
        printLib();
        print('  Member: ${member.name}');
        count++;
      }
    }
    for (final cls in lib.classes) {
      for (final member in cls.members) {
        if (analysis.isMemberUsed(member)) {
          printLib();
          print('  Class ${cls.name} :: Member: ${member.name}');
          count++;
        }
      }
    }
  }
  print('\nTotal reachable non-SDK members: $count');
}
