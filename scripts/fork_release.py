#!/usr/bin/env python3
"""Build RecallBnuy, unsigned, for a release on the fork: the engine from Recall's official release of the same
version and the app from this checkout. The workflow signs and packages it on another machine.
"""
import argparse
import hashlib
import plistlib
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

NAME = 'RecallBnuy'
UPSTREAM = 'AsherJN/recall'


def run(*args, **options):
    print('+', ' '.join(str(a) for a in args), flush=True)
    return subprocess.run([str(a) for a in args], check=True, **options)


def sha256(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as file:
        for chunk in iter(lambda: file.read(1 << 22), b''):
            digest.update(chunk)
    return digest.hexdigest()


def fetch_engine(tag, target):
    """The engine inside Recall's official DMG, checked against its published SHA-256."""
    with tempfile.TemporaryDirectory() as folder:
        run('gh', 'release', 'download', tag, '--repo', UPSTREAM, '--pattern', 'Recall-*', '--dir', folder)
        image = next(Path(folder).glob('*.dmg'))
        if sha256(image) != image.with_name(image.name+'.sha256').read_text().split()[0]:
            raise SystemExit(f'{image.name} does not match its published SHA-256')
        mount = Path(folder)/'mount'
        mount.mkdir()
        run('hdiutil', 'attach', '-nobrowse', '-readonly', '-noautoopen', '-mountpoint', mount, image)
        try:
            shutil.copy2(mount/'Recall.app/Contents/Resources/runtime.tar.gz', target)
        finally:
            run('hdiutil', 'detach', mount, '-force')


def build(args):
    sys.path.insert(0, str(ROOT/'scripts'))
    from build_native_app import ENTITLEMENTS
    engine = args.runtime_archive or ROOT/'runtime/runtime.tar.gz'
    if not args.runtime_archive:
        engine.parent.mkdir(exist_ok=True)
        fetch_engine(args.tag, engine)
    workspace = ROOT/'runtime/dxmt'
    if not (workspace/'dxmt-source').exists():
        run(sys.executable, ROOT/'scripts/build_portable_dxmt.py', '--workspace', workspace, '--source-only')
    shutil.rmtree(args.output, ignore_errors=True)
    args.output.mkdir(parents=True)
    run(sys.executable, ROOT/'scripts/build_native_app.py', '--output', args.output/'Recall.app', '--workspace', workspace, '--runtime-archive', engine)
    app = args.output/f'{NAME}.app'
    (args.output/'Recall.app').rename(app)
    info_path = app/'Contents/Info.plist'
    info = plistlib.loads(info_path.read_bytes())
    info.update(CFBundleName=NAME, CFBundleDisplayName=NAME, CFBundleShortVersionString=args.version)
    info_path.write_bytes(plistlib.dumps(info))
    (args.output/'app.entitlements').write_bytes(plistlib.dumps(ENTITLEMENTS))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tag', required=True, help="Recall's release, such as v1.6.3")
    parser.add_argument('--version', required=True, help='such as 1.6.3-bnuy')
    parser.add_argument('--runtime-archive', type=Path, help='use this engine instead of fetching it')
    parser.add_argument('--output', type=Path, default=ROOT/'runtime/build/fork')
    build(parser.parse_args())


if __name__ == '__main__':
    main()
