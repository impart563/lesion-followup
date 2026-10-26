"""Compare per-target form edits with independent native replays."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parents[1]

def verify_observations(cli,environment,passed):
    result=subprocess.run([shutil.which('node',path=environment['PATH']),'scripts/observation_test.mjs','_build/browser'],cwd=str(ROOT),env=environment,capture_output=True,text=True,encoding='utf-8',timeout=180)
    if result.returncode: raise RuntimeError('Observation acceptance failed:\n'+result.stderr)
    record=json.loads(result.stdout);cases=record.pop('native_cases');comparisons=0
    with tempfile.TemporaryDirectory(prefix='observation native ') as temporary:
        folder=Path(temporary)
        for case in cases:
            study,csv=folder/'study.json',folder/'followup.csv'
            study.write_bytes(case['source']['study_json'].encode('utf-8'));csv.write_bytes(case['source']['followup_csv'].encode('utf-8'))
            args=('--study',str(study),'--input',str(csv))
            assert json.loads(cli(*args,'--check-input','--format','json').stdout)==case['preflight'],case['name']
            for format,expected in case['outputs'].items():
                output=folder/('report.'+format);cli(*args,'--lang','zh-CN','--format',format,'--output',str(output))
                assert output.read_bytes().decode('utf-8')==expected,(case['name'],format)
                comparisons+=1
    record['native_preflight_comparisons']=len(cases);record['native_report_comparisons']=comparisons
    passed('per-target observations: complete target forms, five states, precise values and reasons match native preflight/reports')
    passed('observation apply: unchanged surrounding visits, explicit changes, strict schema and stale-preview rejection')
    return record
