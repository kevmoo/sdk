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

_COMPILE_PLATFORM = "pkg/front_end/tool/compile_platform.dart"

def dart_compile_platform(
        name,
        sources,
        sdk_sources,
        libraries_spec = "org-dartlang-sdk:///sdk/lib/libraries.json",
        product = False,
        exclude_source = False,
        sdk_hash = "0000000000",
        outline = None,
        **kwargs):
    """Compile the VM platform .dill + outline with the prebuilt SDK.

    Ports utils/compile_platform.gni (the prebuilt_dart_action branch) +
    runtime/vm/BUILD.gn:gen_vm_platform. Runs the prebuilt `dart` on
    pkg/front_end/tool/compile_platform.dart, which reads the SDK libraries
    (dart:core et al., in `sdk_sources`) plus the CFE and its package closure
    (in `sources`) and writes two outputs: the full platform `<name>.dill` and
    the summary outline `<name>_outline.dill`.

    The trailing positional arg order — outline, platform, outline — is exactly
    what GN passes (compile_platform.gni:90-91): restArguments[2] is the host
    platform read for the deps file, restArguments[4] is the outline output, and
    the platform output sits between them. sdk_hash must match the dartvm /
    gen_snapshot that consume the dill, or the VM rejects it at load.
    """
    platform_out = name + ".dill"
    outline_out = outline or (name + "_outline.dill")
    native.genrule(
        name = name,
        srcs = [_SDK_FILES, sources, sdk_sources],
        outs = [platform_out, outline_out],
        cmd = (
            "{dart} -Dsdk_hash={hash} --packages={pkg} {tool} " +
            "dart:core -Ddart.vm.product={product} -Ddart.vm.asan=false " +
            "-Ddart.vm.msan=false -Ddart.vm.tsan=false -Ddart.isVM=true {exclude}" +
            "--single-root-scheme=org-dartlang-sdk --single-root-base=$$(pwd) " +
            "{spec} $(location {outline}) $(location {platform}) $(location {outline})"
        ).format(
            dart = _PREBUILT_DART,
            hash = sdk_hash,
            pkg = _PACKAGE_CONFIG,
            tool = _COMPILE_PLATFORM,
            product = "true" if product else "false",
            exclude = "--exclude-source " if exclude_source else "",
            spec = libraries_spec,
            outline = outline_out,
            platform = platform_out,
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
        gen_snapshot_args = None,
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
    gen_snapshot_args = gen_snapshot_args or []

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

    # Stage 2: AOT ELF (mirrors the *_gen_snapshot gen_snapshot_action). The
    # genrule is named `name` (not `name + "_snapshot"`) so it is a drop-in for
    # the GN aot_snapshot() target of the same name — e.g. cross-package refs
    # like dds_aot -> //utils/dtd:dtd_aot_snapshot resolve unchanged.
    native.genrule(
        name = name,
        srcs = [dill],
        outs = [out or (name + ".snapshot")],
        tools = [gen_snapshot],
        cmd = "$(location {gs}) --deterministic --snapshot-kind=app-aot-elf --elf=$@ {gsargs}$(location {dill})".format(
            gs = gen_snapshot,
            gsargs = "".join([a + " " for a in gen_snapshot_args]),
            dill = dill,
        ),
        **kwargs
    )

def dart_app_jit_snapshot(
        name,
        main,
        sources,
        training_args,
        gen_kernel_dill,
        platform_dill,
        dart_vm,
        product = False,
        sdk_hash = "0000000000",
        gen_kernel_args = None,
        vm_args = None,
        out = None,
        **kwargs):
    """Build a Dart app-jit snapshot via a training run. Ports utils/application_snapshot.gni.

    Two stages:
      1. prebuilt `dart` + `gen_kernel_dill` compiles `main` to a *non-AOT*
         `.dart.dill` (`--no-aot --no-embed-sources --no-link-platform`, unlike
         dart_aot_snapshot's `--aot`).
      2. the Bazel-built `dart_vm` (//runtime/bin:dartvm) *executes* that dill
         with `training_args` under `--snapshot-kind=app-jit`, writing the
         app-jit snapshot. This mirrors the GN `dart_action` (APP_JIT) step --
         note it is the JIT VM doing a training run, NOT gen_snapshot. DFE is
         pinned to NEVER_LOADED so the VM doesn't pull in the kernel service
         (which would be a circular dep for kernel-service's own snapshot).
    """
    dill = name + ".dart.dill"
    gen_kernel_args = gen_kernel_args or []
    vm_args = list(vm_args or [])

    # GN injects --coverage=false (+ --ignore-unrecognized-flags, since
    # --coverage is unrecognized in product mode) unless --coverage is already
    # set. Mirror that here (application_snapshot.gni:75-90).
    if not [a for a in vm_args if a.startswith("--coverage")]:
        vm_args = vm_args + ["--coverage=false", "--ignore-unrecognized-flags"]

    # Stage 1: kernel compile (mirrors the *_dill prebuilt_dart_action). Same
    # shape as dart_aot_snapshot's stage 1 but with the app-jit gen_kernel flags.
    native.genrule(
        name = name + "_dill",
        srcs = [main, gen_kernel_dill, platform_dill, _SDK_FILES, sources],
        outs = [dill],
        cmd = (
            "{dart} -Dsdk_hash={hash} $(location {boot}) " +
            "--packages={pkg} --platform=$(location {plat}) " +
            "--no-aot --no-embed-sources --no-link-platform --output=$@ " +
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

    # Stage 2: app-jit training run (mirrors the dart_action APP_JIT step). The
    # genrule is named `name` so it is a drop-in for the GN target. `sources`
    # is included so .dart_tool/package_config.json (part of the opaque
    # filegroup) is materialized for --packages.
    native.genrule(
        name = name,
        srcs = [dill, _SDK_FILES, sources],
        outs = [out or (name + ".dart.snapshot")],
        tools = [dart_vm],
        cmd = (
            "$(location {vm}) --deterministic --packages={pkg} " +
            "--snapshot=$@ --snapshot-kind=app-jit --dfe=NEVER_LOADED " +
            "{vmargs}$(location {dill}) {targs}"
        ).format(
            vm = dart_vm,
            pkg = _PACKAGE_CONFIG,
            vmargs = "".join([a + " " for a in vm_args]),
            dill = dill,
            targs = " ".join(training_args),
        ),
        **kwargs
    )
