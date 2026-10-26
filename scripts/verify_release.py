#!/usr/bin/env python3
"""Verify local candidate archives and their cross-file consistency; never publish."""
import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
from zipfile import ZipFile

BROWSER_FILES = ('index.html', 'smoke.html', 'browser.js', 'browser.d.ts', 'app.mjs', 'workbench.mjs',
    'delivery.mjs', 'archive.mjs', 'review-notes.mjs', 'review-notes-ui.mjs', 'handoff.mjs', 'handoff-ui.mjs',
    'edit-history.mjs', 'visit-editor.mjs', 'visit-editor-ui.mjs', 'observation-editor.mjs', 'examples.mjs',
    'workbench.css', 'package.json', 'serve_browser.py')

def candidate_id(value):
    if not re.fullmatch(r'rc\.[1-9][0-9]{0,5}', value): raise ValueError('candidate must be rc.N with a positive integer')
    return value

def digest(content): return hashlib.sha256(content).hexdigest()

def zip_files(content):
    if len(content) > 64*1024*1024: raise ValueError('archive exceeds 64 MiB')
    with ZipFile(io.BytesIO(content)) as archive:
        entries = archive.infolist()
        if len(entries) > 1000 or sum(item.file_size for item in entries) > 64*1024*1024: raise ValueError('archive resource limit exceeded')
        files = {}; seen = set()
        for item in entries:
            name = item.filename; path = PurePosixPath(name)
            if path.is_absolute() or '..' in path.parts or any(c in name for c in ('\\', ':', '\0')) or any(ord(c)<32 for c in name) or name.casefold() in seen:
                raise ValueError('unsafe or duplicate archive member')
            seen.add(name.casefold())
            if item.file_size > 16*1024*1024 or item.flag_bits & 1 or (item.external_attr >> 16) & 0o170000 == 0o120000: raise ValueError('unsupported archive member')
            if not item.is_dir(): files[name] = archive.read(item)
        return files, archive.comment

def normalized(name, content):
    text_suffixes = {'.mbt','.mbti','.md','.mjs','.js','.css','.json','.html','.svg','.csv','.py','.yml','.toml'}
    return content.replace(b'\r\n',b'\n') if Path(name).suffix in text_suffixes or Path(name).name in {'moon.mod','moon.pkg','LICENSE','.gitignore','.gitattributes'} else content

def source_fingerprint(files):
    checksum = hashlib.sha256(); count = 0
    for name in sorted(files):
        path=PurePosixPath(name)
        if path.name=='acceptance-results.json' or path.suffix.lower() in {'.zip','.png','.jpg','.jpeg','.webp'} or (path.suffix=='.html' and path.parts[0]=='examples'): continue
        checksum.update(name.encode('utf-8')+b'\0');checksum.update(files[name].replace(b'\r\n',b'\n')+b'\0');count+=1
    return checksum.hexdigest(),count

def verify_release(directory):
    folder=Path(directory)
    manifest_bytes=(folder/'release-manifest.json').read_bytes()
    manifest=json.loads(manifest_bytes)
    if manifest.get('schema_version') != 2: raise ValueError('unsupported release manifest; this verifier requires candidate manifest v2')
    version=manifest['version']; candidate=candidate_id(manifest['candidate']); commit=manifest['git_commit']
    if not re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)',version) or not re.fullmatch(r'[0-9a-f]{40}',commit): raise ValueError('invalid version or source commit')
    stem='lesion-followup-'+version+'-'+candidate
    expected={'impart563-lesion-followup-'+version+'.zip',stem+'-source.zip',stem+'-browser.zip'}
    descriptors=manifest['artifacts']
    if len(descriptors)!=3 or {item['name'] for item in descriptors}!=expected: raise ValueError('candidate artifact set differs')
    archives={}; checksums={}
    for item in descriptors:
        name=item['name']; path=folder/name
        if set(item)!={'name','sha256','bytes'} or path.is_symlink(): raise ValueError('invalid artifact descriptor')
        content=path.read_bytes()
        if len(content)!=item['bytes'] or digest(content)!=item['sha256']: raise ValueError('artifact hash or length differs: '+name)
        archives[name]=zip_files(content);checksums[name]=digest(content)
    checksums['release-manifest.json']=digest(manifest_bytes)
    supplied={}
    for line in (folder/'SHA256SUMS').read_text(encoding='utf-8').splitlines():
        value,name=line.split('  ',1)
        if name in supplied: raise ValueError('duplicate checksum entry')
        supplied[name]=value
    if supplied!=checksums: raise ValueError('checksum file differs')
    source, comment=archives[stem+'-source.zip']
    if comment.decode('ascii')!=commit: raise ValueError('source archive commit differs')
    if source_fingerprint(source)!=(manifest['source_sha256'],manifest['source_file_count']): raise ValueError('source fingerprint differs')
    module,_=archives['impart563-lesion-followup-'+version+'.zip']
    if not {'moon.mod','LICENSE','README.mbt.md','moon.pkg','pkg.generated.mbti'}.issubset(module): raise ValueError('module files missing')
    for name,content in module.items():
        if any(part in {'_build','.mooncakes','.repos','.git','__pycache__'} for part in PurePosixPath(name).parts) or name.startswith('examples/downstream-consumer/'):
            raise ValueError('local files leaked into module')
        if name not in source or normalized(name,content)!=normalized(name,source[name]): raise ValueError('module/source content differs: '+name)
    module_text=module['moon.mod'].decode('utf-8')
    if 'name = "impart563/lesion-followup"' not in module_text or ('version = "'+version+'"') not in module_text: raise ValueError('module identity differs')
    browser,_=archives[stem+'-browser.zip']
    if set(browser)!=set(BROWSER_FILES)|{'LICENSE','WORKBENCH.md'}: raise ValueError('browser runtime set differs')
    if json.loads(browser['package.json'])!={'type':'module'}: raise ValueError('browser module type differs')
    for name,content in browser.items():
        source_name='scripts/serve_browser.py' if name=='serve_browser.py' else 'docs/workbench.md' if name=='WORKBENCH.md' else name if name=='LICENSE' else 'browser/'+name
        if source_name in source and normalized(name,content)!=normalized(name,source[source_name]): raise ValueError('browser/source content differs: '+name)
    for name in BROWSER_FILES:
        if name.endswith('.mjs'):
            imports=re.findall(r'(?:from\s*|import\s*\()\s*[\'"]\./([^\'"]+)[\'"]',browser[name].decode('utf-8'))
            if any(dependency not in browser for dependency in imports): raise ValueError('browser import missing: '+name)
    backends=manifest['candidate_consumer']['backends']
    if backends!={name:'passed' for name in ('wasm','wasm-gc','js','native')}: raise ValueError('consumer checks incomplete')
    return {'status':'passed','version':version,'candidate':candidate,'git_commit':commit,
        'source_sha256':manifest['source_sha256'],'source_file_count':manifest['source_file_count'],
        'archives':{name:{'files':len(value[0]),'expanded_bytes':sum(map(len,value[0].values()))} for name,value in archives.items()},
        'browser_runtime_files':len(BROWSER_FILES),'consumer_backends':backends,
        'scope':'local archive consistency and recorded consumer checks; publication and authenticity are not verified'}

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('directory',type=Path)
    parser.add_argument('--record',type=Path);args=parser.parse_args()
    result=verify_release(args.directory);text=json.dumps(result,ensure_ascii=False,indent=2)+'\n'
    if args.record: args.record.write_text(text,encoding='utf-8')
    print(text,end='')

if __name__=='__main__': main()
