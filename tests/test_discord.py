"""Every Discord card check in one command: the four Swift suites (app/ARCHITECTURE.md lists their builds) and the
hooks in Recall's files (test_discord_hooks.py). Each suite is built into a scratch folder and run from the repository
root; skipped without swiftc.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT/'app/Sources'
SWIFTC = ['swiftc', '-O', '-target', 'arm64-apple-macos26.5', '-parse-as-library']
ENGINE = ['Brand', 'Localization', 'DiscordPresence', 'CareerProfile', 'CareerHistory', 'DiscordCardTemplate', 'DiscordCardCatalog']
EVERYTHING = sorted(str(path) for path in SOURCES.rglob('*.swift') if path.name != 'Main.swift')
SUITES = {
    'CareerProfileTests': ENGINE,
    'DiscordCardTests': ENGINE+['DiscordCardCode'],
    'DiscordPresenceTests': ENGINE,
    'DiscordMotionTests': None,
}

from test_discord_hooks import DiscordHooks  # noqa: E402,F401  (run with these)


@unittest.skipUnless(shutil.which('swiftc'), 'needs swiftc')
class DiscordSuites(unittest.TestCase):
    def suite(self, name):
        # Recall's own files (Brand, Localization) beside the feature's in app/Sources/Discord.
        sources = EVERYTHING if SUITES[name] is None else [str(next(SOURCES.rglob(f'{file}.swift'))) for file in SUITES[name]]
        with tempfile.TemporaryDirectory() as scratch:
            binary = Path(scratch)/name
            built = subprocess.run(SWIFTC+sources+[str(ROOT/'tests'/f'{name}.swift'), '-o', str(binary)], capture_output=True, text=True)
            self.assertEqual(built.returncode, 0, built.stderr[-4000:])
            ran = subprocess.run([str(binary)], cwd=ROOT, capture_output=True, text=True, timeout=600)
            self.assertEqual(ran.returncode, 0, (ran.stdout+ran.stderr)[-4000:])

    def test_career_profile(self): self.suite('CareerProfileTests')
    def test_card(self): self.suite('DiscordCardTests')
    def test_presence(self): self.suite('DiscordPresenceTests')
    def test_motion(self): self.suite('DiscordMotionTests')


if __name__ == '__main__':
    unittest.main()
