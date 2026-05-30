// Trivial translation unit for the M4 debug<->release select() mechanism proof.
// Building //build/config:mode_probe materializes one CppCompile + one CppLink
// action whose command lines are the empirical probe for the folded delta (see
// build/config/BUILD.bazel and docs/todo_issues/m4_multiconfig_scoping.md).
int main() {
  return 0;
}
