# Running the Bazel-built dartvm (branch: kevmoo/bazel)

Scope: how to build, run, and refresh `bazel-bin/runtime/bin/dartvm` so it
executes raw `.dart` source via the in-VM Kernel isolate. Branch-local —
not intended for upstream.

## TL;DR

```bash
cd /var/home/kevmoo/github/dart/sdk
bazel-bin/runtime/bin/dartvm path/to/program.dart
```

If you just want to run an arbitrary Dart program with the Bazel binary,
that's it. The sections below are about the **first-time setup** and the
**after-you-edit-SDK-source refresh** loop.

## Why this doc exists

The Bazel build produces a self-contained `dartvm` binary with no external
runtime files: ICU data, VM/core/platform snapshots, and the
kernel-service `.dill` are all `.incbin`-embedded into the ELF. Three of
those embedded blobs (`core_snapshot_*`, `vm_platform*.dill`,
`kernel_service.dill`) are still **sourced from `out/ReleaseX64/`**, not
produced by the Bazel build itself — so the GN/ninja build has to be kept
in a state that produces compatible blobs.

"Compatible" specifically means `sdk_hash="0000000000"`, baked into the
blob header. The Bazel `dartvm` has that hash baked in (the version
genrule runs `make_version.py --no-git-hash --no-sdk-hash`
unconditionally); if a `.dill` carries any other hash the VM rejects it
as a snapshot version mismatch (surfaces as `ApiError` from
`Dart_CreateIsolateGroupFromKernel`, not as anything obviously
hash-related).

## One-time setup

### 1. `out/ReleaseX64/args.gn` must disable version stamping

```gn
verify_sdk_hash = false
dart_version_git_info = false
```

These two together cause `tools/make_version.py` to bake
`sdk_hash="0000000000"` into every `.dill` produced by this `out/` dir,
matching what `bazel build //runtime/bin:dartvm` bakes into the binary.

**Trade-off:** in this `out/` dir, snapshot version verification is now
off across the board. If you also want to use this `out/` for a pure-GN
build, you lose that check. Cleanest pattern is a separate `out/` dir
for Bazel-interop builds; for now we share.

### 2. DEPS pins must be honored for `third_party/pkg/native` and `tools/sdks/dart-sdk`

`gclient sync` should do this, but on this machine it silently skips
many subrepos (most `third_party/pkg/*` and the dart-sdk CIPD package
never appear in the verbose log; reason unclear, possibly tied to
`managed: False` in `~/github/dart/.gclient`).

After `gclient sync`, verify and manually fix as needed:

```bash
# pkg/native must match DEPS pin (read native_rev from DEPS)
NATIVE_REV=$(grep '"native_rev"' DEPS | head -1 | grep -oE '"[a-f0-9]{40}"' | tr -d '"')
git -C third_party/pkg/native fetch --quiet
git -C third_party/pkg/native checkout "$NATIVE_REV"

# tools/sdks/dart-sdk must match DEPS pin (read sdk_tag from DEPS)
SDK_TAG=$(grep '"sdk_tag"' DEPS | head -1 | grep -oE '"version:[^"]+"' | tr -d '"')
echo "dart/dart-sdk/linux-amd64 $SDK_TAG" | \
  cipd ensure -ensure-file - -root tools/sdks/dart-sdk
```

If `pkg/native` is at the wrong rev, the SDK source's references to
`DefinitionWithInstances` won't resolve and `kernel_service.dill`
regeneration fails with a CFE error in `pkg/vm/lib/transformations/record_use/`.

If `tools/sdks/dart-sdk` is too old (≤ 3.11), it can't parse current SDK
source and ninja's `gen_kernel.dart` / `compile_platform.dart` steps fail.

### 3. ICU subrepo edits must not be wiped

`third_party/icu/source/{common,i18n,stubdata}/BUILD.bazel` carry M5
hand-appended `exports_files([...])` blocks (look for
`# Dart Bazel M5:`). `gclient sync` will refuse to clobber them because
they show as uncommitted changes — that's the *intended* protection, not
a bug. Don't `git -C third_party/icu reset --hard` or you'll lose them
silently and link errors of the form `no such target
'//third_party/icu/source/common:appendable.cpp'` will return.

If they ever do get wiped, restoration recipe is in the
`project_m3_handoff` memory file.

## After editing SDK source — refresh the embedded blobs

The embedded `kernel_service.dill` and `vm_platform*.dill` are snapshots
of the SDK as of the last ninja build. If you change `runtime/lib/`,
`sdk/lib/`, or any source the kernel service or platform dill depends
on, you need to regen:

```bash
ninja -C out/ReleaseX64 \
  gen/kernel_service.dill vm_platform.dill vm_platform_stripped.dill
bazel build //runtime/bin:dartvm
```

Bazel's `.incbin` genrules source these files directly from
`out/ReleaseX64/`, so the next `bazel build //runtime/bin:dartvm`
automatically re-links with the fresh content.

## Smoke test

```bash
cat > /tmp/hello.dart <<'EOF'
void main() {
  print('Hello from Bazel-built dartvm!');
  print(2 + 2);
  print([1, 2, 3].map((x) => x * x).toList());
}
EOF
bazel-bin/runtime/bin/dartvm /tmp/hello.dart
# Hello from Bazel-built dartvm!
# 4
# [1, 4, 9]
```

A stronger sanity test that exercises async/await, exceptions, generic
maps, list cascades, and string interpolation lives at `/tmp/sanity.dart`
in the working tree from the M5 closeout session — recreate it from
`project_m3_handoff` memory if needed.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `ApiError` from `Dart_CreateIsolateGroupFromKernel` | sdk_hash mismatch — check args.gn flags and re-ninja the dills |
| `Error while initializing Kernel isolate` | embedded `kernel_service.dill` doesn't match current source — re-ninja |
| `no such target '//third_party/icu/source/common:...cpp'` | ICU subrepo `exports_files` blocks wiped — restore from memory |
| ninja error referencing `DefinitionWithInstances` | `third_party/pkg/native` not at DEPS pin — see setup §2 |
| ninja error parsing wildcard `(_, b, _)` patterns | `tools/sdks/dart-sdk` is too old — see setup §2 |
| `bazel build` succeeds but says "up-to-date" with stale dills | `out/ReleaseX64/**` file mtime didn't change — `touch` the dill, or check that ninja actually wrote a new file |
