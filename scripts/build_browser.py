#!/usr/bin/env python3
"""Build a self-contained ES module and a synthetic browser smoke page."""
import os
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def package_browser():
    output = ROOT / "_build" / "browser"
    output.mkdir(parents=True, exist_ok=True)
    module = ROOT / "_build" / "js" / "release" / "build" / "browser" / "browser.js"
    shutil.copyfile(str(module), str(output / "browser.js"))
    source_map = module.with_suffix(".js.map")
    if source_map.exists():
        shutil.copyfile(str(source_map), str(output / "browser.js.map"))
    shutil.copyfile(str(ROOT / "browser" / "browser.d.ts"), str(output / "browser.d.ts"))
    for name in ("index.html", "smoke.html", "app.mjs", "workbench.mjs", "workbench.css"):
        shutil.copyfile(str(ROOT / "browser" / name), str(output / name))
    shutil.copyfile(str(ROOT / "scripts/serve_browser.py"), str(output / "serve_browser.py"))
    cases = ROOT / "examples/review-cases"
    catalogue = json.loads((cases / "expected.json").read_text(encoding="utf-8"))
    examples = {}
    for case in catalogue["cases"]:
        examples[case["id"]] = {"study_json": (cases / case["study"]).read_bytes().decode("utf-8"),
                                 "followup_csv": (cases / case["input"]).read_bytes().decode("utf-8")}
    (output / "examples.mjs").write_text("// Synthetic inputs bundled at build time.\nexport const examples = " +
                                       json.dumps(examples, ensure_ascii=False, indent=2) + ";\n", encoding="utf-8")
    (output / "package.json").write_text(json.dumps({"type": "module"}) + "\n", encoding="utf-8")
    print("Browser files: " + str(output))
    return output


def main():
    moon = shutil.which("moon")
    if moon is None:
        candidate = Path.home() / ".moon" / "bin" / ("moon.exe" if os.name == "nt" else "moon")
        if not candidate.exists():
            raise RuntimeError("MoonBit is not installed")
        moon = str(candidate)
    env = os.environ.copy()
    env["MOON_WORK"] = "off"
    env["PATH"] = str(Path(moon).parent) + os.pathsep + env.get("PATH", "")
    subprocess.run([moon, "build", "--target", "js", "--release", "--deny-warn", "browser"],
                   cwd=str(ROOT), env=env, check=True)
    package_browser()


if __name__ == "__main__":
    main()
