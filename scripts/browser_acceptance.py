"""Exported JavaScript boundary checks and native CLI parity, using synthetic inputs."""
import csv
import io
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import urllib.request

from build_browser import package_browser
from serve_browser import make_server

ROOT = Path(__file__).resolve().parents[1]


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def verify_http_entry(output):
    # These checks are strictly loopback; avoid OS proxy/DNS settings for localhost.
    local_http = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with make_server(output, port=0, quiet=True) as server:
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        try:
            for name, expected_type in (("index.html", "text/html"), ("smoke.html", "text/html"),
                                        ("browser.js", "javascript"), ("app.mjs", "javascript"),
                                        ("workbench.mjs", "javascript"), ("delivery.mjs", "javascript"), ("archive.mjs", "javascript"), ("review-notes.mjs", "javascript"), ("review-notes-ui.mjs", "javascript"), ("handoff.mjs", "javascript"), ("handoff-ui.mjs", "javascript"), ("edit-history.mjs", "javascript"), ("visit-editor.mjs", "javascript"), ("visit-editor-ui.mjs", "javascript"), ("observation-editor.mjs", "javascript"), ("record-navigation.mjs", "javascript"), ("examples.mjs", "javascript"),
                                        ("workbench.css", "text/css")):
                url = "http://127.0.0.1:{}/{}".format(server.server_address[1], name)
                with local_http.open(url, timeout=10) as response:
                    require(expected_type in response.headers["Content-Type"], "wrong runtime MIME type: " + name)
                    require(response.read() == (output / name).read_bytes(), "served runtime differs: " + name)
        finally:
            server.shutdown()
            worker.join(timeout=10)


def verify_browser(run, cli, outputs, chinese_outputs, passed, environment):
    node = shutil.which("node", path=environment["PATH"])
    require(node is not None, "Node.js is required for browser acceptance")
    version = subprocess.run([node, "--version"], capture_output=True, text=True, check=True).stdout.strip()
    run(["build", "--target", "js", "--release", "--deny-warn", "browser"])
    output = package_browser()
    verify_http_entry(output)
    passed("localhost browser entry, ES-module MIME types and exact runtime assets")
    requests, expectations = [], []

    def add(request, expected):
        requests.append(request if isinstance(request, str) else json.dumps(request, ensure_ascii=False))
        expectations.append(expected)

    for text, code in (("{", "request_json"), ("[]", "request_schema"), ("{}", "request_version")):
        add(text, {"request_error": code})
    for change, code in (({"schema_version": 99}, "request_version"),
                         ({"action": "save"}, "request_action"),
                         ({"language": None}, "request_schema"),
                         ({"language": "zh"}, "request_language"),
                         ({"format": "html"}, "request_schema"),
                         ({"template": "other"}, "request_template"),
                         ({"extra": 1}, "request_schema")):
        add({"schema_version": 1, "action": "template", **change}, {"request_error": code})
    for template in ("single", "multi"):
        for language in ("en", "zh-CN"):
            add({"schema_version": 1, "action": "template", "template": template, "language": language},
                {"template": template, "language": language})
    study = (ROOT / "examples/study.json").read_text(encoding="utf-8")
    followup = (ROOT / "examples/followup.csv").read_text(encoding="utf-8")
    for language, reports in (("en", outputs), ("zh-CN", chinese_outputs)):
        for fmt, content in reports.items():
            add({"schema_version": 1, "action": "review", "study_json": study, "followup_csv": followup,
                 "language": language, "format": fmt}, {"content": content, "format": fmt})

    header = "visit_id,date,technique_id,lesion_id,state,diameter_mm,note\n"

    def track(measurements):
        return header + "".join("v{0},2026-02-{0:02d},ct-venous-5mm,T1,measured,{1},\n".format(i, mm)
                                for i, mm in enumerate(measurements, 1))

    single = json.loads(study)
    single["targets"] = single["targets"][:1]
    single["targets"][0]["baseline_mm"] = "50.0"
    single = json.dumps(single)
    bad_number = json.loads(study)
    bad_number["targets"][0]["baseline_mm"] = 30.0
    malicious = '<script>alert(1)</script>, "复核"\r\n第二行🙂'
    quoted = io.StringIO(newline="")
    writer = csv.writer(quoted)
    writer.writerow(header.strip().split(","))
    writer.writerow(["复核🙂", "2026-01-02", "ct-venous-5mm", "T1", "not_evaluable", "", malicious])
    writer.writerow(["复核🙂", "2026-01-02", "ct-venous-5mm", "N1", "missing", "", ""])
    variants = [
        ("revised-nadir", study, (ROOT / "examples/followup.revised.csv").read_text(encoding="utf-8"), ["PR", "PR", "PD", "NE"]),
        ("PR-exact", single, track(["35.0"]), ["PR"]),
        ("PR-adjacent", single, track(["35.1"]), ["SD"]),
        ("PD-exact", single, track(["25.0", "30.0"]), ["PR", "PD"]),
        ("PD-below", single, track(["25.0", "29.9"]), ["PR", "PR"]),
        ("PD-absolute-required", single, track(["20.0", "24.9"]), ["PR", "PR"]),
        ("after-PD-gate", single, track(["25.0", "30.0", "25.0"]), ["PR", "PD", "NE"]),
        ("missing-technique-default", study, header + "v1,2026-01-02,changed,N1,too_small,,\n", ["NE"]),
        ("node-CR", study, header + "v1,2026-01-02,ct-venous-5mm,T1,absent,,\nv1,2026-01-02,ct-venous-5mm,N1,measured,9.9,\n", ["CR"]),
        ("node-not-CR", study, header + "v1,2026-01-02,ct-venous-5mm,T1,absent,,\nv1,2026-01-02,ct-venous-5mm,N1,measured,10.0,\n", ["PR"]),
        ("unicode-multiline", study, "\ufeff" + quoted.getvalue(), ["NE"]),
        ("no-followup", study, header, []),
        ("extra-precision", study, followup.replace("20.0,", "20.01,", 1), None),
        ("numeric-JSON-diameter", json.dumps(bad_number), followup, None),
        ("structural-JSON-path", study.replace('"30.0"', '"9.9"'), followup, None),
        ("multiline-date-location", study, header + 'v1,2026-01-02,ct-venous-5mm,T1,not_evaluable,,"first\nsecond"\nv2,2026-02-30,ct-venous-5mm,T1,measured,20.0,\n', None),
        ("simultaneous-parse-errors", "{", "bad header\n", None),
    ]
    with tempfile.TemporaryDirectory(prefix="lesion-browser ") as directory:
        folder = Path(directory)
        for name, profile, csv_text, categories in variants:
            profile_path, csv_path = folder / "study.json", folder / "followup.csv"
            profile_path.write_text(profile, encoding="utf-8")
            csv_path.write_bytes(csv_text.encode("utf-8"))
            args = ("--study", str(profile_path), "--input", str(csv_path))
            quality = json.loads(cli(*args, "--check-input", "--format", "json", expected=0 if categories is not None else 2).stdout)
            add({"schema_version": 1, "action": "review", "study_json": profile, "followup_csv": csv_text},
                {"quality": quality, "categories": categories, "name": name,
                 "content": cli(*args, "--format", "json").stdout if categories is not None else None})
            add({"schema_version": 1, "action": "preflight", "study_json": profile, "followup_csv": csv_text,
                 "language": "zh-CN", "format": "markdown"},
                {"quality": quality, "name": name,
                 "content": cli(*args, "--check-input", "--format", "markdown", "--lang", "zh-CN").stdout if categories is not None else None})

    # An invalid request between two identical reviews must not retain state.
    repeat = {"schema_version": 1, "action": "review", "study_json": study, "followup_csv": followup}
    add(repeat, {"content": outputs["json"], "format": "json"})
    add("{", {"request_error": "request_json"})
    add(repeat, {"content": outputs["json"], "format": "json"})
    bridge = """
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
const module = await import(pathToFileURL(process.argv[1]).href);
if (Object.keys(module).join(',') !== 'evaluate') throw new Error('Unexpected export surface');
const results = JSON.parse(readFileSync(0, 'utf8')).map(request => {
  const result = module.evaluate(request);
  if (typeof result !== 'string') throw new Error('Non-string response');
  return JSON.parse(result);
});
process.stdout.write(JSON.stringify(results));
"""
    executed = subprocess.run([node, "--input-type=module", "-e", bridge, str(output / "browser.js")],
                              input=json.dumps(requests, ensure_ascii=False), capture_output=True,
                              encoding="utf-8", env=environment, timeout=60)
    require(executed.returncode == 0, "Exported ES module failed: " + executed.stderr)
    responses = json.loads(executed.stdout)
    require(len(responses) == len(expectations), "Browser response count changed")
    for response, expected in zip(responses, expectations):
        require(response["schema_version"] == 1 and response["scope"] == "target_lesions_only", "Browser envelope scope/version changed")
        if "request_error" in expected:
            require(not response["ok"] and response["error_kind"] == "request" and response["result"] is None and
                    response["preflight"] is None and response["diagnostics"][0]["code"] == expected["request_error"], "Invalid request contract changed")
            continue
        require(response["diagnostics"] == [], "Input diagnostics escaped their preflight contract")
        if "quality" in expected:
            require(response["preflight"] == expected["quality"], "Browser/native preflight mismatch: " + expected["name"])
            require(response["ok"] == expected["quality"]["valid"], "Browser confused hints with blocking errors")
            if not response["ok"]:
                require(response["error_kind"] == "input" and response["result"] is None, "Input error produced a partial result")
                continue
        require(response["ok"] and response["error_kind"] is None, "Browser rejected valid input")
        if "template" in expected:
            files = {file["name"]: file["content"] for file in response["result"]["files"]}
            require(set(files) == {"study.json", "followup.csv", "README.md"}, "Template file contract changed")
            require(len(json.loads(files["study.json"])["targets"]) == (1 if expected["template"] == "single" else 2), "Template selection ignored")
            require(("合成靶病灶" if expected["language"] == "zh-CN" else "Synthetic") in files["README.md"], "Template language ignored")
            continue
        require(response["result"]["content"] == expected["content"], "Browser/native report bytes differ: " + expected.get("name", expected.get("format", "")))
        if "categories" in expected:
            audit = json.loads(response["result"]["content"])
            require([a["target_response"] for a in audit["assessments"]] == expected["categories"], "Boundary classifications changed")
            if expected["name"] == "node-CR":
                require(audit["assessments"][0]["sum_mm"] == "9.9", "Node CR lost actual size")
            if expected["name"] == "unicode-multiline":
                require(audit["assessments"][0]["measurements"][0]["observation"]["note"] == malicious, "Browser altered Unicode/multiline reader notes")
    require(responses[-1] == responses[-3], "Repeated calls retained state")
    passed("browser ES module exports, versioned contracts, templates and independent calls")
    passed("browser/native parity: bilingual five-format reports, exact boundaries, NE gates and located errors")
    workbench = subprocess.run([node, str(ROOT / "scripts/workbench_test.mjs"), str(output)],
                               input=json.dumps(outputs, ensure_ascii=False), capture_output=True,
                               encoding="utf-8", env=environment, cwd=str(ROOT), timeout=60)
    require(workbench.returncode == 0, "Workbench contract tests failed: " + workbench.stderr)
    workbench_result = json.loads(workbench.stdout)
    passed("workbench table edits, exact CSV round trips and strict unfinished draft contracts")
    passed("summary/full print evidence, independent input hashes, long-track fixtures and offline assets")
    return {"node_version": version, "request_count": len(requests), "native_parity_cases": len(variants),
            "build": "python scripts/build_browser.py", "module": "_build/browser/browser.js",
            "workbench": workbench_result}
