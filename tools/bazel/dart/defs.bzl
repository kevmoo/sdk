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

# The package map as a standalone filegroup input. Since `sources` is a per-package
# dart_library closure (.dart files only), this materializes
# .dart_tool/package_config.json for the --packages flag.
_PACKAGE_CONFIG_FILE = "//:package_config_json"

# rules_dart Step 3 (per-package deps): a real per-package dependency graph that
# feeds each tool its own closure. DartLibraryInfo carries the transitive
# closure of a package's .dart sources as a depset; DefaultInfo exposes it so a
# snapshot genrule can take a single dart_library as `sources` and materialize
# exactly that package's closure (not all ~197 packages). Edges come from each
# pubspec's `dependencies:` (a cycle-free safe superset of real imports — see
# docs/todo_issues/rules_dart_scoping.md §8). The graph is generated into
# packages.bzl by gen_packages.py.

DartLibraryInfo = provider(
    doc = "Transitive closure of a Dart package's library sources.",
    fields = {"transitive_srcs": "depset of .dart files in this package + its deps"},
)

def _dart_library_impl(ctx):
    transitive = depset(
        direct = ctx.files.srcs,
        transitive = [d[DartLibraryInfo].transitive_srcs for d in ctx.attr.deps],
    )
    return [
        DefaultInfo(files = transitive),
        DartLibraryInfo(transitive_srcs = transitive),
    ]

dart_library = rule(
    implementation = _dart_library_impl,
    doc = "A Dart package: its own lib sources plus its transitive dep closure.",
    attrs = {
        "srcs": attr.label_list(allow_files = [".dart"]),
        "deps": attr.label_list(providers = [DartLibraryInfo]),
    },
)

# rules_dart Step 5 (sdk/ assembly): the SDK platform libraries (dart:core et al.)
# staged into the final dart-sdk/lib/<name> layout. Ports the GN copy_tree
# template (build/dart/copy_tree.gni -> tools/copy_tree.py): each
# copy_${library}_library copies sdk/lib/<library> with the same exclude globs.
_SDK_LIB_EXCLUDE = "*.svn,doc,*.py,*.gypi,*.sh,.git*,*.gn,*.gni"

def _copy_tree_impl(ctx):
    out = ctx.actions.declare_directory(ctx.attr.out_dir)
    ctx.actions.run_shell(
        command = "python3 {tool} --from {src} --to {to} --exclude '{exclude}'".format(
            tool = ctx.file._tool.path,
            src = ctx.attr.src_dir,
            to = out.path,
            exclude = ctx.attr.exclude,
        ),
        inputs = ctx.files.srcs + [ctx.file._tool],
        outputs = [out],
        mnemonic = "CopyTree",
        progress_message = "Staging SDK tree %s" % ctx.attr.out_dir,
    )
    return [DefaultInfo(files = depset([out]))]

copy_tree = rule(
    implementation = _copy_tree_impl,
    doc = "Stage src_dir into an output tree, mirroring GN copy_tree " +
          "(tools/copy_tree.py): same shutil.copytree + ignore_patterns(exclude).",
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
            doc = "Every file under src_dir (a glob); excluded files are " +
                  "harmless extra inputs, the action filters them out.",
        ),
        "src_dir": attr.string(
            mandatory = True,
            doc = "Execroot-relative source directory, e.g. sdk/lib/core.",
        ),
        "out_dir": attr.string(
            mandatory = True,
            doc = "Output tree path under the package's bin dir, e.g. lib/core.",
        ),
        "exclude": attr.string(
            default = "",
            doc = "GN-style comma-separated ignore_patterns globs.",
        ),
        "_tool": attr.label(
            default = "//tools/bazel/dart:copytree.py",
            allow_single_file = True,
        ),
    },
)

def _copy_internal_with_dills_impl(ctx):
    out = ctx.actions.declare_directory(ctx.attr.out_dir)
    ctx.actions.run_shell(
        command = (
            "python3 {tool} --from {src} --to {to} --exclude '{exclude}' && " +
            "cp {vm_plat} {to}/vm_platform.dill && " +
            "cp {vm_plat} {to}/vm_platform_strong.dill && " +
            "cp {vm_plat_prod} {to}/vm_platform_product.dill"
        ).format(
            tool = ctx.file._tool.path,
            src = ctx.attr.src_dir,
            to = out.path,
            exclude = ctx.attr.exclude,
            vm_plat = ctx.file.vm_platform.path,
            vm_plat_prod = ctx.file.vm_platform_product.path,
        ),
        inputs = ctx.files.srcs + [
            ctx.file._tool,
            ctx.file.vm_platform,
            ctx.file.vm_platform_product,
        ],
        outputs = [out],
        mnemonic = "CopyInternalWithDills",
        progress_message = "Staging SDK internal library with VM platform dills",
    )
    return [DefaultInfo(files = depset([out]))]

copy_internal_with_dills = rule(
    implementation = _copy_internal_with_dills_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
        ),
        "src_dir": attr.string(
            mandatory = True,
        ),
        "out_dir": attr.string(
            mandatory = True,
        ),
        "exclude": attr.string(
            default = "",
        ),
        "vm_platform": attr.label(
            mandatory = True,
            allow_single_file = True,
        ),
        "vm_platform_product": attr.label(
            mandatory = True,
            allow_single_file = True,
        ),
        "_tool": attr.label(
            default = "//tools/bazel/dart:copytree.py",
            allow_single_file = True,
        ),
    },
)

def copy_sdk_library(name, lib, exclude = _SDK_LIB_EXCLUDE, **kwargs):
    """Stage sdk/lib/<lib> -> <bin>/dart-sdk/lib/<lib>, porting GN copy_${lib}_library.

    Rooted under the GN dart_sdk_output ("dart-sdk/") prefix so the assembled
    tree matches out/ReleaseX64/dart-sdk/ and single-file outputs (libraries.json,
    version) don't collide with the same-named //sdk source labels.
    """
    copy_tree(
        name = name,
        srcs = native.glob(["lib/%s/**" % lib], allow_empty = False),
        src_dir = native.package_name() + "/lib/" + lib,
        out_dir = "dart-sdk/lib/" + lib,
        exclude = exclude,
        **kwargs
    )

def dart_kernel_snapshot(name, main, sources, sdk_hash = "0000000000", **kwargs):
    """Compile a Dart script to a *kernel* snapshot with the prebuilt SDK.

    Mirrors utils/gen_kernel/BUILD.gn:bootstrap_gen_kernel — i.e.
    `dart --snapshot-kind=kernel --snapshot=OUT <main>`. Used to (re)build
    bootstrap_gen_kernel.dill itself, avoiding the stale checked-in blob.
    """
    native.genrule(
        name = name,
        srcs = [main, _SDK_FILES, sources, _PACKAGE_CONFIG_FILE],
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
        platform_out = None,
        platform_args = None,
        single_root_base = None,
        deps_outline = None,
        **kwargs):
    """Compile a platform .dill + outline with the prebuilt SDK.

    Ports utils/compile_platform.gni (the prebuilt_dart_action branch). Runs the
    prebuilt `dart` on pkg/front_end/tool/compile_platform.dart, which reads the
    SDK libraries (dart:core et al., in `sdk_sources`) plus the CFE and its
    package closure (in `sources`) and writes two outputs: the full platform dill
    and the summary outline.

    Default (no web params) = the VM platform (runtime/vm/BUILD.gn:gen_vm_platform),
    proven byte-identical to GN. The trailing positional arg order — outline,
    platform, outline — is exactly what GN passes (compile_platform.gni:90-91):
    restArguments[2] is the host platform read for the deps file (Bazel drops the
    undeclared .d, so it only needs to be readable), restArguments[4] is the
    outline output, and the platform output sits between them. sdk_hash must match
    the dartvm / gen_snapshot that consume the dill, or the VM rejects it at load.

    Web/Wasm variants (ddc_platform, compile_dart2js{,_server}_platform,
    compile_dart2wasm_*_platform) differ from the VM call in four ways, expressed
    additively so the VM caller is untouched:
      * `platform_args` — the leading args (e.g. `["--target=dartdevc", "dart:core"]`)
        that REPLACE the VM's `dart:core -Ddart.vm.* -Ddart.isVM=true` block.
      * `single_root_base` — the org-dartlang-sdk root; VM uses the execroot ($$(pwd),
        spec `…:///sdk/lib/…`), web uses `sdk` (spec `…:///lib/…`). Both resolve to
        sdk/lib; the embedded URIs are the canonical scheme, so output stays
        byte-identical to GN regardless of the on-disk base (same as vm_platform).
      * `deps_outline` — GN's add_implicit_vm_platform_dependency: web variants read
        the VM outline (//runtime/vm:vm_platform_outline.dill) for their depfile and
        dep on it; the VM self-build instead uses its own outline (None → default).
      * `platform_out` / `outline` — GN names the outputs after the *tool*
        (dart2js_platform.dill / dart2js_outline.dill), not the target, so both
        output filenames are overridable.
    """
    platform_out = platform_out or (name + ".dill")
    outline_out = outline or (name + "_outline.dill")
    base = single_root_base or "$$(pwd)"

    # _PACKAGE_CONFIG_FILE materializes .dart_tool/package_config.json for the
    # --packages flag. Required because `sources` is a per-package dart_library
    # closure (.dart only).
    srcs = [_SDK_FILES, sources, sdk_sources, _PACKAGE_CONFIG_FILE]

    if platform_args == None:
        # VM platform: dart:core + the VM defines (+ optional --exclude-source).
        mid = (
            "dart:core -Ddart.vm.product={product} -Ddart.vm.asan=false " +
            "-Ddart.vm.msan=false -Ddart.vm.tsan=false -Ddart.isVM=true {exclude}"
        ).format(
            product = "true" if product else "false",
            exclude = "--exclude-source " if exclude_source else "",
        )
    else:
        # Web/Wasm platform: the caller's --target=… args verbatim.
        mid = " ".join(platform_args) + " "

    if deps_outline == None:
        # VM self-build: the deps-read outline positional is its own outline.
        deps_pos = "$(location {})".format(outline_out)
    else:
        # Web variants read the VM outline (GN add_implicit_vm_platform_dependency).
        srcs = srcs + [deps_outline]
        deps_pos = "$(location {})".format(deps_outline)

    native.genrule(
        name = name,
        srcs = srcs,
        outs = [platform_out, outline_out],
        cmd = (
            "{dart} -Dsdk_hash={hash} --packages={pkg} {tool} " +
            "{mid}" +
            "--single-root-scheme=org-dartlang-sdk --single-root-base={base} " +
            "{spec} {deps_pos} $(location {platform}) $(location {outline})"
        ).format(
            dart = _PREBUILT_DART,
            hash = sdk_hash,
            pkg = _PACKAGE_CONFIG,
            tool = _COMPILE_PLATFORM,
            mid = mid,
            base = base,
            spec = libraries_spec,
            deps_pos = deps_pos,
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
        srcs = [main, gen_kernel_dill, platform_dill, _SDK_FILES, sources, _PACKAGE_CONFIG_FILE],
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
        training_srcs = None,
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

    training_srcs: extra inputs the *training run* reads but that aren't in the
    `sources` closure — GN's training_inputs/training_deps. GN's training runs
    read these non-hermetically from the checkout (e.g. analysis_server reads
    sdk/lib via --sdk); under the Bazel sandbox they must be declared, or the
    training run can't open them and the genrule fails.
    """
    dill = name + ".dart.dill"
    gen_kernel_args = gen_kernel_args or []
    vm_args = list(vm_args or [])
    training_srcs = training_srcs or []

    # GN injects --coverage=false (+ --ignore-unrecognized-flags, since
    # --coverage is unrecognized in product mode) unless --coverage is already
    # set. Mirror that here (application_snapshot.gni:75-90).
    if not [a for a in vm_args if a.startswith("--coverage")]:
        vm_args = vm_args + ["--coverage=false", "--ignore-unrecognized-flags"]

    # Stage 1: kernel compile (mirrors the *_dill prebuilt_dart_action). Same
    # shape as dart_aot_snapshot's stage 1 but with the app-jit gen_kernel flags.
    native.genrule(
        name = name + "_dill",
        srcs = [main, gen_kernel_dill, platform_dill, _SDK_FILES, sources, _PACKAGE_CONFIG_FILE],
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
    # `main` is included so a training run that re-reads the entry source (e.g.
    # DDC compiling its own bin/dartdevc.dart) finds it: the entry lives in bin/,
    # outside the package's lib/ closure, so a per-package `sources` no longer
    # materializes it the way the opaque blob did. Dedupe — some tools already
    # list main in training_srcs (e.g. frontend_server/kernel-service pass it via
    # $(location)), and genrule srcs rejects a duplicated label.
    training_stage_srcs = [dill, _SDK_FILES, sources, _PACKAGE_CONFIG_FILE] + training_srcs
    if main not in training_stage_srcs:
        training_stage_srcs = training_stage_srcs + [main]
    native.genrule(
        name = name,
        srcs = training_stage_srcs,
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
