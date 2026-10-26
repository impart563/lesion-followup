#!/usr/bin/env python3
"""Verify the exact published dependency from a new directory, without a workspace."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from distribution import ROOT, module_version
from evidence_paths import public_record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--record', type=Path, required=True)
    options = parser.parse_args()
    moon = shutil.which('moon')
    if not moon:
        raise RuntimeError('MoonBit is not installed')
    dependency = 'impart563/lesion-followup@' + module_version()
    environment = dict(os.environ, MOON_WORK='off')
    commands = []
    def run(arguments, cwd):
        result = subprocess.run([moon] + arguments, cwd=str(cwd), env=environment,
                                capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=180)
        commands.append({'command': 'moon ' + ' '.join(arguments), 'exit_code': result.returncode,
                         'stdout': result.stdout, 'stderr': result.stderr})
        if result.returncode:
            raise RuntimeError('registry verification failed: ' + commands[-1]['command'] + '\n' + result.stdout + result.stderr)
        return result
    with tempfile.TemporaryDirectory(prefix='lesion-registry-consumer ') as directory:
        consumer = Path(directory)
        for name in ('moon.mod', 'moon.pkg', 'main.mbt'):
            shutil.copyfile(str(ROOT/'examples/downstream-consumer'/name), str(consumer/name))
        if dependency not in (consumer/'moon.mod').read_text(encoding='utf-8'):
            raise AssertionError('consumer version does not match release')
        run(['update'], consumer)
        metadata = json.loads(run(['view', dependency, '--json'], consumer).stdout)
        if metadata.get('status') != 'success':
            raise AssertionError('registry has not confirmed the exact release')
        if metadata['result']['module'] != 'impart563/lesion-followup' or metadata['result']['version'] != module_version():
            raise AssertionError('registry returned a different module/version')
        outputs = {}
        for backend in ('wasm', 'wasm-gc', 'js', 'native'):
            result = run(['run', '--target', backend, '.'], consumer)
            for marker in ('Downstream consumer smoke passed: node CR retains 9.9 mm',
                           'Downstream integration passed: text input, preflight, target-only NE, bilingual bundles and tamper rejection'):
                if marker not in result.stdout:
                    raise AssertionError('consumer checks did not complete on ' + backend)
            outputs[backend] = 'passed'
        if (consumer/'moon.work').exists():
            raise AssertionError('unexpected workspace')
        tree = run(['tree'], consumer).stdout
        record = {'status': 'passed', 'checked_at_utc': datetime.now(timezone.utc).isoformat(),
                  'dependency': dependency, 'source': 'public registry; fresh directory outside checkout',
                  'workspace': 'disabled by MOON_WORK=off; no moon.work copied', 'backends': outputs,
                  'registry_metadata': metadata, 'dependency_tree': tree, 'commands': commands,
                  'scope': 'synthetic software integration; not clinical validation'}
        record = public_record(record, ROOT, aliases=[(consumer, '<registry-consumer>')])
        options.record.parent.mkdir(parents=True, exist_ok=True)
        options.record.write_text(json.dumps(record, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print('Registry installation verified: ' + dependency + ' on four backends')


if __name__ == '__main__':
    main()
