#!/usr/bin/env python3
"""Prepare a checked release candidate from a clean, accepted Git commit; never publish."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
from zipfile import ZIP_DEFLATED, ZipFile
from acceptance import source_digest
from build_browser import main as build_browser
from distribution import module_version, verify_candidate_consumer
from verify_release import BROWSER_FILES, candidate_id, verify_release

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "_build/release")
    parser.add_argument("--candidate", default="rc.2")
    args = parser.parse_args()
    try:
        candidate_id(args.candidate)
    except ValueError as error:
        parser.error(str(error))
    env = dict(os.environ, MOON_WORK="off")

    def git(*arguments):
        return subprocess.check_output(["git", *arguments], cwd=str(ROOT), encoding="utf-8").strip()

    if git("status", "--porcelain"):
        raise RuntimeError("commit reviewed sources and acceptance record before packaging")
    record = json.loads((ROOT / "docs/acceptance-results.json").read_text(encoding="utf-8"))
    if record["status"] != "passed" or record["source_sha256"] != source_digest()[0]:
        raise RuntimeError("acceptance record does not match this source tree")
    version = module_version()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    moon = shutil.which("moon")
    subprocess.run([moon, "package"], cwd=str(ROOT), env=env, check=True)
    package = output / ("impart563-lesion-followup-" + version + ".zip")
    shutil.copyfile(str(ROOT / "_build/publish" / package.name), str(package))
    consumer = verify_candidate_consumer(package, moon, env)
    build_browser()
    stem = "lesion-followup-" + version + "-" + args.candidate
    source = output / (stem + "-source.zip")
    subprocess.run(["git", "archive", "--format=zip", "--output", str(source), "HEAD"], cwd=str(ROOT), check=True)
    browser = output / (stem + "-browser.zip")
    # Explicit runtime allowlist: no acceptance fixtures, drafts or local screenshots.
    with ZipFile(browser, "w", ZIP_DEFLATED) as archive:
        for name in BROWSER_FILES:
            archive.write(ROOT / "_build/browser" / name, name)
        archive.write(ROOT / "LICENSE", "LICENSE")
        archive.write(ROOT / "docs/workbench.md", "WORKBENCH.md")
    files = [package, source, browser]
    manifest = {"schema_version": 2, "version": version, "candidate": args.candidate, "git_commit": git("rev-parse", "HEAD"),
                "source_sha256": record["source_sha256"], "source_file_count": record["source_file_count"], "candidate_consumer": consumer,
                "publication": {"github": "candidate prepared; publication not performed by this script",
                                "mooncakes": "not published", "registry_install": "not performed"},
                "artifacts": [{"name": p.name, "sha256": hashlib.sha256(p.read_bytes()).hexdigest(), "bytes": p.stat().st_size} for p in files]}
    (output / "release-manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    files.append(output / "release-manifest.json")
    (output / "SHA256SUMS").write_text("".join(hashlib.sha256(p.read_bytes()).hexdigest() + "  " + p.name + "\n" for p in files), encoding="utf-8")
    verification = verify_release(output)
    (output / "verification.json").write_text(json.dumps(verification, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Release candidate prepared: " + str(output))


if __name__ == "__main__":
    main()
