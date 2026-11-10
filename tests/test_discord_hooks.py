"""The Discord card's hooks in Recall's own files (app/Sources/Discord/DiscordFeature.swift).

Each hook is one whole line in the function that needs it, so a merge that moves or drops one fails here instead of
leaving the card quietly off. A hook that isn't listed fails too: Recall's files get hooks only. And the game bundle
the worker builds (scripts/game_mode_app.py) is the one the card watches for. Deterministic: reads files only.
"""
from pathlib import Path
import re
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'scripts'))
import game_mode_app  # noqa: E402

SOURCES = ROOT/'app/Sources'
# File, the function (or view body) that holds the hook, and the hook line.
HOOKS = [
    ('AppModel.swift', 'final class AppModel', 'let discord=DiscordFeature()'),
    ('AppModel.swift', 'func startup()', 'discord.start(allowed:'),
    ('AppModel.swift', 'func refresh() async throws', 'discord.statusKnown()'),
    ('AppModel.swift', 'func showSession(', 'discord.sessionSeen(processes)'),
    ('AppModel.swift', 'func uninstallEverything(', 'discord.uninstalled()'),
    ('AppModel.swift', 'func makeReport(', '"discord_presence":discord.report'),
    ('UtilitySheets.swift', 'struct SettingsSheet', '.discordPages(model.discord.studio'),
    ('UtilitySheets.swift', 'struct SettingsSheet', 'DiscordSettingsCard(studio:model.discord.studio)'),
    ('SetupView.swift', 'struct SetupView', 'DiscordHomePanel(studio:model.discord.studio'),
    ('SetupView.swift', 'struct SetupView', '.modifier(DiscordWindowFit())'),
]


def body(text, header):
    """The text from `header` to the end of its braces."""
    start = text.find(header)
    if start < 0:
        return None
    i, depth = text.index('{', start), 0
    for j in range(i, len(text)):
        depth += {'{': 1, '}': -1}.get(text[j], 0)
        if depth == 0:
            return text[start:j+1]
    return None


class DiscordHooks(unittest.TestCase):
    def test_each_hook_is_in_its_function(self):
        for file, header, hook in HOOKS:
            with self.subTest(hook=hook):
                text = body((SOURCES/file).read_text(), header)
                self.assertIsNotNone(text, f'{file}: {header} is gone')
                lines = [line for line in text.splitlines() if hook in line]
                self.assertEqual(len(lines), 1, f'{file}: {hook} should be in {header} once')

    def test_no_hook_beyond_the_list(self):
        listed = {hook for _, _, hook in HOOKS}
        for file in sorted({file for file, _, _ in HOOKS} | {'Main.swift', 'LauncherStyle.swift', 'Localization.swift', 'Brand.swift'}):
            for n, line in enumerate((SOURCES/file).read_text().splitlines(), 1):
                if re.search(r'\bdiscord\.(?!com\b|gg\b)|Discord(?:Feature|HomePanel|SettingsCard|WindowFit)\b|\.discordPages\(', line) and not line.lstrip().startswith('//'):
                    with self.subTest(at=f'{file}:{n}'):
                        self.assertTrue(any(hook in line for hook in listed), f'{file}:{n} is a Discord hook not in HOOKS: {line.strip()}')

    def test_the_card_watches_the_game_bundle_the_worker_builds(self):
        swift = (SOURCES/'Discord/DiscordFeature.swift').read_text()
        self.assertIn(f'gameBundleID="{game_mode_app.IDENTIFIER}"', swift)
        self.assertIn(f'lastPathComponent == "{Path(game_mode_app.EXECUTABLE).name}"', swift)


if __name__ == '__main__':
    unittest.main()
