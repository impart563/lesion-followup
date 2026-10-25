"""Browser comparison / session checks using native CLI outputs as the reference."""
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def verify_revisions(cli, environment, passed):
    study = (ROOT / "examples/study.json").read_text(encoding="utf-8")
    original = (ROOT / "examples/followup.csv").read_text(encoding="utf-8")
    native = []
    cases = (("changed-nadir", "examples/followup.revised.csv"), ("identical", "examples/followup.csv"),
             ("missing", "examples/review-cases/missing.csv"), ("technique", "examples/review-cases/technique.csv"))
    for name, path in cases:
        for language in ("en", "zh-CN"):
            args = ("--study", "examples/study.json", "--input", path,
                    "--compare-study", "examples/study.json", "--compare-input", "examples/followup.csv", "--lang", language)
            native.append({"name": name, "language": language,
                           "before": {"study_json": study, "followup_csv": original},
                           "current": {"study_json": study, "followup_csv": (ROOT / path).read_text(encoding="utf-8")},
                           "outputs": {fmt: cli(*args, "--format", fmt).stdout for fmt in ("json", "markdown", "html")}})
    result = subprocess.run([shutil.which("node", path=environment["PATH"]), "scripts/revision_workbench_test.mjs", "_build/browser"],
                            input=json.dumps(native, ensure_ascii=False), capture_output=True, text=True, encoding="utf-8",
                            env=environment, cwd=str(ROOT), timeout=120)
    if result.returncode:
        raise RuntimeError("comparison/session acceptance failed:\n" + result.stderr)
    record = json.loads(result.stdout)
    passed("browser revisions: bilingual native parity, exact source pairs, independent diagnostics and baseline guards")
    passed("portable review sessions: independent hashes, unfinished inputs, tamper rejection and restored evidence")
    return record
