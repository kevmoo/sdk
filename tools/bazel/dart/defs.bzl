"""Minimal Dart-compilation rules for the Bazel migration (rules_dart Step 0).

Ports the GN `aot_snapshot` template (utils/aot_snapshot.gni) and the
`bootstrap_gen_kernel` prebuilt-dart action (utils/gen_kernel/BUILD.gn) as
genrule-based macros. Scope is deliberately minimal — this is the first proof
that a Bazel rule can produce a real Dart AOT snapshot. See
docs/todo_issues/rules_dart_scoping.md for the full plan and the open
deps-model / Bzlmod decisions this intentionally defers.

Deps model: OPAQUE. Every macro takes a `sources` label (a filegroup of the
whole Dart package closure) rather than a per-package dep graph. This mirrors
today's non-hermetic GN build and unblocks the first proof; the gazelle-style
pubspec->deps generator that recovers incrementality is a later step.

sdk_hash discipline: the prebuilt `dart` and the Bazel-built `gen_snapshot`
both bake sdk_hash=0000000000, so every snapshot here must compile with the
same hash or the VM rejects it at load. The default below matches.
"""

_PREBUILT_DART = "tools/sdks/dart-sdk/bin/dart"
_SDK_FILES = "//tools/sdks/dart-sdk:sdk_files"
_PACKAGE_CONFIG = ".dart_tool/package_config.json"

def dart_kernel_snapshot(name, main, sources, sdk_hash = "0000000000", **kwargs):
    """Compile a Dart script to a *kernel* snapshot with the prebuilt SDK.

    Mirrors utils/gen_kernel/BUILD.gn:bootstrap_gen_kernel — i.e.
    `dart --snapshot-kind=kernel --snapshot=OUT <main>`. Used to (re)build
    bootstrap_gen_kernel.dill itself, avoiding the stale checked-in blob.
    """
    native.genrule(
        name = name,
        srcs = [main, _SDK_FILES, sources],
        outs = [name + ".dill"],
        cmd = (
            "{dart} --snapshot-kind=kernel --snapshot=$@ " +
            "-Dsdk_hash={hash} --packages={pkg} $(location {main})"
        ).format(
            dart = _PREBUILT_DART,
            hash = sdk_hash,
            pkg = _PACKAGE_CONFIG,
            main = main,
        ),
        **kwargs
    )

def dart_aot_snapshot(
        name,
        main,
        sources,
        gen_kernel_dill,
        platform_dill,
        gen_snapshot,
        product = True,
        sdk_hash = "0000000000",
        gen_kernel_args = None,
        out = None,
        **kwargs):
    """Build a Dart AOT (app-aot-elf) snapshot. Ports utils/aot_snapshot.gni.

    Two stages:
      1. prebuilt `dart` + `gen_kernel_dill` compiles `main` (+ its package
         closure in `sources`) to a `.dart.dill`, with --aot.
      2. the Bazel-built `gen_snapshot` (pass gen_snapshot_product for product
         mode) turns the dill into an AOT ELF.
    """
    dill = name + ".dart.dill"
    gen_kernel_args = gen_kernel_args or []

    # Stage 1: kernel compile (mirrors the *_dill prebuilt_dart_action).
    native.genrule(
        name = name + "_dill",
        srcs = [main, gen_kernel_dill, platform_dill, _SDK_FILES, sources],
        outs = [dill],
        cmd = (
            "{dart} -Dsdk_hash={hash} $(location {boot}) " +
            "--packages={pkg} --platform=$(location {plat}) --aot --output=$@ " +
            "-Dsdk_hash={hash} -Ddart.vm.product={product} " +
            "-Ddart.vm.asan=false -Ddart.vm.msan=false -Ddart.vm.tsan=false " +
            "{extra}$(location {main})"
        ).format(
            dart = _PREBUILT_DART,
            hash = sdk_hash,
            boot = gen_kernel_dill,
            pkg = _PACKAGE_CONFIG,
            plat = platform_dill,
            product = "true" if product else "false",
            extra = "".join([a + " " for a in gen_kernel_args]),
            main = main,
        ),
    )

    # Stage 2: AOT ELF (mirrors the *_gen_snapshot gen_snapshot_action).
    native.genrule(
        name = name + "_snapshot",
        srcs = [dill],
        outs = [out or (name + ".snapshot")],
        tools = [gen_snapshot],
        cmd = "$(location {gs}) --deterministic --snapshot-kind=app-aot-elf --elf=$@ $(location {dill})".format(
            gs = gen_snapshot,
            dill = dill,
        ),
        **kwargs
    )
