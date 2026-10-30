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


def prepare_source(work):
    """DXMT at its pinned commit with the accepted patches, in WORK/dxmt-source. It is all the app
    build needs (build_native_app.py --workspace WORK): its pipeline sources come from here."""
    source=work/'dxmt-source'
    if not source.exists():run('git','clone','--no-checkout','https://github.com/NerRobDog/dxmt',source)
    # Every build starts from the pinned commit with nothing applied: the patches stack, so a tree
    # left patched by an earlier build can't be checked patch by patch (a later patch changes the
    # lines an earlier one is checked against).
    run('git','-C',source,'checkout','--force','--detach',BASE)
    run('git','-C',source,'clean','-fdq')
    run('git','-C',source,'submodule','update','--init','--recursive')
    current=subprocess.check_output(['git','-C',str(source/'include/native/directx'),'rev-parse','HEAD'],text=True).strip()
    if current!=HEADERS:raise ValueError('DirectX header identity mismatch')
    current=subprocess.check_output(['git','-C',str(source/'external/nvapi'),'rev-parse','HEAD'],text=True).strip()
    if current!=NVAPI:raise ValueError('NVAPI header identity mismatch')
    patch=ROOT/'patches/dxmt-v1-private.patch'
    if hashlib.sha256(patch.read_bytes()).hexdigest()!='5afcbde9512381c37e975450d08f7fd3cef1e8755739f1f5b4ae8f1563de5199':raise ValueError('Accepted renderer patch changed')
    run('git','apply',patch,cwd=source)
    # v1.0: the play-tested performance work (DXMT replay branch e873a90) on top.
    performance=ROOT/'patches/dxmt-v1-performance.patch'
    if hashlib.sha256(performance.read_bytes()).hexdigest()!='b119feb670a3e2ffe656159118e99a75abc5b9a8097e77096c512a01b81861f2':raise ValueError('Accepted performance patch changed')
    run('git','apply',performance,cwd=source)
    portable_patch=ROOT/'patches/dxmt-portable-metal.patch'
    run('git','apply',portable_patch,cwd=source)
    # 1.3: DLSS on MetalFX. Direct3D 12 entry points and NVIDIA's failure codes in the DLSS
    # stand-in, and a d3d12.dll whose device only answers NVIDIA Streamline's setup questions.
    # MetalFX writes the DLSS output with shader-write usage (the 1.2 compression keeps it from
    # render targets the game never writes as UAVs); jittered motion vectors lose the jitter change
    # (a pass macOS compiles at run time); the chosen mode is the floor of the dynamic range; and the
    # stand-in logs what the game passes. Sharpening after MetalFX (d3d11.metalfxSharpness, Recall's
    # Sharpening setting) is a contrast-adaptive pass, also compiled at run time.
    metalfx=ROOT/'patches/dxmt-metalfx-upscaling.patch'
    if hashlib.sha256(metalfx.read_bytes()).hexdigest()!='87ab3e3a74a1c140653d6d66cda6576049472c8999afab68bccc866e48028b17':raise ValueError('Accepted MetalFX patch changed')
    run('git','apply',metalfx,cwd=source)
    # 1.4: the shader pack holds every learned pipeline. Its archives are hashed in pieces instead
    # of read whole, have no total size limit, and can be prepared in batches that each add one
    # (DXMT_PIPELINE_CACHE_APPEND); learning goes on until the disk is nearly full.
    shader_pack=ROOT/'patches/dxmt-shader-pack.patch'
    if hashlib.sha256(shader_pack.read_bytes()).hexdigest()!='26b64c19f499e4e7fbccfa9402ab0bdd5a0e383af2d5098aa00c9abcd7182773':raise ValueError('Accepted shader pack patch changed')
    run('git','apply',shader_pack,cwd=source)
    # Pawpad: a compute pipeline Metal refuses to build has its dispatches skipped. Encoding them
    # without a pipeline divided by zero in Apple's GPU driver and froze Aniimo at 100% loading.
    skip_failed=ROOT/'patches/dxmt-skip-failed-compute.patch'
    if hashlib.sha256(skip_failed.read_bytes()).hexdigest()!='9da53f1e033ba1b503e161cb450da47458c7b5ccc231a989335e9d1427e9cde5':raise ValueError('Accepted failed-pipeline patch changed')
    run('git','apply',skip_failed,cwd=source)
    # Pawpad: DXMT_RECORD_TRIGGER starts the D3D11 recorder when a file appears, so a recording
    # can begin once the game is in the world without pressing keys in the game.
    record_trigger=ROOT/'patches/dxmt-record-trigger.patch'
    if hashlib.sha256(record_trigger.read_bytes()).hexdigest()!='0d44e2d46fe721370ec8b94f6c473feb49c104562bc747b8d1c1a2737474c895':raise ValueError('Accepted record-trigger patch changed')
    run('git','apply',record_trigger,cwd=source)
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
        run('git','apply',fix,cwd=source);upstream[name]=fix
    # Pawpad: say in the log when Metal refuses a texture or buffer allocation (the resource then
    # has no storage: zeros when sampled, a GPU address of 0 for buffers). Logging only.
    refused=ROOT/'patches/dxmt-log-refused-allocations.patch'
    if hashlib.sha256(refused.read_bytes()).hexdigest()!='f791eba1c721b0a501ed545ba6418314a1c94dce54ef9ea861e780492b5b7492':raise ValueError('Accepted refused-allocation patch changed')
    run('git','apply',refused,cwd=source);upstream['log-refused-allocations']=refused
    return source,{'patch':patch,'performance':performance,'portable':portable_patch,'metalfx':metalfx,'shader_pack':shader_pack,'skip_failed':skip_failed,'record_trigger':record_trigger,'upstream':upstream}


def build(work,tools,jobs,signing=SIGNING):
    if not (signing/sign_pe.KEY).is_file():raise ValueError(f'No signing certificate in {signing} (scripts/sign_pe.py create-certificate)')
    source,patches=prepare_source(work);builddir=work/'dxmt-build';install=work/'dxmt-install'
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
    a=p.parse_args()
    if a.source_only:a.workspace.mkdir(parents=True,exist_ok=True);prepare_source(a.workspace.resolve())
    else:build(a.workspace.resolve(),a.toolchains.resolve(),a.jobs)
