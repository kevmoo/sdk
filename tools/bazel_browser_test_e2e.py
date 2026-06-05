#!/usr/bin/env python3
# Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
# for details. All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.

import os
import shutil
import subprocess
import tempfile
import unittest

class BazelBrowserTestE2E(unittest.TestCase):

    def setUp(self):
        self.workspace_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        self.dart_sdk_bin = os.path.join(self.workspace_dir, 'tools', 'sdks', 'dart-sdk', 'bin', 'dart')
        self.generator_script = os.path.join(self.workspace_dir, 'tools', 'bazel', 'dart', 'generate_test_targets.dart')
        self.test_py = os.path.join(self.workspace_dir, 'tools', 'test.py')
        self.bazel_output_base = os.path.join(self.workspace_dir, 'out', 'bazel_e2e_ob')

    def test_r1_dynamic_vm_target_selection(self):
        print("\n=== [R1] VM Target Selection Tests ===")
        
        # 1. Build SDK in default mode
        print("Building default SDK...")
        res_default = subprocess.run(
            ['bazel', f'--output_base={self.bazel_output_base}', 'build', '//sdk:create_sdk'],
            cwd=self.workspace_dir,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        self.assertEqual(res_default.returncode, 0, f"Default build failed:\n{res_default.stderr}")
        
        # Resolve bazel-bin path dynamically for the isolated output base
        res_info = subprocess.run(
            ['bazel', f'--output_base={self.bazel_output_base}', 'info', 'bazel-bin'],
            cwd=self.workspace_dir,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        self.assertEqual(res_info.returncode, 0, f"Failed to get bazel-bin path: {res_info.stderr}")
        bazel_bin_dir = res_info.stdout.strip()
        
        dart_path = os.path.join(bazel_bin_dir, 'sdk', 'dart-sdk', 'bin', 'dart')
        dartaot_path = os.path.join(bazel_bin_dir, 'sdk', 'dart-sdk', 'bin', 'dartaotruntime')
        self.assertTrue(os.path.exists(dart_path), f"Dart VM binary missing at {dart_path}")
        self.assertTrue(os.path.exists(dartaot_path), f"AOT runtime binary missing at {dartaot_path}")

        # 2. Build SDK in product mode
        print("Building product SDK...")
        res_product = subprocess.run(
            ['bazel', f'--output_base={self.bazel_output_base}', 'build', '--//build/config:dart_product=true', '//sdk:create_sdk'],
            cwd=self.workspace_dir,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        self.assertEqual(res_product.returncode, 0, f"Product build failed:\n{res_product.stderr}")
        self.assertTrue(os.path.exists(dart_path), f"Dart VM binary missing at {dart_path}")
        self.assertTrue(os.path.exists(dartaot_path), f"AOT runtime binary missing at {dartaot_path}")

    def test_r2_target_generation(self):
        print("\n=== [R2] Target Generation Tests ===")
        with tempfile.TemporaryDirectory() as tmpdir:
            print(f"Running generate_test_targets.dart with output-dir={tmpdir}...")
            res = subprocess.run([
                self.dart_sdk_bin,
                self.generator_script,
                f'--workspace-dir={self.workspace_dir}',
                f'--output-dir={tmpdir}',
                '--suite=corelib'
            ], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            
            self.assertEqual(res.returncode, 0, f"Generator failed:\nStdout: {res.stdout}\nStderr: {res.stderr}")
            
            corelib_build_path = os.path.join(tmpdir, 'corelib', 'BUILD.bazel')
            self.assertTrue(os.path.exists(corelib_build_path), f"BUILD.bazel not generated at {corelib_build_path}")
            
            with open(corelib_build_path, 'r') as f:
                content = f.read()
            
            # Assert all browser target suffixes are present
            self.assertIn('_wasm_chrome_release', content)
            self.assertIn('_wasm_firefox_release', content)
            self.assertIn('_dart2js_chrome_release', content)
            self.assertIn('_dart2js_firefox_release', content)
            print("Successfully verified generated target configs contain browser configurations.")

    def test_r3_wrapper_routing_e2e(self):
        print("\n=== [R3] Wrapper Routing E2E Tests ===")
        
        # Setup dummy bazel in a temp directory to intercept commands
        with tempfile.TemporaryDirectory() as tmpdir:
            dummy_bazel_path = os.path.join(tmpdir, 'bazel')
            
            # Write a dummy bazel script that prints call arguments and mock query results
            with open(dummy_bazel_path, 'w') as f:
                f.write('''#!/usr/bin/env python3
import sys
args = sys.argv[1:]
if 'query' in args:
    repo = [a for a in args if a.startswith('@')][0]
    repo_name = repo.split('//')[0]
    targets = [
        f"{repo_name}//corelib:tests_wasm_chrome_release",
        f"{repo_name}//corelib:list_test_wasm_chrome_release",
        f"{repo_name}//corelib:tests_wasm_firefox_release",
        f"{repo_name}//corelib:list_test_wasm_firefox_release",
        f"{repo_name}//corelib:tests_dart2js_chrome_release",
        f"{repo_name}//corelib:list_test_dart2js_chrome_release",
        f"{repo_name}//corelib:tests_dart2js_firefox_release",
        f"{repo_name}//corelib:list_test_dart2js_firefox_release",
        f"{repo_name}//corelib:tests_vm_product",
        f"{repo_name}//corelib:list_test_vm_product",
    ]
    print('\\n'.join(targets))
    sys.exit(0)
elif 'test' in args:
    print("DUMMY_BAZEL_RUN: " + " ".join(sys.argv))
    sys.exit(0)
''')
            
            os.chmod(dummy_bazel_path, 0o755)
            
            # Modify environment to prepend tmpdir to PATH
            env = os.environ.copy()
            env['PATH'] = tmpdir + os.pathsep + env['PATH']
            
            # Run wrapper with different browser configurations
            configs = [
                ('dart2wasm-chrome', '@dart_tests//corelib:list_test_wasm_chrome_release'),
                ('dart2wasm-firefox', '@dart_tests//corelib:list_test_wasm_firefox_release'),
                ('dart2js-chrome', '@dart_tests//corelib:list_test_dart2js_chrome_release'),
                ('dart2js-firefox', '@dart_tests//corelib:list_test_dart2js_firefox_release'),
            ]
            
            for config_name, expected_target in configs:
                print(f"Testing wrapper routing for config '{config_name}'...")
                res = subprocess.run([
                    'python3',
                    self.test_py,
                    '--bazel',
                    '-n', config_name,
                    'corelib/list_test'
                ], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                
                self.assertEqual(res.returncode, 0, f"Wrapper failed for {config_name}:\nStdout: {res.stdout}\nStderr: {res.stderr}")
                self.assertIn("DUMMY_BAZEL_RUN:", res.stdout)
                self.assertIn(expected_target, res.stdout)
                print(f"Verified wrapper routed correctly to {expected_target}")

if __name__ == '__main__':
    unittest.main()
