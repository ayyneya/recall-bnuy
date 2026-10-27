#!/usr/bin/env python3
"""Build Pawpad.app with command-line tools (no Xcode project), as build_native_app.py builds Recall.

Pawpad bundles the engine archive pawpad/Resources/release.json pins (for now Recall's
published engine, taken from Recall.app/Contents/Resources/runtime.tar.gz) and its own worker
and app. No account, game, cache or installed environment is copied.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tarfile
from build_portable_setup import HEADERS, MINIMUM_MACOS
from candidate_contract import verify_generated

ROOT=Path(__file__).resolve().parents[1]
PAWPAD=ROOT/'pawpad'
APP_NAME='Pawpad'
APP_BUILD='1'
BUNDLE_ID='dev.neya.pawpad'
MICROPHONE_USAGE='Voice chat in Aniimo uses your microphone.'
COPYRIGHT='Based on Recall by Joshua Asher Nelson. Not affiliated with or endorsed by Pawprint Studio, FunPlus or Apple.'
ENTITLEMENTS={'com.apple.security.device.audio-input':True}
def run(*args):subprocess.run([str(a) for a in args],check=True)
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def build_worker(output,headers):
    """The setup worker, with the same strict flags as Recall's (build_portable_setup.py)."""
    verify_generated()
    for name,expected in HEADERS.items():
        if not (headers/name).is_file() or sha(headers/name)!=expected:
            raise ValueError(f'{headers/name} is missing or differs from libarchive 3.7.7. Fetch it with build_portable_setup.py (it pins its SHA-256).')
    run('/usr/bin/clang','-O2','-fobjc-arc','-Wall','-Wextra','-Werror','-Wno-deprecated-declarations','-ffile-prefix-map='+str(ROOT)+'=/pawpad-source',
        '-mmacosx-version-min='+MINIMUM_MACOS,'-I',headers,'-I',ROOT/'scripts','-I',PAWPAD/'Worker',PAWPAD/'Worker/pawpad_setup.m',
        '-framework','Foundation','-framework','AppKit','-framework','CoreAudio','-framework','IOKit','-larchive','-o',output)
def build(output,runtime_archive,headers,identity=None):
    release=json.loads((PAWPAD/'Resources/release.json').read_text())
    if not runtime_archive.is_file():
        raise ValueError(f"No engine archive at {runtime_archive}. Pass Recall's with --runtime-archive /Applications/Recall.app/Contents/Resources/runtime.tar.gz "
                         f"(engine {release['runtimeVersion']}).")
    if (found:=sha(runtime_archive))!=release['runtimeSHA256']:
        raise ValueError(f"{runtime_archive} has SHA-256 {found}, but pawpad/Resources/release.json pins {release['runtimeSHA256']} (engine {release['runtimeVersion']}).")
    if output.exists():raise ValueError(f'{output} already exists. Choose a new --output: earlier builds are kept, never overwritten.')
    helpers=output/'Contents/Helpers';resources=output/'Contents/Resources';macos=output/'Contents/MacOS'
    for directory in (helpers,resources,macos):directory.mkdir(parents=True)
    build_worker(helpers/'pawpad-setup',headers)
    run('/usr/bin/swiftc','-file-prefix-map',str(ROOT)+'=/pawpad-source','-O','-target','arm64-apple-macos'+MINIMUM_MACOS,'-parse-as-library',*sorted((PAWPAD/'App').glob('*.swift')),'-o',macos/APP_NAME)
    # The flight recorder's report tool (pawpad/Perf), beside the worker that runs it.
    run('/usr/bin/swiftc','-file-prefix-map',str(ROOT)+'=/pawpad-source','-O','-target','arm64-apple-macos'+MINIMUM_MACOS,*sorted((PAWPAD/'Perf').glob('*.swift')),'-o',helpers/'pawpad-perf')
    # An Intel app: opening it makes macOS offer to install Rosetta.
    rosetta=helpers/'Rosetta Check.app/Contents';(rosetta/'MacOS').mkdir(parents=True)
    source=output.parent/'rosetta-check.c';source.write_text('int main(void) { return 0; }\n')
    run('/usr/bin/clang','-arch','x86_64','-mmacosx-version-min='+MINIMUM_MACOS,source,'-o',rosetta/'MacOS/RosettaCheck');source.unlink()
    (rosetta/'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':BUNDLE_ID+'.rosetta-check','CFBundleExecutable':'RosettaCheck','CFBundleName':'Rosetta Check','CFBundlePackageType':'APPL','LSUIElement':True,'LSMinimumSystemVersion':MINIMUM_MACOS}))
    run('/bin/cp','-c',runtime_archive,resources/release['runtimeArchive'])
    (resources/'release.json').write_text(json.dumps(release,indent=2)+'\n')
    # The engine's own license files, from the verified archive; then Pawpad's and Recall's.
    with tarfile.open(runtime_archive) as archive:
        for member in archive.getmembers():
            if member.isfile() and member.name.startswith('licenses/') and '..' not in Path(member.name).parts:
                target=resources/'Licenses'/Path(member.name).relative_to('licenses')
                target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(archive.extractfile(member).read())
    (resources/'Licenses').mkdir(exist_ok=True)
    shutil.copy2(ROOT/'licenses/PROJECT-APACHE-2.0',resources/'Licenses/PAWPAD-AND-RECALL-APACHE-2.0.txt')
    shutil.copy2(PAWPAD/'NOTICE',resources/'Licenses/NOTICE.txt')
    iconset=output.parent/(output.stem+'-AppIcon.iconset');artwork=output.parent/(output.stem+'-AppIcon.png')
    run('/usr/bin/swift',PAWPAD/'Resources/make_icon.swift',artwork)
    run('/usr/bin/swift',ROOT/'scripts/app_icon.swift',artwork,iconset)
    run('/usr/bin/iconutil','-c','icns',iconset,'-o',resources/'AppIcon.icns')
    shutil.rmtree(iconset);artwork.unlink()
    (output/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':BUNDLE_ID,'CFBundleExecutable':APP_NAME,'CFBundleName':APP_NAME,'CFBundleDisplayName':APP_NAME,
        'CFBundlePackageType':'APPL','CFBundleShortVersionString':release['appVersion'],'CFBundleVersion':APP_BUILD,'CFBundleIconFile':'AppIcon',
        'LSMinimumSystemVersion':MINIMUM_MACOS,'NSHighResolutionCapable':True,'LSMultipleInstancesProhibited':True,'NSPrincipalClass':'NSApplication',
        'NSMicrophoneUsageDescription':MICROPHONE_USAGE,'NSHumanReadableCopyright':COPYRIGHT,'CFBundleDevelopmentRegion':'en','LSApplicationCategoryType':'public.app-category.games'}))
    # Signed with a Developer ID when one is given; otherwise ad hoc, for this Mac only.
    sign=identity or '-'
    extra=['--options','runtime','--timestamp'] if identity else []
    for binary in (helpers/'pawpad-setup',helpers/'pawpad-perf',rosetta.parent):run('/usr/bin/codesign','--force',*extra,'--sign',sign,binary)
    entitlements=output.parent/(output.stem+'.entitlements');entitlements.write_bytes(plistlib.dumps(ENTITLEMENTS))
    run('/usr/bin/codesign','--force',*extra,'--entitlements',entitlements,'--sign',sign,output);entitlements.unlink()
    run('/usr/bin/codesign','--verify','--deep','--strict',output)
    proof={'app_version':release['appVersion'],'app_build':APP_BUILD,'runtime_sha256':sha(resources/release['runtimeArchive']),'signed':bool(identity),
           'source_files':{str(p.relative_to(ROOT)):sha(p) for p in sorted(PAWPAD.rglob('*')) if p.is_file()},
           'files':{str(p.relative_to(output)):sha(p) for p in output.rglob('*') if p.is_file()}}
    output.with_suffix('.build.json').write_text(json.dumps(proof,indent=2)+'\n')
    print(output)
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output',type=Path,default=ROOT/'runtime/build/Pawpad.app')
    p.add_argument('--runtime-archive',type=Path,default=Path('/Applications/Recall.app/Contents/Resources/runtime.tar.gz'))
    p.add_argument('--headers',type=Path,default=ROOT/'runtime/toolchains/libarchive-3.7.7')
    p.add_argument('--identity',help='Developer ID Application identity; ad hoc when left out')
    a=p.parse_args()
    try:build(a.output.resolve(),a.runtime_archive.resolve(),a.headers.resolve(),a.identity)
    except ValueError as error:raise SystemExit(f'build_pawpad.py: {error}')
