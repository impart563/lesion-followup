#!/usr/bin/env python3
"""Reproduce the synthetic review collection and check independent hand calculations."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
CASES = ROOT / "examples" / "review-cases"
FORMATS = ("json", "csv", "markdown", "svg", "html")


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def reproduce(output, cli):
    # Fail before writing anything if the destination already exists.
    output.mkdir(parents=True, exist_ok=False)
    catalogue = json.loads((CASES / "expected.json").read_text(encoding="utf-8"))
    batch = json.loads((CASES / "batch.json").read_text(encoding="utf-8"))
    require(batch["cases"] == [{k: case[k] for k in ("id", "study", "input")}
                               for case in catalogue["cases"]], "batch/catalogue inputs differ")
    verified = []
    for case in catalogue["cases"]:
        study = CASES / case["study"]
        followup = CASES / case["input"]
        sources = {"study.json": study.read_bytes(), "followup.csv": followup.read_bytes()}
        folder = output / case["id"]
        folder.mkdir()
        for name, content in sources.items():
            (folder / name).write_bytes(content)
        args = ("--study", str(study), "--input", str(followup))
        quality = json.loads(cli(*args, "--check-input", "--format", "json").stdout)
        require(quality["valid"], case["id"] + ": preflight failed")
        reports = {fmt: cli(*args, "--format", fmt, "--lang", "zh-CN").stdout for fmt in FORMATS}
        audit = json.loads(reports["json"])
        require(audit["scope"] == catalogue["scope"], "review scope changed")
        require(len(audit["assessments"]) == len(case["expected"]), "visit count differs")
        for actual, expected in zip(audit["assessments"], case["expected"]):
            for key in ("visit_id", "sum_mm", "prior_nadir_mm", "target_response"):
                require(actual[key] == expected[key], case["id"] + ": " + key + " differs from hand calculation")
            require(expected["finding"] in {f["code"] for f in actual["findings"]}, "expected rule branch missing")
        for fmt, content in reports.items():
            (folder / ("report." + ("md" if fmt == "markdown" else fmt))).write_bytes(content.encode("utf-8"))
        draft = {"schema_version": 1, "kind": "lesion-followup-draft", "saved_at": "2026-01-01T00:00:00.000Z",
                 "language": "zh-CN", "study_json": sources["study.json"].decode("utf-8"),
                 "followup_csv": sources["followup.csv"].decode("utf-8")}
        (folder / "draft.json").write_text(json.dumps(draft, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        require(study.read_bytes() == sources["study.json"] and followup.read_bytes() == sources["followup.csv"], "source changed")
        verified.append({"id": case["id"], "target_responses": [a["target_response"] for a in audit["assessments"]],
                         "input_sha256": {name: hashlib.sha256(data).hexdigest() for name, data in sources.items()}})
    cli("--batch", str(CASES / "batch.json"), "--bundle", str(output / "batch"), "--lang", "zh-CN")
    index = json.loads((output / "batch/index.json").read_text(encoding="utf-8"))
    require((index["success_count"], index["failure_count"]) == (4, 0), "batch expected 4 successes")
    for case in catalogue["cases"]:
        require((output / "batch" / case["id"] / "audit.json").read_bytes() ==
                (output / case["id"] / "report.json").read_bytes(), "batch/individual review differ")
        cli("--verify-bundle", str(output / "batch" / case["id"]), "--format", "json")
    comparison = ("--study", str(CASES / "../study.json"), "--input", str(CASES / "../followup.revised.csv"),
                  "--compare-study", str(CASES / "../study.json"), "--compare-input", str(CASES / "../followup.csv"))
    revision = json.loads(cli(*comparison, "--format", "json").stdout)
    require(len(revision["input_changes"]) == 1, "expected one revised observation")
    require([v["visit_id"] for v in revision["affected_visits"]] == ["week-4", "week-6", "week-8"], "revision downstream evidence differs")
    (output / "revision.json").write_text(json.dumps(revision, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (output / "revision.html").write_bytes(cli(*comparison, "--format", "html", "--lang", "zh-CN").stdout.encode("utf-8"))
    result = {"status": "passed", "scope": "synthetic target-lesion software examples; not clinical validation",
              "cases": verified, "batch_success_count": 4, "changed_observations": 1, "affected_visits": 3}
    (output / "verification.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True, help="new output directory")
    args = parser.parse_args()
    moon = shutil.which("moon")
    if not moon:
        raise RuntimeError("MoonBit must be on PATH")
    env = dict(os.environ, MOON_WORK="off")

    def cli(*arguments):
        return subprocess.run([moon, "run", "--target", "native", "cmd/demo", "--", *arguments],
                              cwd=str(ROOT), env=env, capture_output=True, text=True, encoding="utf-8", check=True, timeout=180)

    result = reproduce(args.output.resolve(), cli)
    print("Verified {} synthetic cases, batch and revision: {}".format(len(result["cases"]), args.output))


if __name__ == "__main__":
    main()
