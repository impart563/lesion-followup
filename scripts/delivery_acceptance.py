"""Browser batch/ZIP interoperability, with independently generated native bundles."""
import io
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
from zipfile import ZipFile, ZipInfo, ZIP_STORED, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parents[1]


class StreamingBuffer(io.BytesIO):
    def seekable(self):
        return False

    def seek(self, *args):
        raise io.UnsupportedOperation("streaming fixture")


def verify_delivery(cli, environment, passed):
    output = ROOT / "_build/browser/acceptance"
    output.mkdir(parents=True, exist_ok=True)
    native = []
    with tempfile.TemporaryDirectory(prefix="browser-delivery ") as temporary:
        folder = Path(temporary)
        for profile in ("lf", "unicode-crlf"):
            study = (ROOT / "examples/study.json").read_text(encoding="utf-8")
            csv = (ROOT / "examples/followup.csv").read_text(encoding="utf-8")
            if profile == "unicode-crlf":
                value = json.loads(study)
                value["study_id"] = "合成复核 Ω"
                study = json.dumps(value, ensure_ascii=False, indent=2) + "\n"
                study, csv = (text.replace("\n", "\r\n") for text in (study, csv))
            study_path, csv_path = folder / "study.json", folder / "followup.csv"
            study_path.write_bytes(study.encode("utf-8"))
            csv_path.write_bytes(csv.encode("utf-8"))
            for language in ("en", "zh-CN"):
                bundle = folder / (profile + "-" + language)
                cli("--study", str(study_path), "--input", str(csv_path), "--bundle", str(bundle), "--lang", language)
                files = [{"name": p.name, "content": p.read_bytes().decode("utf-8")} for p in sorted(bundle.iterdir())]
                native.append({"profile": profile, "language": language, "sources": {"study_json": study, "followup_csv": csv}, "files": files})
        fixtures = []
        for name, method, streaming in (("native-stored.zip", ZIP_STORED, False),
                                        ("native-deflated.zip", ZIP_DEFLATED, False),
                                        ("native-streamed.zip", ZIP_DEFLATED, True)):
            buffer = StreamingBuffer() if streaming else io.BytesIO()
            with ZipFile(buffer, "w", compression=method) as archive:
                archive.comment = b"independent Python ZIP fixture"
                archive.writestr("合成报告/", b"")
                for file in native[-1]["files"]:
                    archive.writestr("合成报告/" + file["name"], file["content"].encode("utf-8"))
            (output / name).write_bytes(buffer.getvalue())
            fixtures.append(name)
        invalid = []
        for name, entries in (("unsafe-path.zip", [("../report.html", b"text")]),
                              ("case-collision.zip", [("audit.json", b"a"), ("AUDIT.JSON", b"b")]),
                              ("unicode-collision.zip", [("é", b"a"), ("e\u0301", b"b")]),
                              ("invalid-utf8.zip", [("audit.json", b"\xff")])):
            with ZipFile(output / name, "w") as archive:
                for path, data in entries:
                    archive.writestr(path, data)
            invalid.append(name)
        link = ZipInfo("report.html")
        link.create_system = 3
        link.external_attr = 0o120777 << 16
        with ZipFile(output / "symlink.zip", "w") as archive:
            archive.writestr(link, b"target")
        invalid.append("symlink.zip")
        zip64 = ZipInfo("audit.json")
        zip64.extra = b"\x01\x00\x00\x00"
        with ZipFile(output / "zip64-extra.zip", "w") as archive:
            archive.writestr(zip64, b"{}")
        invalid.append("zip64-extra.zip")
        buffer = io.BytesIO()
        with ZipFile(buffer, "w", compression=ZIP_DEFLATED) as archive:
            archive.writestr("test", b"A" * 65536)
        bomb = bytearray(buffer.getvalue())
        central = bomb.index(b"PK\x01\x02")
        bomb[22:26] = (1).to_bytes(4, "little")
        bomb[central + 24:central + 28] = (1).to_bytes(4, "little")
        (output / "underdeclared-deflate.zip").write_bytes(bomb)
        invalid.append("underdeclared-deflate.zip")
        result = subprocess.run([shutil.which("node", path=environment["PATH"]), "scripts/delivery_workbench_test.mjs", "_build/browser"],
                                input=json.dumps({"native": native, "fixtures": fixtures, "invalid": invalid}, ensure_ascii=False),
                                capture_output=True, text=True, encoding="utf-8", env=environment, cwd=str(ROOT), timeout=180)
        if result.returncode:
            raise RuntimeError("browser batch/ZIP acceptance failed:\n" + result.stderr)
        record = json.loads(result.stdout)
        # Only our generated names are extracted; no user-supplied archive is extracted.
        verified = 0
        for name in ("browser-bundle.zip", "browser-batch.zip"):
            with ZipFile(output / name) as archive:
                if archive.testzip() is not None:
                    raise AssertionError("browser ZIP CRC mismatch")
                entries = archive.namelist()
                if name == "browser-batch.zip":
                    index = json.loads(archive.read("index.json"))
                    if (index["success_count"], index["failure_count"]) != (2, 3):
                        raise AssertionError("exported index differs from mixed batch")
                    prefixes = [case["id"] + "/" for case in index["cases"] if case["status"] == "success"]
                else:
                    prefixes = [""]
                for i, prefix in enumerate(prefixes):
                    target = folder / (name + "-" + str(i))
                    target.mkdir()
                    expected = {prefix + item for item in ("manifest.json", "report.html", "audit.json", "audit.csv", "chart.svg")}
                    if not expected.issubset(entries):
                        raise AssertionError("ZIP missing native report files")
                    for entry in expected:
                        (target / entry[len(prefix):]).write_bytes(archive.read(entry))
                    cli("--verify-bundle", str(target), "--format", "json")
                    verified += 1
        record["native_verified_exported_bundles"] = verified
    passed("browser batch: mixed sessions, independent failures, valid NE, cancellation and core index rendering")
    passed("browser ZIP delivery: bilingual native bytes, Python stored/DEFLATE/streamed import and native export verification")
    passed("browser archive integrity: tamper/missing/profile rejection, CRC, paths, duplicate entries and bounded decoding")
    return record
