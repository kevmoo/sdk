#!/usr/bin/env python3
# Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
# for details. All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.

import json
import re
import subprocess
import sys

def run_bench(runtime_path, bench_path, filter_str=None):
    cmd = [runtime_path, '--print-metrics', bench_path]
    if filter_str:
        cmd.append(f'--filter={filter_str}')
    proc = subprocess.run(cmd, capture_output=True, text=True)
    out = proc.stdout.strip()
    err = proc.stderr

    metrics = {}
    matches = re.findall(r'--- Benchmark:\s+(.+?)\s+---\nTime per iteration:\s+([\d.]+)\s+us\nThroughput:\s+([\d.]+)\s+ops/sec', out)
    for name, time_us, thr in matches:
        metrics[name.strip()] = {
            'microsPerOp': float(time_us),
            'opsPerSec': float(thr)
        }

    if not metrics:
        print(f"Failed to parse benchmark output from {runtime_path} (filter={filter_str}):\nStdout:\n{out}\nStderr:\n{err}", file=sys.stderr)
        sys.exit(1)

    heap_global = re.search(r'heap\.global\.used[^\(]+\((\d+)\s+B\)', err)
    heap_new = re.search(r'heap\.new\.used\.max[^\(]+\((\d+)\s+B\)', err)
    return {
        'metrics': metrics,
        'heap_global': int(heap_global.group(1)) if heap_global else None,
        'heap_new': int(heap_new.group(1)) if heap_new else None
    }

def print_gc_table(title, base_data, ref_data):
    print(f"\n### {title}\n")
    print("| Heap Telemetry Metric | Baseline Control Footprint | Refactored Experimental Footprint | Net Reduction Δ (%) |")
    print("| :--- | :---: | :---: | :---: |")
    if base_data['heap_global'] and ref_data['heap_global']:
        b_val = base_data['heap_global']
        r_val = ref_data['heap_global']
        diff = (r_val - b_val) / b_val * 100.0
        print(f"| **Global Main Heap (`heap.global.used`)** | {b_val:,} B | {r_val:,} B | **{diff:+.2f}%** ({r_val - b_val:,} B) |")
    if base_data['heap_new'] and ref_data['heap_new']:
        b_val = base_data['heap_new']
        r_val = ref_data['heap_new']
        diff = (r_val - b_val) / b_val * 100.0
        print(f"| **Peak Nursery GC Churn (`heap.new.used.max`)** | {b_val:,} B | {r_val:,} B | **{diff:+.2f}%** ({r_val - b_val:,} B) |")

def main():
    base_runtime = '/usr/local/google/home/kevmoo/github/dart-sdk/core/agent-zone-baseline/sdk/out/ReleaseX64/dart'
    ref_runtime = '/usr/local/google/home/kevmoo/github/dart-sdk/core/agent-zone-refactor/sdk/out/ReleaseX64/dart'
    bench_script = 'tests/lib/async/zone_perf_bench.dart'

    print("Running full benchmark suite across runtimes for execution throughput comparison...", file=sys.stderr)
    base = run_bench(base_runtime, bench_script)
    ref = run_bench(ref_runtime, bench_script)

    print("Running targeted unconfounded GC measurements for Zone.fork...", file=sys.stderr)
    base_fork = run_bench(base_runtime, bench_script, "Zone.fork (custom")
    ref_fork = run_bench(ref_runtime, bench_script, "Zone.fork (custom")

    print("Running targeted unconfounded GC measurements for runZoned...", file=sys.stderr)
    base_rz = run_bench(base_runtime, bench_script, "runZoned (custom")
    ref_rz = run_bench(ref_runtime, bench_script, "runZoned (custom")

    print("### Quantified Side-by-Side Controlled Execution Metrics\n")
    print("| Target Operation | Baseline Control (Time/Iter) | Baseline Control (Throughput) | Refactored Experimental (Time/Iter) | Refactored Experimental (Throughput) | Speedup Δ (%) |")
    print("| :--- | :---: | :---: | :---: | :---: | :---: |")

    for name, b_item in base['metrics'].items():
        if name not in ref['metrics']:
            continue
        r_item = ref['metrics'][name]
        b_time = b_item['microsPerOp']
        b_ops = b_item['opsPerSec']
        r_time = r_item['microsPerOp']
        r_ops = r_item['opsPerSec']
        speedup = (r_ops - b_ops) / b_ops * 100.0
        print(f"| **{name}** | {b_time:.6f} µs | {b_ops:,.2f} ops/sec | {r_time:.6f} µs | {r_ops:,.2f} ops/sec | **{speedup:+.2f}%** |")

    print_gc_table("Isolated GC & Memory Telemetry: Custom `Zone.fork` Spawning", base_fork, ref_fork)
    print_gc_table("Isolated GC & Memory Telemetry: Custom `runZoned` Execution", base_rz, ref_rz)

    if all(k in base['metrics'] for k in ['Direct closure invocation', 'Zone.current.run(closure)', 'runZoned (no specification)']):
        b_dir = base['metrics']['Direct closure invocation']['microsPerOp']
        b_run = base['metrics']['Zone.current.run(closure)']['microsPerOp']
        b_rz = base['metrics']['runZoned (no specification)']['microsPerOp']

        r_dir = ref['metrics']['Direct closure invocation']['microsPerOp']
        r_run = ref['metrics']['Zone.current.run(closure)']['microsPerOp']
        r_rz = ref['metrics']['runZoned (no specification)']['microsPerOp']

        print("\n### Quantified Closure Wrapping & Zone Switching Overhead\n")
        print(f"- **Baseline Zone Switching Overhead (`Zone.current.run` vs Direct)**: {b_run - b_dir:.6f} µs")
        print(f"- **Refactored Zone Switching Overhead (`Zone.current.run` vs Direct)**: {r_run - r_dir:.6f} µs")
        print(f"- **Baseline `runZoned` Closure Wrapping Overhead (`runZoned` vs `Zone.current.run`)**: {b_rz - b_run:.6f} µs")
        print(f"- **Refactored `runZoned` Closure Wrapping Overhead (`runZoned` vs `Zone.current.run`)**: {r_rz - r_run:.6f} µs")

if __name__ == '__main__':
    main()

