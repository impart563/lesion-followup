#!/usr/bin/env python3
"""Build, test and review the complete public workflow using only Python stdlib."""
from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
from collections import Counter
from datetime import datetime, timezone
from html.parser import HTMLParser
import xml.etree.ElementTree as ET
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
FORMATS = ("markdown", "json", "csv", "svg", "html")
SCENARIOS = {
    "nadir-boundary": ["PR", "PR", "PD"],
    "node-resolution": ["PR", "CR", "NE"],
    "missing-visit": ["PR", "NE", "PR", "PD"],
}


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def source_paths():
    """Prune caches before walking; use a platform-independent relative order."""
    paths = []
    excluded = {".git", "_build", "target", ".mooncakes", ".repos", "__pycache__"}
    for directory, directories, files in os.walk(str(ROOT)):
        directories[:] = [name for name in directories if name not in excluded]
        paths.extend(Path(directory) / name for name in files)
    return sorted(paths, key=lambda path: path.relative_to(ROOT).as_posix())


def source_digest():
    digest = hashlib.sha256()
    included = []
    for path in source_paths():
        relative = path.relative_to(ROOT)
        if path.name == "acceptance-results.json" or path.suffix in {".zip", ".html", ".png"}:
            continue
        included.append(relative.as_posix())
        digest.update(relative.as_posix().encode("utf-8") + b"\0")
        digest.update(path.read_bytes().replace(b"\r\n", b"\n") + b"\0")
    return digest.hexdigest(), len(included)


class ReviewHTML(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.ids = []
        self.links = []
        self.tags = []
        self.text = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        self.tags.append(tag)
        if "id" in attrs:
            self.ids.append(attrs["id"])
        if "href" in attrs:
            self.links.append(attrs["href"])
        require(not any(key.startswith("on") for key in attrs), "HTML contains event handler")
        require("src" not in attrs, "HTML unexpectedly loads a resource")

    def handle_data(self, data):
        self.text.append(data)


def verify_formats(outputs, expected):
    report = json.loads(outputs["json"])
    require(report["schema_version"] == 1, "report version changed")
    require(report["scope"] == "target_lesions_only", "scope missing")
    assessments = report["assessments"]
    actual = [a["target_response"] for a in assessments]
    require(actual == expected, "unexpected clinical categories: " + repr(actual))
    require(report["summary"]["visit_count"] == len(expected), "summary visit mismatch")
    counts = Counter(expected)
    require(report["summary"]["response_counts"] == {key: counts[key] for key in ("CR", "PR", "SD", "PD", "NE")}, "summary category mismatch")
    records = list(csv.DictReader(io.StringIO(outputs["csv"])))
    assessment_rows = [row for row in records if row["row_type"] == "assessment"]
    require(len(assessment_rows) == len(assessments), "CSV assessment count mismatch")
    for row, a in zip(assessment_rows, assessments):
        require(row["visit_id"] == a["visit_id"], "CSV order mismatch")
        require(row["target_response"] == a["target_response"], "CSV category mismatch")
        require(row["sum_mm"] == (a["sum_mm"] or ""), "CSV sum mismatch")
        require(row["prior_nadir_mm"] == a["prior_nadir_mm"], "CSV nadir mismatch")
        require(row["prior_nadir_visit_id"] == a["prior_nadir_visit_id"], "CSV reference mismatch")
    measurement_rows = [row for row in records if row["row_type"] == "measurement"]
    expected_measurements = {(a["visit_id"], m["lesion_id"]): m for a in assessments for m in a["measurements"]}
    require(len(measurement_rows) == len(expected_measurements), "CSV measurement count mismatch")
    for row in measurement_rows:
        m = expected_measurements[(row["visit_id"], row["lesion_id"])]
        require(row["diameter_mm"] == (m["effective_mm"] or ""), "CSV effective diameter mismatch")
        require(row["state"] == m["observation"]["state"], "CSV observation mismatch")
    findings = [row for row in records if row["row_type"] == "finding"]
    require(len(findings) == sum(len(a["findings"]) for a in assessments), "CSV finding count mismatch")
    svg = ET.fromstring(outputs["svg"])
    require(svg.tag == "{http://www.w3.org/2000/svg}svg", "not an SVG document")
    circles = list(svg.iter("{http://www.w3.org/2000/svg}circle"))
    require(len(circles) == 1 + sum(a["target_response"] != "NE" for a in assessments), "NE incorrectly plotted as a measurement")
    html = ReviewHTML()
    html.feed(outputs["html"])
    require(not {"script", "iframe", "img", "link"}.intersection(html.tags), "HTML is not self-contained")
    require(len(html.ids) == len(set(html.ids)), "HTML has duplicate IDs")
    for link in html.links:
        if link.startswith("#"):
            require(link[1:] in html.ids, "broken HTML navigation: " + link)
    for index, a in enumerate(assessments):
        require("visit-" + str(index) in html.ids, "missing visit evidence section")
        require(a["visit_id"] in "".join(html.text), "HTML omitted visit")
    require("target_pd" in outputs["markdown"] if "PD" in expected else True, "Markdown omitted rule evidence")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--record", type=Path, help="write a verified JSON result after all checks pass")
    options = parser.parse_args()
    moon = shutil.which("moon")
    if moon is None:
        candidate = Path.home() / ".moon" / "bin" / ("moon.exe" if os.name == "nt" else "moon")
        if candidate.exists():
            moon = str(candidate)
    if moon is None:
        raise RuntimeError("MoonBit is not installed; install it from https://www.moonbitlang.com/download/")
    environment = os.environ.copy()
    environment["PATH"] = str(Path(moon).parent) + os.pathsep + environment.get("PATH", "")
    commands = []
    checks = []

    def run(args, cwd=ROOT, expected=0, workspace=None):
        env = environment.copy()
        env["MOON_WORK"] = str(workspace) if workspace else "off"
        result = subprocess.run([moon] + list(args), cwd=str(cwd), env=env, text=True, encoding="utf-8", errors="replace", capture_output=True, timeout=180)
        display_args = []
        for argument in args:
            if argument.startswith(tempfile.gettempdir() + os.sep):
                argument = "<temporary>/" + Path(argument).name
            display_args.append(argument)
        commands.append({"command": "moon " + " ".join(display_args), "cwd": str(Path(cwd).relative_to(ROOT)).replace("\\", "/"), "exit_code": result.returncode})
        if result.returncode != expected:
            raise RuntimeError("moon " + " ".join(args) + "\n" + result.stdout + "\n" + result.stderr)
        return result

    def cli(*args, expected=0):
        return run(["run", "--target", "native", "cmd/demo", "--"] + list(args), expected=expected)

    def passed(name):
        checks.append(name)
        print("PASS " + name, flush=True)

    version = run(["version", "--all"]).stdout.strip()
    run(["fmt", "--check"])
    run(["check", "--target", "all", "--deny-warn"])
    run(["build", "--target", "native", "--deny-warn"])
    tests = run(["test", "--target", "all", "--deny-warn"])
    test_counts = {}
    for total, passed_count, failed_count, target in re.findall(r"Total tests: (\d+), passed: (\d+), failed: (\d+)\. \[([^\]]+)\]", tests.stdout + tests.stderr):
        test_counts[target] = {"total": int(total), "passed": int(passed_count), "failed": int(failed_count)}
    require(set(test_counts) == {"wasm", "wasm-gc", "js", "native"}, "not all test targets ran")
    require(all(v["failed"] == 0 and v["total"] > 0 for v in test_counts.values()), "unit tests failed or absent")
    before = {p.relative_to(ROOT): p.read_bytes() for p in source_paths() if p.name == "pkg.generated.mbti"}
    run(["info"])
    after = {p.relative_to(ROOT): p.read_bytes() for p in source_paths() if p.name == "pkg.generated.mbti"}
    require(before == after, "public interfaces were stale; review moon info output")
    passed("format, warning-free checks, native build, four-target tests and public interfaces")
    quickstart = run(["run", "--target", "native", "examples/quickstart"]).stdout
    require("target_pd" in quickstart, "public quickstart failed")
    consumer = ROOT / "examples" / "downstream-consumer"
    downstream = run(["run", "--target", "native", "."], cwd=consumer, workspace=consumer / "moon.work").stdout
    require("Downstream consumer smoke passed: node CR retains 9.9 mm" in downstream, "external module failed")
    passed("public quickstart and separate downstream module")
    scenario_summaries = {}
    for scenario, expected in SCENARIOS.items():
        outputs = {}
        for report_format in FORMATS:
            args = ("--scenario", scenario, "--format", report_format)
            first = cli(*args).stdout
            require(first == cli(*args).stdout, "non-deterministic " + scenario + "/" + report_format)
            outputs[report_format] = first
        report = verify_formats(outputs, expected)
        scenario_summaries[scenario] = report["summary"]
        passed(scenario + ": five formats, repeatability and matching evidence")
    prefix = ("--study", "examples/study.json", "--input", "examples/followup.csv")
    outputs = {fmt: cli(*prefix, "--format", fmt).stdout for fmt in FORMATS}
    report = verify_formats(outputs, ["PR", "PR", "PR", "PD"])
    require([a["sum_mm"] for a in report["assessments"]] == ["35.0", "20.0", "24.0", "25.0"], "input fixture sums changed")
    require((ROOT / "examples/review.html").read_text(encoding="utf-8") == outputs["html"], "checked-in preview is stale")
    passed("JSON profile plus CSV input, fixture arithmetic and saved HTML preview")
    require(json.loads(cli(*prefix, "--check-input", "--format", "json").stdout)["valid"], "valid input preflight failed")
    for args in [("--format", "invalid"), ("--study", "only.json"), ("--scenario", "unknown"), ("--bundle", "b", "--format", "html"), ("--check-input", "--format", "svg")]:
        cli(*args, expected=2)
    cli("--help")
    require(cli("--version").stdout.strip() == "lesion-followup 0.1.0", "version output changed")
    passed("CLI modes, help, version and incompatible arguments")
    with tempfile.TemporaryDirectory(prefix="lesion-followup ") as directory:
        temp = Path(directory)
        bundle = temp / "review bundle"
        cli(*prefix, "--bundle", str(bundle))
        first_files = {p.name: p.read_bytes() for p in bundle.iterdir()}
        cli(*prefix, "--bundle", str(bundle))
        require(first_files == {p.name: p.read_bytes() for p in bundle.iterdir()}, "bundle bytes changed")
        require(set(first_files) == {"report.html", "audit.json", "audit.csv", "chart.svg", "manifest.json"}, "unexpected bundle contents")
        manifest = json.loads(first_files["manifest.json"])
        require(manifest["summary"] == report["summary"], "bundle manifest summary mismatch")
        for name in manifest["artifacts"]:
            require(name in first_files, "manifest refers to a missing artifact")
        require(first_files["report.html"].decode("utf-8") == outputs["html"], "bundle differs from direct output")
        target = temp / "direct.html"
        cli(*prefix, "--format", "html", "--output", str(target))
        require(target.read_text(encoding="utf-8") == outputs["html"], "file output mismatch")
        passed("deterministic review bundles, manifest and direct file output")
        study_path = temp / "study.json"
        csv_path = temp / "input.csv"
        study_text = (ROOT / "examples/study.json").read_text(encoding="utf-8")
        csv_text = (ROOT / "examples/followup.csv").read_text(encoding="utf-8")
        study_path.write_text(study_text, encoding="utf-8")
        csv_path.write_text(csv_text.replace("20.0,", "20.01,", 1), encoding="utf-8")
        temp_prefix = ("--study", str(study_path), "--input", str(csv_path))
        invalid = json.loads(cli(*temp_prefix, "--check-input", "--format", "json", expected=2).stdout)
        require(not invalid["valid"] and invalid["diagnostics"][0]["line"] == 2 and invalid["diagnostics"][0]["field"] == "diameter_mm", "CSV diagnostics lost physical location")
        target.write_text("sentinel", encoding="utf-8")
        cli(*temp_prefix, "--format", "html", "--output", str(target), expected=2)
        require(target.read_text(encoding="utf-8") == "sentinel", "invalid input wrote a partial review")
        csv_path.write_text(csv_text, encoding="utf-8")
        cli(*temp_prefix, "--format", "json", "--output", str(csv_path), expected=2)
        require(csv_path.read_text(encoding="utf-8") == csv_text, "source CSV was overwritten")
        cli(*temp_prefix, "--format", "json", "--output", str(study_path), expected=2)
        require(study_path.read_text(encoding="utf-8") == study_text, "source profile was overwritten")
        cli(*temp_prefix, "--output", str(temp / "missing" / "report.html"), expected=1)
        cli("--study", str(study_path), "--input", str(temp / "absent.csv"), expected=1)
        passed("structured input errors, no partial report, source protection and I/O failures")
        malicious = "<script>alert(1)</script>, \"quoted\"\nsecond line"
        with csv_path.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.writer(handle)
            writer.writerow(["visit_id", "date", "technique_id", "lesion_id", "state", "diameter_mm", "note"])
            writer.writerow(["review", "2026-01-02", "ct-venous-5mm", "T1", "not_evaluable", "", malicious])
            writer.writerow(["review", "2026-01-02", "ct-venous-5mm", "N1", "missing", "", ""])
        unsafe_outputs = {fmt: cli(*temp_prefix, "--format", fmt).stdout for fmt in FORMATS}
        verify_formats(unsafe_outputs, ["NE"])
        require("<script>" not in unsafe_outputs["html"], "HTML injection")
        data_rows = list(csv.DictReader(io.StringIO(unsafe_outputs["csv"])))
        require(any(row["message"] == malicious for row in data_rows), "CSV lost a quoted multiline note")
        passed("untrusted text escaping and multiline CSV round trip")
    run(["package"])
    package_path = ROOT / "_build" / "publish" / "impart563-lesion-followup-0.1.0.zip"
    with ZipFile(package_path) as archive:
        entries = [entry.replace("\\", "/") for entry in archive.namelist()]
    require("moon.mod" in entries and "LICENSE" in entries, "module archive is incomplete")
    require(not any(entry.startswith((".mooncakes/", "_build/", "examples/downstream-consumer/")) for entry in entries), "local/cache files leaked into package")
    require((ROOT / "README.md").read_bytes() == (ROOT / "README.mbt.md").read_bytes(), "README copies differ")
    passed("package archive and synchronized tested README")
    fingerprint, source_files = source_digest()
    record = {
        "status": "passed",
        "checked_at_utc": datetime.now(timezone.utc).isoformat(),
        "module": "impart563/lesion-followup@0.1.0",
        "scope": "software acceptance using synthetic data; not clinical validation",
        "source_sha256": fingerprint,
        "source_file_count": source_files,
        "reproduce": "python scripts/acceptance.py --record docs/acceptance-results.json",
        "toolchain": version.replace(str(Path.home()), "~"),
        "python_version": __import__("sys").version.split()[0],
        "unit_tests": test_counts,
        "workflow_checks": checks,
        "scenario_summaries": scenario_summaries,
        "file_input_summary": report["summary"],
        "command_count": len(commands),
        "commands": commands,
    }
    if options.record:
        destination = options.record if options.record.is_absolute() else ROOT / options.record
        destination.write_text(json.dumps(record, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("Acceptance passed: " + str(len(checks)) + " workflow groups; " + str(test_counts), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
