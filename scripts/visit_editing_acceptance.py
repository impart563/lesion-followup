"""Check whole-visit edits and text history against independent native replays."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def verify_visit_editing(cli, environment, passed):
    result = subprocess.run([shutil.which('node', path=environment['PATH']), 'scripts/visit_editing_test.mjs', '_build/browser'],
        cwd=str(ROOT), env=environment, capture_output=True, text=True, encoding='utf-8', timeout=180)
    if result.returncode: raise RuntimeError('Visit editing acceptance failed:\n'+result.stderr)
    record = json.loads(result.stdout)
    cases = record.pop('native_cases'); comparisons = 0
    with tempfile.TemporaryDirectory(prefix='visit editing ') as temporary:
        folder = Path(temporary)
        for case in cases:
            study, csv = folder/'study.json', folder/'followup.csv'
            study.write_bytes(case['source']['study_json'].encode('utf-8'))
            csv.write_bytes(case['source']['followup_csv'].encode('utf-8'))
            args = ('--study', str(study), '--input', str(csv))
            preflight = json.loads(cli(*args, '--check-input', '--format', 'json').stdout)
            assert preflight == case['preflight'], case['name']
            for format, expected in case['outputs'].items():
                output = folder/('report.'+format)
                cli(*args, '--lang', 'zh-CN', '--format', format, '--output', str(output))
                assert output.read_bytes().decode('utf-8') == expected, (case['name'], format)
                comparisons += 1
    record['native_preflight_comparisons'] = len(cases)
    record['native_report_comparisons'] = comparisons
    passed('whole-visit append and management: blank measurements, complete targets, native validation and untouched observation content')
    passed('visit operation preview: explicit apply, duplicate/date rejection and stale or replaced preview protection')
    passed('input edit history: coalescing, exact raw restoration, bounded retention, branching and external-load reset')
    return record
