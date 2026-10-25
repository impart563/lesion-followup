import assert from "node:assert/strict";
import { readFileSync, writeFileSync } from "node:fs";
import { resolve, join } from "node:path";
import { pathToFileURL } from "node:url";

const folder = resolve(process.argv[2]), output = join(folder, "acceptance");
const load = name => import(pathToFileURL(join(folder, name)));
const { evaluate } = await load("browser.js");
const { invoke, makeSession } = await load("workbench.mjs");
const { examples } = await load("examples.mjs");
const { createBundle, reviewBatch, batchZip, verifyArchive, BATCH_LIMITS } = await load("delivery.mjs");
const { readZip, writeZip, ZIP_LIMITS } = await load("archive.mjs");
const { native, fixtures, invalid } = JSON.parse(readFileSync(0, "utf8"));
const checks = [];
for (const test of native) {
  const actual = createBundle(evaluate, test.sources, test.language).files;
  assert.deepEqual([...actual].sort((a, b) => a.name.localeCompare(b.name)), [...test.files].sort((a, b) => a.name.localeCompare(b.name)));
  assert.deepEqual(await readZip(writeZip(actual)), actual);
  assert((await verifyArchive(evaluate, writeZip(actual))).every(r => r.ok));
}
checks.push("four bilingual LF/Unicode-CRLF native bundles match all five files byte for byte");
for (const name of fixtures) {
  const results = await verifyArchive(evaluate, readFileSync(join(output, name)));
  assert.equal(results.length, 1); assert.equal(results[0].id, "合成报告"); assert.equal(results[0].ok, true);
}
checks.push("independent Python stored, deflated and data-descriptor ZIPs with UTF-8 names and directory entries");
for (const name of invalid) await assert.rejects(readZip(readFileSync(join(output, name))), name);
checks.push("independent unsafe paths, case/Unicode collisions, invalid UTF-8, symlink/ZIP64 and underdeclared DEFLATE rejection");

const session = await makeSession(examples.multi, examples.revised, "en");
const missing = await makeSession(null, examples.missing, "zh-CN");
const bad = await makeSession(null, { ...examples.multi, followup_csv: "invalid header\n" }, "zh-CN");
const file = (name, text) => ({ name, size: Buffer.byteLength(text), text: async () => text });
const selection = [file("修订.json", session), file("损坏.json", session.replace('"sha256": "', '"sha256": "0')),
  file("未完成.json", bad), { name: "读取失败.json", size: 1, text: async () => { throw new Error("read failed"); } }, file("缺测.json", missing)];
let events = 0;
const batch = await reviewBatch(evaluate, selection, "zh-CN", { onProgress: rows => { assert.equal(rows.length, ++events); } });
assert.deepEqual(batch.rows.map(r => r.status), ["success", "input_error", "input_error", "io_error", "success"]);
assert.equal(batch.rows[0].session.before.followup_csv, examples.multi.followup_csv);
assert.equal(batch.rows[0].session.current.followup_csv, examples.revised.followup_csv);
const audit = JSON.parse(batch.rows[4].bundle.find(f => f.name === "audit.json").content);
assert(audit.assessments.some(a => a.target_response === "NE"));
const index = JSON.parse(batch.index.find(f => f.name === "index.json").content);
assert.equal(index.success_count, 2); assert.equal(index.failure_count, 3);
assert.deepEqual(index.cases.map(c => c.report_path), ["case-001/report.html", null, null, null, "case-005/report.html"]);
const archive = batchZip(batch);
assert((await verifyArchive(evaluate, archive)).every(r => r.ok));
writeFileSync(join(output, "browser-batch.zip"), archive);
writeFileSync(join(output, "browser-bundle.zip"), writeZip(batch.rows[0].bundle));
for (const [name, text] of [["batch-revised.json", session], ["batch-missing.json", missing], ["batch-invalid.json", bad], ["batch-corrupt.json", "{}"]]) writeFileSync(join(output, name), text);
checks.push("mixed batch isolates corrupt/clinical/read failures, preserves both source pairs and accepts NE");
let cancel = false;
assert.equal(await reviewBatch(evaluate, selection, "en", { onProgress: () => { cancel = true; }, cancelled: () => cancel }), null);
await assert.rejects(reviewBatch(evaluate, [], "en"));
await assert.rejects(reviewBatch(evaluate, Array(21).fill(selection[0]), "en"));
const oversized = await reviewBatch(evaluate, [{ ...selection[0], size: BATCH_LIMITS.fileBytes + 1 }], "en");
assert.equal(oversized.rows[0].status, "input_error");
checks.push("selection cancellation and explicit case/size limits");

const good = batch.rows[0].bundle;
for (const change of [
  good.map(f => f.name === "report.html" ? { ...f, content: f.content + "changed" } : f),
  good.filter(f => f.name !== "chart.svg"), good.filter(f => f.name !== "manifest.json"),
  good.map(f => f.name === "manifest.json" ? { ...f, content: f.content.replace('"schema_version": 2', '"schema_version": 99') } : f),
  [...good, { name: "unexpected.txt", content: "extra" }],
]) assert.equal((await verifyArchive(evaluate, writeZip(change)))[0].ok, false);
const changed = good.map(f => f.name === "report.html" ? { ...f, content: f.content + "changed" } : f);
writeFileSync(join(output, "tampered-bundle.zip"), writeZip(changed));
const partiallyBad = [...batch.index, ...good.map(f => ({ ...f, name: "case-001/" + f.name })), ...changed.map(f => ({ ...f, name: "case-002/" + f.name }))];
assert.deepEqual((await verifyArchive(evaluate, writeZip(partiallyBad))).map(r => r.ok), [true, false]);
checks.push("core rejects changed artifacts, missing files/manifest, unsupported profile and extra files independently");

for (const name of ["../outside", "/absolute", "a\\b", "C:/x", "a/../b", "CON", "a/aux.txt", "a./x"]) {
  assert.throws(() => writeZip([{ name, content: "" }]));
}
assert.throws(() => writeZip([{ name: "a", content: "1" }, { name: "A", content: "2" }]));
const original = writeZip([{ name: "test", content: "hello" }]);
for (const change of [
  b => { b[34] ^= 1; }, // Stored data CRC.
  b => { b[6] = 1; }, // Encrypted/local-header mismatch.
  b => { b[30] = 88; }, // Central/local name mismatch.
  b => { new DataView(b.buffer).setUint32(b.length - 22 + 16, 0xffffffff, true); },
]) { const bytes = original.slice(); change(bytes); await assert.rejects(readZip(bytes)); }
for (const length of [0, 21, original.length - 1]) await assert.rejects(readZip(original.slice(0, length)));
const utf8 = writeZip([{ name: "test", content: "é" }]);
// A literal BOM survives transport; manifest hashes decide whether it belongs.
assert.equal((await readZip(writeZip([{ name: "test", content: "\ufefftext" }])))[0].content, "\ufefftext");
const hostilePath = original.slice();
const central = new DataView(hostilePath.buffer).getUint32(hostilePath.length - 6, true);
hostilePath.set(new TextEncoder().encode("../x"), 30); hostilePath.set(new TextEncoder().encode("../x"), central + 46);
await assert.rejects(readZip(hostilePath));
await assert.rejects(readZip(new Uint8Array(ZIP_LIMITS.bytes + 1)));
await assert.rejects(verifyArchive(evaluate, writeZip([{ name: "index.json", content: "{}" }])));
assert.equal((await readZip(utf8))[0].content, "é");
checks.push("CRC/truncation/header/path/duplicate/size rejection and strict UTF-8 transport");
for (const request of [
  { action: "bundle", ...examples.multi, format: "json" },
  { action: "verify-bundle", manifest: "{}", files: [], language: "en" },
  { action: "batch-index", cases: [] },
  { action: "batch-index", cases: [{ id: "x", status: "success", message: "", visit_count: 0.1, review_hint_count: 0 }] },
]) assert.equal(invoke(evaluate, request).error_kind, "request");
checks.push("new adapter actions retain strict per-action request contracts");
process.stdout.write(JSON.stringify({ status: "passed", native_bundle_file_comparisons: native.length * 5,
  independent_zip_fixtures: fixtures.length, rejected_independent_zip_fixtures: invalid.length, mixed_batch_cases: batch.rows.length, checks }));
