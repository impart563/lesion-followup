"""Complete handoff checks with native bundles and independently written ZIPs."""
import io
import json
import hashlib
from pathlib import Path
import shutil
import subprocess
import tempfile
from zipfile import ZipFile, ZIP_DEFLATED
from delivery_acceptance import StreamingBuffer

ROOT = Path(__file__).resolve().parents[1]


def verify_handoff(cli, environment, passed):
    output = ROOT / '_build/browser/acceptance'
    native = []
    with tempfile.TemporaryDirectory(prefix='handoff-native ') as temporary:
        folder = Path(temporary)
        for profile in ('lf', 'unicode-crlf'):
            study = (ROOT / 'examples/study.json').read_text(encoding='utf-8')
            csv = (ROOT / 'examples/followup.csv').read_text(encoding='utf-8')
            if profile == 'unicode-crlf':
                value = json.loads(study); value['study_id'] = '合成交接 Ω'
                study = json.dumps(value, ensure_ascii=False, indent=2) + '\n'
                study, csv = (text.replace('\n', '\r\n') for text in (study, csv))
            study_path, csv_path = folder/'study.json', folder/'followup.csv'
            study_path.write_bytes(study.encode('utf-8')); csv_path.write_bytes(csv.encode('utf-8'))
            for language in ('en', 'zh-CN'):
                bundle = folder/(profile+'-'+language)
                cli('--study', str(study_path), '--input', str(csv_path), '--lang', language, '--bundle', str(bundle))
                native.append({'profile': profile, 'language': language, 'sources': {'study_json': study, 'followup_csv': csv},
                    'files': [{'name': p.name, 'content': p.read_bytes().decode('utf-8')} for p in sorted(bundle.iterdir())]})

        def node(data, external=False):
            args = [shutil.which('node', path=environment['PATH']), 'scripts/handoff_test.mjs', '_build/browser']
            if external: args.append('--external')
            result = subprocess.run(args, input=json.dumps(data, ensure_ascii=False), capture_output=True,
                text=True, encoding='utf-8', cwd=str(ROOT), env=environment, timeout=180)
            if result.returncode: raise RuntimeError('handoff acceptance failed:\n'+result.stderr)
            return json.loads(result.stdout)

        record = node({'native': native})
        with ZipFile(output/'handoff-with-notes.zip') as original:
            manifest = json.loads(original.read('handoff.json'))
            digest = manifest.pop('sha256')
            assert hashlib.sha256(json.dumps(manifest, ensure_ascii=False, separators=(',', ':')).encode('utf-8')).hexdigest() == digest
            for file in manifest['files']:
                content = original.read(file['name'])
                assert len(content) == file['byte_length'] and hashlib.sha256(content).hexdigest() == file['sha256']
            fixtures = []
            for name, streaming in [('handoff-python-deflated.zip', False), ('handoff-python-streamed.zip', True)]:
                buffer = StreamingBuffer() if streaming else io.BytesIO()
                with ZipFile(buffer, 'w', compression=ZIP_DEFLATED) as archive:
                    for info in original.infolist(): archive.writestr(info.filename, original.read(info.filename))
                (output/name).write_bytes(buffer.getvalue()); fixtures.append(name)
        external = node({'fixtures': fixtures}, external=True)
        for i in range(len(native)):
            with ZipFile(output/('handoff-native-'+str(i)+'.zip')) as archive:
                target = folder/('export-'+str(i)); target.mkdir()
                for name in ('manifest.json', 'report.html', 'audit.json', 'audit.csv', 'chart.svg'):
                    (target/name).write_bytes(archive.read('report/'+name))
                cli('--verify-bundle', str(target), '--format', 'json')
        record['independent_python_manifest_hashes'] = True
        record['independent_deflate_fixtures'] = external['count']
        record['native_verified_exported_bundles'] = len(native)
    passed('complete handoff export: bilingual native bytes, raw source pairs, optional notes and independent manifest hashes')
    passed('handoff reception: strict files, nested integrity, source/note binding and complete native report regeneration')
    passed('handoff restore: atomic apply, no-note clearing, stale edits, changed files and concurrent inspection rejection')
    return record
