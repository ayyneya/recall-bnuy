#!/usr/bin/env python3
"""Derive a Pawpad engine from Recall's published one, replacing only what Pawpad rebuilt.

Recall's derive_runtime.py signs with Recall's Developer ID and expects its release chain.
Pawpad keeps the published engine (Recall.app/Contents/Resources/runtime.tar.gz) and swaps in:
- Wine modules rebuilt with Pawpad's patches (scripts/build_portable_runtime.py, PAWPAD_PATCHES),
  named with --wine, taken from WORK/install/usr/local/lib/wine;
- the whole DXMT build (scripts/build_portable_dxmt.py, WORK/dxmt-install), so its modules
  always come from one build of one source.
Replaced Mach-O files are signed ad hoc with the hardened runtime: the engine's loader has
library validation disabled, as Recall ships it. Every other file stays byte-identical, and the
manifest records what was replaced and from which build.

  derive_pawpad_runtime.py --workspace ~/recall/pawpad-lab/build/phase-2 --version pawpad-20261024.1 \
      --wine x86_64-windows/ntoskrnl.exe,x86_64-windows/rsaenh.dll
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile

BASE_ARCHIVE = Path('/Applications/Recall.app/Contents/Resources/runtime.tar.gz')


def sha(p):
    with p.open('rb') as f: return hashlib.file_digest(f, 'sha256').hexdigest()


def macho(p):
    with p.open('rb') as f: magic = f.read(4)
    return magic in (b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xfe\xed\xfa\xcf')


def derive(work, version, wine_modules, base_archive):
    out = work / 'pawpad-artifacts'
    dest = out / version
    if dest.exists(): raise SystemExit(f'{dest} exists; use a new version')
    out.mkdir(exist_ok=True)
    with tarfile.open(base_archive) as t: t.extractall(dest, filter='tar')
    manifest = json.loads((dest / 'runtime.json').read_text())
    base_version = manifest['version']
    replaced = {}

    def replace(source, rel):
        target = dest / rel
        if rel not in manifest['files']: raise SystemExit(f'{rel} is not in the base engine')
        if target.is_symlink() or not target.is_file(): raise SystemExit(f'{rel} is not a file in the base engine')
        before = manifest['files'][rel]['sha256']
        shutil.copyfile(source, target)
        if macho(target):
            subprocess.run(['codesign', '--force', '--options', 'runtime', '--sign', '-', str(target)], check=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run(['codesign', '--verify', '--strict', str(target)], check=True)
        replaced[rel] = {'base_sha256': before, 'sha256': sha(target), 'source': str(source.relative_to(work))}

    wine = work / 'install/usr/local/lib/wine'
    for name in wine_modules:
        replace(wine / name, 'lib/wine/' + name)
    dxmt = work / 'dxmt-install'
    for p in sorted(dxmt.rglob('*')):
        if p.is_file() and p.suffix in ('.dll', '.so'):
            replace(p, 'lib/wine/' + str(p.relative_to(dxmt)))
    if not any(k.endswith('d3d11.dll') for k in replaced): raise SystemExit('No DXMT build in the workspace')

    for rel in replaced:
        manifest['files'][rel] = {'sha256': replaced[rel]['sha256'], 'bytes': (dest / rel).stat().st_size}
    manifest['version'] = version
    manifest['pawpad'] = {'derived_from': base_version, 'base_archive_sha256': sha(base_archive), 'replaced': replaced,
                          'wine_build_proof': json.loads((work / 'wine-build-proof.json').read_text()).get('pawpad_patches'),
                          'dxmt_build_proof': json.loads((work / 'dxmt-build-proof.json').read_text())}
    manifest['status'] = 'pawpad development engine; ad-hoc signed replacements'
    (dest / 'runtime.json').write_text(json.dumps(manifest, indent=2) + '\n')
    archive = out / (version + '.tar.gz')
    with tarfile.open(archive, 'w:gz', compresslevel=3) as tar:
        for p in sorted(dest.rglob('*')): tar.add(p, arcname=str(p.relative_to(dest)), recursive=False)
    shutil.rmtree(dest)
    print(json.dumps({'version': version, 'archive': str(archive), 'sha256': sha(archive),
                      'replaced': sorted(replaced)}, indent=2))


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--workspace', type=Path, required=True)
    p.add_argument('--version', required=True)
    p.add_argument('--wine', default='', help='comma-separated paths under lib/wine to take from the Wine build')
    p.add_argument('--base-archive', type=Path, default=BASE_ARCHIVE)
    a = p.parse_args()
    derive(a.workspace.resolve(), a.version, [m for m in a.wine.split(',') if m], a.base_archive)
