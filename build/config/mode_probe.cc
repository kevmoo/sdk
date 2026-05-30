// Trivial translation unit shared by the M4 config-axis select() mechanism
// proofs. Building //build/config:mode_probe (debug<->release) or
// //build/config:product_probe (product) materializes one CppCompile + one
// CppLink action whose command lines are the empirical probe for the folded
// delta (see build/config/BUILD.bazel and
// docs/todo_issues/m4_multiconfig_scoping.md).
int main() {
  return 0;
}
