#!/usr/bin/env python3
"""Reconstruct and build the accepted DXMT patch against freshly built Wine tools."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import shutil

import sign_pe

ROOT=Path(__file__).resolve().parents[1]
BASE='c5dc3a0dfe9108e667da43de871324bd298c9c02'
HEADERS='9df86f2341616ef1888ae59919feaa6d4fad693d'
# NVIDIA's NVAPI headers (MIT), a submodule of the base, for DXMT's NVAPI stand-in.
NVAPI='d08488fcc82eef313b0464db37d2955709691e94'
# MetalFX upscaling (1.3): DXMT's DLSS stand-in is signed with Recall's own certificate.
SIGNING=ROOT/'runtime/signing/recall-nvngx'


def run(*args,**kwargs):return subprocess.run([str(a) for a in args],check=True,**kwargs)


# What build() itself puts into the source tree; it never counts as someone's work there.
BUILD_FILES={'portable_metal.py'}


def git_output(source,*args):return subprocess.check_output(['git','-C',str(source),*args])


def tree_state(source):
    """The tree's commit, tracked changes and untracked files (BUILD_FILES aside), hashed."""
    state=hashlib.sha256(git_output(source,'rev-parse','HEAD'))
    state.update(git_output(source,'diff','--binary','HEAD'))
    for name in sorted(n.decode() for n in git_output(source,'ls-files','--others','--exclude-standard','-z').split(b'\0') if n):
        if name not in BUILD_FILES:state.update(name.encode()+b'\0'+(source/name).read_bytes())
    return state.hexdigest()


def tree_clean(source):
    """No tracked changes and no untracked files (BUILD_FILES aside): nothing a checkout could lose."""
    out=git_output(source,'status','--porcelain','--untracked-files=all','-z').split(b'\0')
    return all(line[3:].decode() in BUILD_FILES for line in out if line)


def patch_identity():
    """BASE, this script and every DXMT patch file: while none changes, a tree that an earlier run
    prepared is what this run would prepare."""
    identity=hashlib.sha256(BASE.encode()+Path(__file__).read_bytes())
    for p in sorted((ROOT/'patches').glob('dxmt-*.patch')):identity.update(p.name.encode()+b'\0'+p.read_bytes())
    return identity.hexdigest()


def prepare_source(work,discard_changes=False):
    """DXMT at its pinned commit with the accepted patches, in WORK/dxmt-source. It is all the app
    build needs (build_native_app.py --workspace WORK): its pipeline sources come from here.

    The tree is also where DXMT work happens, so it is only reset when it holds nothing but what an
    earlier run of this script put there (WORK/dxmt-source.prepared.json): other edits or new files
    stop the build, unless DISCARD_CHANGES. A tree prepared from the same patches is kept as it is,
    which keeps the build incremental."""
    source=work/'dxmt-source';record=work/'dxmt-source.prepared.json'
    fresh=not source.exists()
    if fresh:run('git','clone','--no-checkout','https://github.com/NerRobDog/dxmt',source)
    kept=json.loads(record.read_text()) if record.exists() and not fresh else {}
    state=None if fresh else tree_state(source)
    reuse=state is not None and kept.get('state')==state and kept.get('patches')==patch_identity()
    if not (fresh or reuse or discard_changes or kept.get('state')==state or tree_clean(source)):
        raise ValueError(f'{source} holds changes this script did not make (edits or new files). Export them '
                         'to a patch first, or run again with --discard-dxmt-changes to throw them away.')
    def use(patch):
        if not reuse:run('git','apply',patch,cwd=source)
    # Every preparation starts from the pinned commit with nothing applied: the patches stack, so a
    # tree left patched by an earlier build can't be checked patch by patch (a later patch changes
    # the lines an earlier one is checked against).
    if not reuse:
        run('git','-C',source,'checkout','--force','--detach',BASE)
        run('git','-C',source,'clean','-fdq')
        run('git','-C',source,'submodule','update','--init','--recursive')
    current=subprocess.check_output(['git','-C',str(source/'include/native/directx'),'rev-parse','HEAD'],text=True).strip()
    if current!=HEADERS:raise ValueError('DirectX header identity mismatch')
    current=subprocess.check_output(['git','-C',str(source/'external/nvapi'),'rev-parse','HEAD'],text=True).strip()
    if current!=NVAPI:raise ValueError('NVAPI header identity mismatch')
    patch=ROOT/'patches/dxmt-v1-private.patch'
    if hashlib.sha256(patch.read_bytes()).hexdigest()!='5afcbde9512381c37e975450d08f7fd3cef1e8755739f1f5b4ae8f1563de5199':raise ValueError('Accepted renderer patch changed')
    use(patch)
    # v1.0: the play-tested performance work (DXMT replay branch e873a90) on top.
    performance=ROOT/'patches/dxmt-v1-performance.patch'
    if hashlib.sha256(performance.read_bytes()).hexdigest()!='b119feb670a3e2ffe656159118e99a75abc5b9a8097e77096c512a01b81861f2':raise ValueError('Accepted performance patch changed')
    use(performance)
    portable_patch=ROOT/'patches/dxmt-portable-metal.patch'
    use(portable_patch)
    # 1.3: DLSS on MetalFX. Direct3D 12 entry points and NVIDIA's failure codes in the DLSS
    # stand-in, and a d3d12.dll whose device only answers NVIDIA Streamline's setup questions.
    # MetalFX writes the DLSS output with shader-write usage (the 1.2 compression keeps it from
    # render targets the game never writes as UAVs); jittered motion vectors lose the jitter change
    # (a pass macOS compiles at run time); the chosen mode is the floor of the dynamic range; and the
    # stand-in logs what the game passes. Sharpening after MetalFX (d3d11.metalfxSharpness, Recall's
    # Sharpening setting) is a contrast-adaptive pass, also compiled at run time.
    metalfx=ROOT/'patches/dxmt-metalfx-upscaling.patch'
    if hashlib.sha256(metalfx.read_bytes()).hexdigest()!='87ab3e3a74a1c140653d6d66cda6576049472c8999afab68bccc866e48028b17':raise ValueError('Accepted MetalFX patch changed')
    use(metalfx)
    # 1.4: the shader pack holds every learned pipeline. Its archives are hashed in pieces instead
    # of read whole, have no total size limit, and can be prepared in batches that each add one
    # (DXMT_PIPELINE_CACHE_APPEND); learning goes on until the disk is nearly full.
    shader_pack=ROOT/'patches/dxmt-shader-pack.patch'
    if hashlib.sha256(shader_pack.read_bytes()).hexdigest()!='26b64c19f499e4e7fbccfa9402ab0bdd5a0e383af2d5098aa00c9abcd7182773':raise ValueError('Accepted shader pack patch changed')
    use(shader_pack)
    # Pawpad: a compute pipeline Metal refuses to build has its dispatches skipped. Encoding them
    # without a pipeline divided by zero in Apple's GPU driver and froze Aniimo at 100% loading.
    skip_failed=ROOT/'patches/dxmt-skip-failed-compute.patch'
    if hashlib.sha256(skip_failed.read_bytes()).hexdigest()!='9da53f1e033ba1b503e161cb450da47458c7b5ccc231a989335e9d1427e9cde5':raise ValueError('Accepted failed-pipeline patch changed')
    use(skip_failed)
    # Pawpad: DXMT_RECORD_TRIGGER starts the D3D11 recorder when a file appears, so a recording
    # can begin once the game is in the world without pressing keys in the game.
    record_trigger=ROOT/'patches/dxmt-record-trigger.patch'
    if hashlib.sha256(record_trigger.read_bytes()).hexdigest()!='0d44e2d46fe721370ec8b94f6c473feb49c104562bc747b8d1c1a2737474c895':raise ValueError('Accepted record-trigger patch changed')
    use(record_trigger)
    # Pawpad: fixes from upstream 3Shain/dxmt after the fork's base (aacfbd3), in three groups
    # (pawpad-lab perf-goal/research-dxmt-upstream.md). The shader translator: vector
    # firstbit_shi built invalid IR (d1c926c; Metal refused Aniimo's compute shader 32f49794 with
    # "Failed to materializeAll"), logic flaws (ae91269), call return points (9839e55), queries on
    # null texture descriptors (64ee6f5); AIRCONV_VERSION 124 (the fork's 24 plus these), so the
    # shader cache keeps them apart. The display queries made every Present leak (d815f7f,
    # a741a3f). Copies between texture types were dropped (e40c9d7: a Unity game's 3D colour
    # grading table stayed black) and clears used the full texture size for a mip (f9beaea).
    upstream={}
    for name,digest in (('airconv','5a337b451f4f9e0a114ba32a80652d9cf2bfa52037c94feca4a830573984781c'),
                        ('display-leaks','b0afd37b931fdf53768301f8b3eb8d7f7b56dea69d38904bb1349a0fc701af11'),
                        ('texture-fixes','0d13688b55b02ac81f61b3ff0ad1baa9ffde7ce6751bebbdbdb617a707a15c95')):
        fix=ROOT/f'patches/dxmt-upstream-{name}.patch'
        if hashlib.sha256(fix.read_bytes()).hexdigest()!=digest:raise ValueError(f'Accepted upstream {name} patch changed')
        use(fix);upstream[name]=fix
    pawpad={}
    # Pawpad: say in the log when Metal refuses a texture or buffer allocation (the resource then
    # has no storage: zeros when sampled, a GPU address of 0 for buffers). Logging only.
    refused=ROOT/'patches/dxmt-log-refused-allocations.patch'
    if hashlib.sha256(refused.read_bytes()).hexdigest()!='f791eba1c721b0a501ed545ba6418314a1c94dce54ef9ea861e780492b5b7492':raise ValueError('Accepted refused-allocation patch changed')
    use(refused);pawpad['log-refused-allocations']=refused
    # Pawpad: draws whose render pipeline Metal refused are skipped, as dispatches already are
    # (dxmt-skip-failed-compute); they used to run with the previously bound pipeline.
    render_skip=ROOT/'patches/dxmt-skip-failed-render.patch'
    if hashlib.sha256(render_skip.read_bytes()).hexdigest()!='20053fa0cad13ca5d7f52ad5741e002c8071f60547d1864a7a24466c39913ebc':raise ValueError('Accepted failed-render patch changed')
    use(render_skip);pawpad['skip-failed-render']=render_skip
    # Pawpad: DXMT_DEPTH_RENAME_CAP limits the copies a depth texture gets from full clears in one
    # command buffer (default 32 as before), and the log says when a texture's copies pile up.
    depth_cap=ROOT/'patches/dxmt-depth-rename-cap.patch'
    if hashlib.sha256(depth_cap.read_bytes()).hexdigest()!='b92bd73215ff8ada509bbd8680ff6fb42dca6fa55fb4fe77a5bcb9c2d2ad08c9':raise ValueError('Accepted depth-rename patch changed')
    use(depth_cap);pawpad['depth-rename-cap']=depth_cap
    # Pawpad: per-pass GPU timing for diagnosis, off unless DXMT_PASS_TIMING is set (lab tool).
    pass_timing=ROOT/'patches/dxmt-pass-timing.patch'
    if hashlib.sha256(pass_timing.read_bytes()).hexdigest()!='1182d71734a63209882cae87a9c1b1145b8f9886d7e262b5acc4120039c715a3':raise ValueError('Accepted pass-timing patch changed')
    use(pass_timing);pawpad['pass-timing']=pass_timing
    # Pawpad: 8 MB frame-log segments, so a one-hour session keeps all its frames (2 MB kept ~20 minutes).
    frame_log=ROOT/'patches/dxmt-frame-log-segments.patch'
    if hashlib.sha256(frame_log.read_bytes()).hexdigest()!='20c0d3a3373104f3020fa5b929e194538e0e3a85abdbf223b2d70e61a87c6211':raise ValueError('Accepted frame-log patch changed')
    use(frame_log);pawpad['frame-log-segments']=frame_log
    # Pawpad: typeless 2D render targets start without PixelFormatView (DXMT_DEFER_PIXEL_FORMAT_VIEW=1),
    # which keeps Apple's lossless compression; a view in another format moves the texture first.
    defer_pfv=ROOT/'patches/dxmt-defer-pixel-format-view.patch'
    if hashlib.sha256(defer_pfv.read_bytes()).hexdigest()!='06414ea2d8f54c10a346be1f3ffb7bc3c4934da8d99347a91a68c0080c99e8c8':raise ValueError('Accepted deferred-PixelFormatView patch changed')
    use(defer_pfv);pawpad['defer-pixel-format-view']=defer_pfv
    # Pawpad: fixes from the 30 Oct code review. Views DXMT itself makes in another format (resolves,
    # partial ClearView, MetalFX's motion vectors) move a deferred texture first, other-format views of
    # an allocation without PixelFormatView are made when used, and multisample targets aren't
    # deferred. A refused allocation is never used: a move or depth rename keeps the texture where it
    # is, Map(WRITE_DISCARD) and creation fail with E_OUTOFMEMORY. The record trigger fires once per
    # file, DXMT_PASS_TIMING registers shader tags, and the display query frees every ICC tag.
    review=ROOT/'patches/dxmt-review-fixes.patch'
    if hashlib.sha256(review.read_bytes()).hexdigest()!='82c0b7494c7162d7fd44f7168402aff5e7745670791279c239c8b96d716c8e35':raise ValueError('Accepted review-fixes patch changed')
    use(review);pawpad['review-fixes']=review
    # Pawpad: DXMT_RENAME_UAV_BUFFERS=1 renames GPU-writable buffers on a whole UpdateSubresource
    # instead of copying through a blit encoder (off by default).
    rename_uav=ROOT/'patches/dxmt-rename-uav-buffers.patch'
    if hashlib.sha256(rename_uav.read_bytes()).hexdigest()!='b8205d52f0f3a79f7c1371ee0a17c0e6bae31a85a02d741a6c8385900a79e19a':raise ValueError('Accepted rename-UAV-buffers patch changed')
    use(rename_uav);pawpad['rename-uav-buffers']=rename_uav
    # Pawpad: DXMT_GPU_ERROR_DETAIL=1 logs each encoder's state when a command buffer fails (GPU hangs).
    error_detail=ROOT/'patches/dxmt-gpu-error-detail.patch'
    if hashlib.sha256(error_detail.read_bytes()).hexdigest()!='686834388dd03c0161420787efae596b1f9ae97d31deee45768b8d1930ee400d':raise ValueError('Accepted GPU-error-detail patch changed')
    use(error_detail);pawpad['gpu-error-detail']=error_detail
    if not reuse:record.write_text(json.dumps({'patches':patch_identity(),'state':tree_state(source)},indent=2)+'\n')
    return source,{'patch':patch,'performance':performance,'portable':portable_patch,'metalfx':metalfx,'shader_pack':shader_pack,'skip_failed':skip_failed,'record_trigger':record_trigger,'upstream':upstream,'pawpad':pawpad}


def build(work,tools,jobs,signing=SIGNING,discard_changes=False):
    if not (signing/sign_pe.KEY).is_file():raise ValueError(f'No signing certificate in {signing} (scripts/sign_pe.py create-certificate)')
    source,patches=prepare_source(work,discard_changes);builddir=work/'dxmt-build';install=work/'dxmt-install'
    patch,performance,portable_patch,metalfx,shader_pack=(patches[k] for k in ('patch','performance','portable','metalfx','shader_pack'))
    wrapper=source/'portable_metal.py'
    shutil.copy2(ROOT/'scripts/portable_metal.py',wrapper);wrapper.chmod(0o755)
    env=os.environ.copy();env.pop('DESTDIR',None)
    env['PATH']=':'.join([str(tools/'llvm-mingw-20251216-ucrt-macos-universal/bin'),str(tools/'python/bin'),'/usr/bin','/bin','/usr/sbin','/sbin'])
    meson=tools/'python/bin/meson'
    setup=[meson,'setup',builddir,source,'--cross-file',source/'build-win64.txt','--buildtype=release',
           '--prefix',install,'--strip','-Dnative_llvm_path='+str(tools/'clang+llvm-15.0.7-x86_64-apple-darwin21.0'),
           '-Dwine_build_path='+str(work/'wine-build'),'-Denable_tests=false','-Denable_nvapi=true',
           '-Denable_nvngx=true','-Denable_d3d12=false']
    if (builddir/'meson-private/coredata.dat').exists():setup.append('--reconfigure')
    run(*setup,env=env)
    run(meson,'compile','-C',builddir,'-j',jobs,env=env)
    run(meson,'install','-C',builddir,'--no-rebuild',env=env)
    # NVIDIA's NGX loader loads only a signed core DLL; signing follows winebuild --builtin.
    nvngx=install/'x86_64-windows/nvngx.dll'
    sign_pe.sign(signing,nvngx,nvngx)
    if not sign_pe.check(nvngx,signing):raise ValueError('nvngx.dll signature check failed')
    files={str(p.relative_to(install)):hashlib.sha256(p.read_bytes()).hexdigest()
           for p in install.rglob('*') if p.is_file()}
    (work/'dxmt-build-proof.json').write_text(json.dumps({'base':BASE,'headers':HEADERS,
        'patch_sha256':hashlib.sha256(patch.read_bytes()).hexdigest(),'files':files,
        'performance_patch_sha256':hashlib.sha256(performance.read_bytes()).hexdigest(),
        'metalfx_patch_sha256':hashlib.sha256(metalfx.read_bytes()).hexdigest(),'nvapi':NVAPI,
        'shader_pack_patch_sha256':hashlib.sha256(shader_pack.read_bytes()).hexdigest(),
        'skip_failed_compute_patch_sha256':hashlib.sha256(patches['skip_failed'].read_bytes()).hexdigest(),
        'record_trigger_patch_sha256':hashlib.sha256(patches['record_trigger'].read_bytes()).hexdigest(),
        'upstream_patch_sha256':{k:hashlib.sha256(v.read_bytes()).hexdigest() for k,v in patches['upstream'].items()},
        'pawpad_patch_sha256':{k:hashlib.sha256(v.read_bytes()).hexdigest() for k,v in patches['pawpad'].items()},
        'nvngx_certificate_sha256':hashlib.sha256((signing/sign_pe.LEAF).read_bytes()).hexdigest(),
        'portable_metal_patch_sha256':hashlib.sha256(portable_patch.read_bytes()).hexdigest(),
        'portable_metal_wrapper_sha256':hashlib.sha256(wrapper.read_bytes()).hexdigest(),
        'developer_dir':env.get('DEVELOPER_DIR','xcode-select'),'sdkroot':env.get('SDKROOT','default'),
        'metal_cache':'used' if env.get('DXMT_METAL_CACHE') else 'none',
        'wine_build_tools':'fresh Phase 2 source build'},indent=2)+'\n')


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--workspace',type=Path,required=True)
    p.add_argument('--toolchains',type=Path,default=ROOT/'runtime/toolchains');p.add_argument('--jobs',type=int,choices=range(1,5),default=2)
    p.add_argument('--source-only',action='store_true',help='only fetch and patch DXMT (enough for build_native_app.py --workspace); no toolchains or signing needed')
    p.add_argument('--discard-dxmt-changes',action='store_true',help='reset WORKSPACE/dxmt-source even if it holds edits or new files this script did not make (they are lost)')
    a=p.parse_args()
    if a.source_only:a.workspace.mkdir(parents=True,exist_ok=True);prepare_source(a.workspace.resolve(),a.discard_dxmt_changes)
    else:build(a.workspace.resolve(),a.toolchains.resolve(),a.jobs,discard_changes=a.discard_dxmt_changes)
