import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { resolve, join } from "node:path";
import { pathToFileURL } from "node:url";

const folder = resolve(process.argv[2]), output = join(folder, "acceptance");
const load = name => import(pathToFileURL(join(folder, name)));
const { evaluate } = await load("browser.js");
const { examples } = await load("examples.mjs");
const { createHandoff, readHandoff, createHandoffReceiver, HANDOFF_LIMITS } = await load("handoff.mjs");
const { createReviewNotes, updateReviewNotes, encodeReviewNotes } = await load("review-notes.mjs");
const { readZip, writeZip } = await load("archive.mjs");
const { createBundle, verifyArchive } = await load("delivery.mjs");
const { makeSession, sourceFingerprint } = await load("workbench.mjs");
const input = JSON.parse(readFileSync(0, "utf8"));
if (process.argv.includes("--external")) {
  for (const name of input.fixtures) {
    const result = await readHandoff(evaluate, readFileSync(join(output, name)));
    assert.equal(result.summary.has_reference, true); assert.equal(result.summary.notes.reviewed, 1);
  }
  process.stdout.write(JSON.stringify({ status: "passed", count: input.fixtures.length }));
  process.exit(0);
}
const at = "2026-10-25T00:00:00.000Z", later = "2026-10-25T01:00:00.000Z", checks = [];
const hash = text => createHash("sha256").update(text).digest("hex");
let comparisons = 0;
for (const [i, test] of input.native.entries()) {
  const zip = await createHandoff(evaluate, null, test.sources, test.language, null, at);
  const received = await readHandoff(evaluate, zip);
  assert.deepEqual(received.session.current, test.sources);
  assert.equal(received.summary.language, test.language); assert.equal(received.notes, null);
  const files = await readZip(zip);
  for (const expected of test.files) {
    assert.equal(files.find(f => f.name === "report/"+expected.name).content, expected.content);
    comparisons++;
  }
  writeFileSync(join(output, `handoff-native-${i}.zip`), zip);
}
checks.push("four bilingual LF/Unicode-CRLF handoffs match twenty independent native report files");

let notes = await createReviewNotes(evaluate, examples.revised, at);
notes = updateReviewNotes(notes, { id: notes.items[0].id, status: "reviewed", note: "已核对修订后的合成记录；后续变化保留进一步复核。\n备注 Ω 😀" }, later);
const good = await createHandoff(evaluate, examples.multi, examples.revised, "zh-CN", notes, at);
const withoutNotes = await createHandoff(evaluate, null, examples.multi, "en", null, at);
const received = await readHandoff(evaluate, good);
assert.deepEqual(received.session.before, examples.multi); assert.deepEqual(received.session.current, examples.revised);
assert.deepEqual(received.notes, notes); assert.equal(received.summary.notes.reviewed, 1);
assert.equal(received.summary.source_sha256, await sourceFingerprint(examples.revised));
assert.equal(received.summary.file_count, 8);
assert.deepEqual(good, await createHandoff(evaluate, examples.multi, examples.revised, "zh-CN", notes, at));
const unfinishedReference = { study_json: "unfinished reference", followup_csv: "" };
assert.deepEqual((await readHandoff(evaluate, await createHandoff(evaluate, unfinishedReference, examples.multi, "en", null, at))).session.before, unfinishedReference);
await assert.rejects(createHandoff(evaluate, null, examples.multi, "zh-CN", notes, at));
await assert.rejects(createHandoff(evaluate, null, { ...examples.multi, followup_csv: "bad header\n" }, "en", null, at));
await assert.rejects(createHandoff(evaluate, null, { ...examples.multi, study_json: examples.multi.study_json + " ".repeat(HANDOFF_LIMITS.sessionBytes) }, "en", null, at));
await assert.rejects(verifyArchive(evaluate, good), /检查交接包/);
checks.push("fixed-time export is deterministic and preserves both versions, note states, Unicode and exact binding");

async function repack(files) {
  const payload = files.filter(f => f.name !== "handoff.json");
  const manifest = JSON.parse(files.find(f => f.name === "handoff.json").content);
  manifest.files = payload.map(f => ({ name: f.name, byte_length: Buffer.byteLength(f.content), sha256: hash(f.content) }));
  // Keep the version-1 canonical order, independently of the archive's order.
  const order = ["session.json", "review-notes.json", "report/report.html", "report/audit.json", "report/audit.csv", "report/chart.svg", "report/manifest.json"];
  manifest.files.sort((a,b) => order.indexOf(a.name)-order.indexOf(b.name));
  delete manifest.sha256; manifest.sha256 = hash(JSON.stringify(manifest));
  return writeZip([...payload, { name: "handoff.json", content: JSON.stringify(manifest) }]);
}
const files = await readZip(good), bad = [];
bad.push(writeZip(files.filter(f => f.name !== "report/chart.svg")));
bad.push(writeZip([...files, { name: "unexpected.txt", content: "extra" }]));
bad.push(writeZip(files.map(f => f.name === "report/report.html" ? { ...f, content: f.content + "changed" } : f)));
for (const mutate of [m => { m.schema_version=2; }, m => { m.extra=true; }, m => { m.scope="overall_response"; },
  m => { m.sha256="0".repeat(64); }, m => { m.files[0].byte_length=0.5; }, m => { m.files.push(m.files[0]); }]) {
  const changed = structuredClone(files), item = changed.find(f => f.name === "handoff.json"), m = JSON.parse(item.content);
  mutate(m); item.content = JSON.stringify(m); bad.push(writeZip(changed));
}
const changedSession = files.map(f => f.name === "session.json" ? { ...f, content: f.content.replace("synthetic-target-followup", "changed-target-followup") } : f);
bad.push(await repack(changedSession));
const wrongNotes = await encodeReviewNotes(await createReviewNotes(evaluate, examples.missing, at));
bad.push(await repack(files.map(f => f.name === "review-notes.json" ? { ...f, content: wrongNotes } : f)));
// A complete, internally valid bundle from another current track still fails replay binding.
const unrelated = createBundle(evaluate, examples.multi, "zh-CN").files;
const mixed = await repack(files.map(f => f.name.startsWith("report/") ? { ...f, content: unrelated.find(r => "report/"+r.name === f.name).content } : f));
await assert.rejects(readHandoff(evaluate, mixed), e => e.code === "handoff_replay"); bad.push(mixed);
const otherLanguage = createBundle(evaluate, examples.revised, "en").files;
const mixedLanguage = await repack(files.map(f => f.name.startsWith("report/") ? { ...f, content: otherLanguage.find(r => "report/"+r.name === f.name).content } : f));
await assert.rejects(readHandoff(evaluate, mixedLanguage), e => e.code === "handoff_replay"); bad.push(mixedLanguage);
for (const zip of bad) await assert.rejects(readHandoff(evaluate, zip));
writeFileSync(join(output, "handoff-tampered.zip"), bad[2]);
writeFileSync(join(output, "handoff-mixed-report.zip"), mixed);
const reversed = [...files].reverse();
assert.deepEqual((await readHandoff(evaluate, writeZip(reversed))).summary, received.summary);
function reordered(value) {
  return Array.isArray(value) ? value.map(reordered) : value && typeof value === "object" ?
    Object.fromEntries(Object.entries(value).reverse().map(([k,v]) => [k,reordered(v)])) : value;
}
const reorderedManifest = files.map(f => f.name === "handoff.json" ? { ...f, content: JSON.stringify(reordered(JSON.parse(f.content))) } : f);
assert.deepEqual((await readHandoff(evaluate, writeZip(reorderedManifest))).summary, received.summary);
checks.push("missing/extra/tampered files, strict manifests, nested session/note mismatch and valid-but-unrelated reports are rejected");

let revision = 0, applied = [], target = { current: examples.multi, notes: { marker: "existing" } };
const receiver = createHandoffReceiver(evaluate, () => revision, snapshot => {
  applied.push(snapshot); target = { current: snapshot.session.current, notes: snapshot.notes };
});
const original = structuredClone(target);
for (const zip of bad) { await assert.rejects(receiver.inspect(async () => zip)); assert.deepEqual(target, original); assert.equal(receiver.canLoad(), false); }
const preview = await receiver.inspect(async () => good); preview.study_id = "changed preview";
assert.deepEqual(target, original); assert.equal(receiver.canLoad(), true);
revision++; assert.equal(receiver.canLoad(), false); assert.throws(() => receiver.load()); assert.deepEqual(target, original);
let release;
const pending = receiver.inspect(() => new Promise(resolve => { release = resolve; }));
const pendingRejected = assert.rejects(pending, e => e.code === "handoff_stale");
revision++; release(good); await pendingRejected; assert.equal(applied.length, 0);
let releaseFirst;
const first = receiver.inspect(() => new Promise(resolve => { releaseFirst = resolve; }));
const firstRejected = assert.rejects(first, e => e.code === "handoff_stale");
await receiver.inspect(async () => good); releaseFirst(withoutNotes); await firstRejected;
receiver.load(); assert.equal(applied.length, 1); assert.deepEqual(target.notes, notes);
assert.notEqual(applied[0].summary.study_id, "changed preview");
await receiver.inspect(async () => withoutNotes); receiver.load(); assert.equal(target.notes, null);
await receiver.inspect(async () => good); receiver.invalidate(); assert.throws(() => receiver.load());
await assert.rejects(receiver.inspect(async () => { throw new Error("read failure"); }));
assert.equal(receiver.canLoad(), false);
checks.push("receiver applies only validated snapshots and rejects newer edits, replacement files, concurrent inspections and read failures");
writeFileSync(join(output, "handoff-with-notes.zip"), good);
writeFileSync(join(output, "handoff-without-notes.zip"), withoutNotes);
writeFileSync(join(output, "handoff-source-session.json"), await makeSession(examples.multi, examples.revised, "zh-CN", at));
process.stdout.write(JSON.stringify({ status: "passed", native_report_file_comparisons: comparisons, rejected_archives: bad.length,
  receiver_applies: applied.length, checks }));
