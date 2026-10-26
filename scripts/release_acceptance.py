"""Exercise candidate verification with real packaged sources and deliberate corruption."""
from pathlib import Path
import json,tempfile,subprocess
from zipfile import ZipFile,ZIP_DEFLATED
from verify_release import BROWSER_FILES,candidate_id,digest,verify_release

ROOT=Path(__file__).resolve().parents[1]

def verify_publish_filter(moon,environment,passed):
    with tempfile.TemporaryDirectory(prefix='publish filter ') as temporary:
        folder=Path(temporary)
        (folder/'moon.mod').write_text('name = "impart563/publish-filter-fixture"\nversion = "0.0.0"\nreadme = "README.md"\nlicense = "Apache-2.0"\n',encoding='utf-8')
        (folder/'moon.pkg').write_text('',encoding='utf-8')
        (folder/'marker.mbt').write_text('///|\npub fn marker() -> Int { 1 }\n',encoding='utf-8')
        (folder/'README.md').write_text('Synthetic publication-filter fixture.\n',encoding='utf-8')
        (folder/'LICENSE').write_bytes((ROOT/'LICENSE').read_bytes())
        (folder/'.moonignore').write_bytes((ROOT/'.moonignore').read_bytes())
        forbidden=['old-source.zip','nested/backup.zip','backup.bundle','__pycache__/local.pyc','nested/__pycache__/local.pyc','scripts/private.txt','.github/ci.yml','.repos/foreign.txt','target/cache.txt','nested/_build/cache.txt']
        for name in forbidden:
            path=folder/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_text('synthetic local artifact',encoding='utf-8')
        result=subprocess.run([moon,'package','--list'],cwd=str(folder),env=environment,capture_output=True,text=True,encoding='utf-8',timeout=180)
        if result.returncode: raise RuntimeError('publish-filter fixture failed:\n'+result.stderr)
        with ZipFile(folder/'_build/publish/impart563-publish-filter-fixture-0.0.0.zip') as archive:
            names=set(name.replace('\\','/') for name in archive.namelist())
        assert {'marker.mbt','moon.mod','moon.pkg','README.md','LICENSE'}.issubset(names)
        assert not names.intersection(forbidden),names.intersection(forbidden)
    passed('publication filters: actual packaging excludes root/nested archives, local caches and development-only files')
    return {'status':'passed','rejected_local_files':len(forbidden),'commands':[{'command':'moon package --list','cwd':'<publish-filter-fixture>','exit_code':0}]}

def verify_release_contract(package,consumer,paths,fingerprint,count,passed):
    for value in ('rc.1','rc.2','rc.999999'): assert candidate_id(value)==value
    invalid=('rc.0','rc.01','rc.-1','rc.1/next','../rc.1','RC.1','rc.1000000','0.2.0-rc.1','rc.2\n')
    for value in invalid:
        try: candidate_id(value)
        except ValueError: continue
        raise AssertionError('accepted invalid candidate: '+value)
    with tempfile.TemporaryDirectory(prefix='release contract ') as temporary:
        folder=Path(temporary);version=package.name[len('impart563-lesion-followup-'):-4]
        stem='lesion-followup-'+version+'-rc.2';commit='1'*40
        source=folder/(stem+'-source.zip')
        with ZipFile(source,'w',ZIP_DEFLATED) as archive:
            for path in paths: archive.writestr(path.relative_to(ROOT).as_posix(),path.read_bytes())
            archive.comment=commit.encode('ascii')
        (folder/package.name).write_bytes(package.read_bytes())
        browser=folder/(stem+'-browser.zip')
        with ZipFile(browser,'w',ZIP_DEFLATED) as archive:
            for name in BROWSER_FILES: archive.writestr(name,(ROOT/'_build/browser'/name).read_bytes())
            archive.writestr('LICENSE',(ROOT/'LICENSE').read_bytes())
            archive.writestr('WORKBENCH.md',(ROOT/'docs/workbench.md').read_bytes())
        manifest={'schema_version':2,'version':version,'candidate':'rc.2','git_commit':commit,'source_sha256':fingerprint,
            'source_file_count':count,'candidate_consumer':consumer,
            'publication':{'mooncakes':'not published','registry_install':'not performed'},'artifacts':[]}
        def seal():
            manifest['artifacts']=[{'name':path.name,'sha256':digest(path.read_bytes()),'bytes':path.stat().st_size} for path in (folder/package.name,source,browser)]
            (folder/'release-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
            (folder/'SHA256SUMS').write_text(''.join(digest(path.read_bytes())+'  '+path.name+'\n' for path in (folder/package.name,source,browser,folder/'release-manifest.json')),encoding='utf-8')
        seal();valid=verify_release(folder)
        baseline={path.name:path.read_bytes() for path in folder.iterdir()}
        rejected=0
        def reject(mutate,expected):
            nonlocal rejected,manifest
            for name,content in baseline.items(): (folder/name).write_bytes(content)
            manifest=json.loads(baseline['release-manifest.json'])
            mutate()
            try: verify_release(folder)
            except (ValueError,FileNotFoundError) as error:
                assert expected in str(error),str(error);rejected+=1;return
            raise AssertionError('accepted malformed candidate')
        reject(lambda:(folder/package.name).unlink(),'')
        reject(lambda:browser.write_bytes(b'changed'),'artifact hash')
        reject(lambda:(folder/'SHA256SUMS').write_text('0'*64+'  release-manifest.json\n',encoding='utf-8'),'checksum file')
        def change_manifest(key,value): manifest[key]=value;seal()
        reject(lambda:change_manifest('candidate','rc.0'),'candidate must')
        reject(lambda:change_manifest('schema_version',1),'unsupported release manifest')
        reject(lambda:change_manifest('source_sha256','0'*64),'source fingerprint')
        def rewrite(path,mutate):
            with ZipFile(path) as archive: files={i.filename:archive.read(i) for i in archive.infolist() if not i.is_dir()};comment=archive.comment
            files,comment=mutate(files,comment)
            with ZipFile(path,'w',ZIP_DEFLATED) as archive:
                for name,content in files.items():archive.writestr(name,content)
                archive.comment=comment
            seal()
        reject(lambda:rewrite(source,lambda files,comment:(files,b'2'*40)),'source archive commit')
        reject(lambda:rewrite(folder/package.name,lambda files,comment:({**files,'README.mbt.md':b'changed'},comment)),'module/source')
        reject(lambda:rewrite(browser,lambda files,comment:({k:v for k,v in files.items() if k!='observation-editor.mjs'},comment)),'browser runtime set')
        reject(lambda:rewrite(browser,lambda files,comment:({**files,'../outside.txt':b'bad'},comment)),'unsafe or duplicate')
        reject(lambda:change_manifest('candidate_consumer',{'backends':{'native':'passed'}}),'consumer checks incomplete')
    passed('release candidate contracts: strict rc IDs, source/module/browser identity, runtime closure and exact checksum sets')
    passed('candidate corruption rejection: altered/missing artifacts, recomputed cross-file mismatches, paths and incomplete consumer evidence')
    return {'status':'passed','archives':len(valid['archives']),'browser_runtime_files':valid['browser_runtime_files'],
        'rejected_candidates':rejected,'rejected_candidate_ids':len(invalid),'checks':['source archive fingerprint and commit','module/source bytes and identity','complete browser runtime and local imports','all artifact lengths, hashes and checksum entries','recorded four-backend consumer completion']}
