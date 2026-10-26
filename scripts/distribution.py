"""Version discovery and consumer checks against an extracted Mooncakes candidate."""
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]


def module_version():
    return re.search(r'^version\s*=\s*"([^"]+)"', (ROOT / "moon.mod").read_text(encoding="utf-8"), re.M).group(1)


def verify_candidate_consumer(package, moon, environment):
    """No local checkout link: the library is read only from the packaged archive."""
    with tempfile.TemporaryDirectory(prefix="lesion-candidate ") as directory:
        base = Path(directory)
        module = base / "module"
        module.mkdir()
        with ZipFile(package) as archive:
            for entry in archive.infolist():
                relative = Path(entry.filename.replace("\\", "/"))
                if relative.is_absolute() or ".." in relative.parts or ":" in str(relative):
                    raise AssertionError("unsafe archive member")
                target = module / relative
                if entry.is_dir():
                    target.mkdir(parents=True, exist_ok=True)
                else:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(archive.read(entry))
        consumer = base / "consumer"
        consumer.mkdir()
        for name in ("moon.mod", "moon.pkg", "main.mbt"):
            shutil.copyfile(str(ROOT / "examples/downstream-consumer" / name), str(consumer / name))
        workspace = base / "moon.work"
        workspace.write_text('members = ["module", "consumer"]\n', encoding="utf-8")
        env = dict(environment, MOON_WORK=str(workspace))
        outputs = {}
        commands = []
        for backend in ("wasm", "wasm-gc", "js", "native"):
            result = subprocess.run([moon, "run", "--target", backend, "."], cwd=str(consumer), env=env,
                                    capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=180)
            if result.returncode or "Downstream consumer smoke passed: node CR retains 9.9 mm" not in result.stdout or "Downstream integration passed: text input, preflight, target-only NE, bilingual bundles and tamper rejection" not in result.stdout:
                raise RuntimeError("candidate consumer " + backend + "\n" + result.stdout + result.stderr)
            outputs[backend] = "passed"
            commands.append({"command": "moon run --target " + backend + " .", "cwd": "<extracted-candidate-consumer>", "exit_code": result.returncode})
        return {"source": "extracted Mooncakes candidate; no checkout library link", "backends": outputs,
                "checks": ["typed root-facade construction", "text template/parsing/preflight/replay", "invalid input and valid NE remain separate", "bilingual native bundles and tamper rejection"],
                "commands": commands,
                "registry_install": "not performed by this check; extracted candidate only"}
