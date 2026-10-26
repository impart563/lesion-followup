"""Portable paths for shareable software acceptance records."""
from pathlib import Path
import os
import re
import tempfile


def record_argument(value, checkout, temporary=None):
    path = Path(value)
    if not path.is_absolute():
        return value
    path = path.resolve()
    for base, label in ((Path(checkout).resolve(), None),
                        (Path(temporary or tempfile.gettempdir()).resolve(), '<temporary>')):
        try:
            relative = path.relative_to(base).as_posix()
        except ValueError:
            continue
        return relative if label is None else label + '/' + relative
    return '<external>/' + path.name


def public_record(value, checkout, aliases=()):
    """Remove machine-specific prefixes from nested metadata and captured output."""
    roots = [(Path(checkout), '<checkout>'),
             (Path(tempfile.gettempdir()), '<temporary>'),
             (Path.home(), '<home>')]
    roots.extend((Path(path), label) for path, label in aliases)
    replacements = {}
    for path, label in roots:
        # Windows tools can print either an 8.3 spelling or its expanded path.
        for variant in (path, path.resolve()):
            for prefix in (str(variant), variant.as_posix()):
                replacements.setdefault(prefix, label)
    prefixes = sorted(replacements, key=len, reverse=True)
    def clean(item):
        if isinstance(item, str):
            for prefix in prefixes:
                if os.name == 'nt':
                    item = re.sub(re.escape(prefix), lambda _: replacements[prefix], item, flags=re.I)
                else:
                    item = item.replace(prefix, replacements[prefix])
            return item
        if isinstance(item, dict):
            return {key: clean(content) for key, content in item.items()}
        if isinstance(item, list):
            return [clean(content) for content in item]
        return item
    return clean(value)


def verify_record_paths():
    with tempfile.TemporaryDirectory(prefix='record-path-fixture ') as directory:
        base = Path(directory)
        checkout = base / 'checkout'
        source = checkout / 'examples' / 'case' / '..' / 'study.json'
        assert record_argument(str(source), checkout, base) == 'examples/study.json'
        assert record_argument(str(base / 'temporary input.csv'), checkout, base) == '<temporary>/temporary input.csv'
        assert record_argument('examples/study.json', checkout) == 'examples/study.json'
        assert record_argument('--format', checkout) == '--format'
        raw = {'commands': [{'command': str(source), 'exit_code': 0}],
               'canonical': str(source.resolve()),
               'tree': 'consumer (local ' + str(base / 'consumer') + ')',
               'toolchain': Path.home().as_posix() + '/tools/moon',
               'url': 'https://mooncakes.io/docs/impart563/lesion-followup@0.2.0'}
        clean = public_record(raw, checkout, aliases=[(base / 'consumer', '<registry-consumer>')])
        assert clean['commands'][0]['command'].startswith('<checkout>')
        assert clean['canonical'].startswith('<checkout>')
        assert clean['commands'][0]['exit_code'] == 0
        assert clean['tree'] == 'consumer (local <registry-consumer>)'
        assert clean['toolchain'] == '<home>/tools/moon'
        assert clean['url'] == raw['url'] and raw['tree'] != clean['tree']
        assert str(base) not in str(clean) and str(checkout) not in str(clean)
