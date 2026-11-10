"""The Discord card's translations, kept apart from Recall's (app/Resources/Discord/Localizations/<language>.json) and
merged into each language's table: build_native_app.py writes them into the same Localizable.strings, and
test_localization.py reads them through `merged`. A key in both tables must say the same."""
import json
from pathlib import Path


def discord_table(language):
    """The Discord card's strings for a language file of Recall's (its name: "ko.json")."""
    path = Path(language).parents[1] / 'Discord' / 'Localizations' / Path(language).name
    return json.loads(path.read_text())['Localizable'] if path.exists() else {}


def merge(language, table):
    """Recall's table for a language with the Discord card's strings in it; a key both have must say the same."""
    ours = discord_table(language)
    clashes = sorted(key for key in ours if key in table['Localizable'] and table['Localizable'][key] != ours[key])
    if clashes:
        raise ValueError(f'{Path(language).name}: the Discord card and Recall translate these differently: {clashes}')
    return {**table, 'Localizable': {**table['Localizable'], **ours}}


class Merged(type(Path())):
    """A language file that reads as Recall's table with the Discord card's merged in."""
    def read_text(self, *args, **kwargs):
        return json.dumps(merge(self, json.loads(super().read_text(*args, **kwargs))), ensure_ascii=False)


def merged(languages):
    return [Merged(path) for path in languages]
