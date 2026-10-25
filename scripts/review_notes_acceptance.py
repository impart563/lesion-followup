"""Manual review metadata checks against native preflight, using synthetic inputs."""
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


class SafeNotes(HTMLParser):
    def __init__(self):
        super().__init__()
        self.text = []
        self.csp = False

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if tag in ('script', 'iframe', 'object', 'form', 'img'):
            raise AssertionError('active content in exported review notes')
        if any(k.startswith('on') or k in ('src', 'href') for k in values):
            raise AssertionError('external or executable attribute in review notes')
        if tag == 'meta' and values.get('http-equiv') == 'Content-Security-Policy':
            self.csp = "default-src 'none'" in values.get('content', '')

    def handle_data(self, text):
        self.text.append(text)


def verify_review_notes(cli, environment, passed):
    native = []
    for name, path in [('multi', 'examples/followup.csv'), ('missing', 'examples/review-cases/missing.csv'),
                       ('technique', 'examples/review-cases/technique.csv'), ('revised', 'examples/followup.revised.csv')]:
        sources = {'study_json': (ROOT / 'examples/study.json').read_bytes().decode('utf-8'),
                   'followup_csv': (ROOT / path).read_bytes().decode('utf-8')}
        native.append({'name': name, 'sources': sources,
                       'preflight': json.loads(cli('--study', 'examples/study.json', '--input', path, '--check-input', '--format', 'json').stdout)})
    multiple = 'visit_id,date,technique_id,lesion_id,state,diameter_mm,note\nv1,2026-01-02,changed,N1,too_small,,\n'
    with tempfile.TemporaryDirectory(prefix='manual-review ') as directory:
        path = Path(directory) / 'multiple-hints.csv'
        path.write_bytes(multiple.encode('utf-8'))
        native.append({'name': 'multiple-hints', 'sources': {'study_json': native[0]['sources']['study_json'], 'followup_csv': multiple},
                       'preflight': json.loads(cli('--study', 'examples/study.json', '--input', str(path), '--check-input', '--format', 'json').stdout)})
    result = subprocess.run([shutil.which('node', path=environment['PATH']), 'scripts/review_notes_test.mjs', '_build/browser'],
                            input=json.dumps(native, ensure_ascii=False), capture_output=True, text=True, encoding='utf-8',
                            env=environment, cwd=str(ROOT), timeout=120)
    if result.returncode:
        raise RuntimeError('manual review acceptance failed:\n' + result.stderr)
    record = json.loads(result.stdout)
    output = ROOT / '_build/browser/acceptance'
    value = json.loads((output / 'review-notes.json').read_text(encoding='utf-8'))
    digest = value.pop('sha256')
    canonical = json.dumps(value, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
    if hashlib.sha256(canonical).hexdigest() != digest:
        raise AssertionError('independent Python review payload hash differs')
    for language in ('en', 'zh-CN'):
        text = (output / ('review-notes.' + language + '.html')).read_text(encoding='utf-8')
        parser = SafeNotes()
        parser.feed(text)
        joined = ''.join(parser.text)
        if not parser.csp or '<script>alert(1)</script>' not in joined or value['context']['source_sha256'] not in joined:
            raise AssertionError('export lost escaped note or input fingerprint')
    record['independent_python_payload_hash'] = True
    passed('human review: native hint parity, independent viewing states, source binding and unchanged clinical evidence')
    passed('review note persistence: strict version/hash/context, malformed records, limits and backward clock handling')
    passed('review note documents: bilingual HTML/Markdown, pending items, literal untrusted text and matching fingerprints')
    return record
