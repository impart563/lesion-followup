import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { resolve, join } from "node:path";
import { pathToFileURL } from "node:url";

const folder = resolve(process.argv[2]), output = join(folder, "acceptance");
const load = name => import(pathToFileURL(join(folder, name)));
const { evaluate } = await load("browser.js");
const { invoke, makeSession } = await load("workbench.mjs");
const { examples } = await load("examples.mjs");
const { createReviewNotes, updateReviewNotes, encodeReviewNotes, readReviewNotes, reviewProgress,
  renderReviewNotes, REVIEW_LIMITS } = await load("review-notes.mjs");
const native = JSON.parse(readFileSync(0, "utf8")), checks = [];
const at = "2026-10-25T00:00:00.000Z", later = "2026-10-25T01:00:00.000Z";
for (const test of native) {
  const record = await createReviewNotes(evaluate, test.sources, at);
  assert.deepEqual(record.items.map(item => item.hint), test.preflight.review_hints);
  assert.equal(record.context.visit_count, test.preflight.visit_count);
  assert.equal(record.context.source_sha256, createHash("sha256").update(JSON.stringify([test.sources.study_json, test.sources.followup_csv])).digest("hex"));
}
checks.push("five native preflights retain every hint, location and exact source fingerprint");
const sources = Object.freeze({ ...native.find(test => test.name === "multiple-hints").sources });
const clinicalBefore = invoke(evaluate, { action: "review", ...sources, format: "json" });
let record = await createReviewNotes(evaluate, sources, at);
assert(record.items.length > 1);
const initial = structuredClone(record);
const malicious = '<script>alert(1)</script>\n[x](javascript:alert(1))\n![image](https://example.invalid/a)\n# Heading\n```\n备注 Ω 😀';
record = updateReviewNotes(record, { id: record.items[0].id, status: "reviewed", note: malicious }, later);
record = updateReviewNotes(record, { summary_note: "已对照原始记录，采集差异仍需进一步确认。" }, later);
assert.equal(initial.items[0].status, "pending");
assert.equal(initial.items[0].note, "");
assert.deepEqual(reviewProgress(record), { total: record.items.length, reviewed: 1, pending: record.items.length - 1 });
assert.deepEqual(invoke(evaluate, { action: "review", ...sources, format: "json" }), clinicalBefore);
assert.deepEqual(invoke(evaluate, { action: "preflight", ...sources }).preflight.review_hints, initial.items.map(i => i.hint));
checks.push("viewing statuses and notes do not mutate source pairs, core hints or clinical results");

const text = await encodeReviewNotes(record), parsed = JSON.parse(text);
const { sha256, ...payload } = parsed;
assert.equal(sha256, createHash("sha256").update(JSON.stringify(payload)).digest("hex"));
assert.deepEqual(await readReviewNotes(text, evaluate, sources), record);
function reordered(value) {
  return Array.isArray(value) ? value.map(reordered) : value && typeof value === "object" ?
    Object.fromEntries(Object.entries(value).reverse().map(([k, v]) => [k, reordered(v)])) : value;
}
assert.deepEqual(await readReviewNotes(JSON.stringify(reordered(parsed)), evaluate, sources), record);
assert.equal((await readReviewNotes(text, evaluate, sources)).items[0].note, malicious);
await assert.rejects(readReviewNotes(text, evaluate, { ...sources, study_json: sources.study_json + " " }));
await assert.rejects(readReviewNotes(text, evaluate, examples.multi));
await assert.rejects(createReviewNotes(evaluate, { ...sources, followup_csv: "bad header\n" }));
// Even a recomputed unkeyed digest cannot bind a changed hint to the current core output.
const forged = structuredClone(parsed); forged.items[0].hint.message = "forged";
const { sha256: ignored, ...forgedPayload } = forged;
forged.sha256 = createHash("sha256").update(JSON.stringify(forgedPayload)).digest("hex");
await assert.rejects(readReviewNotes(JSON.stringify(forged), evaluate, sources));
checks.push("portable notes verify independent hashes, raw-text binding and recomputed native hint identity");

for (const mutate of [v => { v.schema_version = 99; }, v => { v.extra = true; }, v => { v.context.extra = true; },
  v => { v.items[0].extra = true; }, v => { v.items[0].hint.extra = true; }, v => { v.items[0].status = "approved"; },
  v => { v.items[0].id = "unknown"; }, v => { v.updated_at = "2026-02-30T00:00:00.000Z"; },
  v => { v.items[0].updated_at = "2027-01-01T00:00:00.000Z"; }, v => { v.sha256 = "0".repeat(64); },
  v => { v.context.visit_count = 1.2; }, v => { v.items[0].hint.line = -1; }, v => { v.summary_note = "a".repeat(6001); }]) {
  const value = structuredClone(parsed); mutate(value);
  await assert.rejects(readReviewNotes(JSON.stringify(value), evaluate, sources));
}
await assert.rejects(readReviewNotes("{", evaluate, sources));
await assert.rejects(readReviewNotes(" ".repeat(REVIEW_LIMITS.bytes + 1), evaluate, sources));
assert.throws(() => updateReviewNotes(record, { id: "missing", status: "pending", note: "" }));
assert.throws(() => updateReviewNotes(record, { id: record.items[0].id, status: "reviewed", note: "a".repeat(2001) }));
assert.equal(updateReviewNotes(record, { id: record.items[0].id, status: "reviewed", note: "😀".repeat(1000) }).items[0].note.length, 2000);
assert.equal(updateReviewNotes(record, { summary_note: "clock" }, at).updated_at, later);
await assert.rejects(createReviewNotes(() => JSON.stringify({ ok: true, preflight: { valid: true,
  review_hints: Array(1001).fill(initial.items[0].hint) }, result: { study: {} } }), sources, at));
checks.push("strict fields, timestamps, statuses, lengths and monotonic local modification times");

const noHint = invoke(evaluate, { action: "template", template: "single" }).result.files;
const emptySources = { study_json: noHint.find(f => f.name === "study.json").content,
  followup_csv: noHint.find(f => f.name === "followup.csv").content };
const empty = await createReviewNotes(evaluate, emptySources, at);
// The single template's original track has no core hints.
assert.equal(empty.items.length, 0);
assert.deepEqual(reviewProgress(empty), { total: 0, reviewed: 0, pending: 0 });
assert.equal((await readReviewNotes(await encodeReviewNotes(empty), evaluate, emptySources)).items.length, 0);
checks.push("zero-hint records retain an independent summary without inventing findings");

for (const language of ["en", "zh-CN"]) {
  for (const format of ["html", "markdown"]) {
    const rendered = renderReviewNotes(record, format, language);
    assert(rendered.includes(record.context.source_sha256));
    assert(rendered.includes(language === "en" ? "Pending" : "待核查"));
    assert(rendered.includes(language === "en" ? "Viewed" : "已查看"));
    assert(!rendered.includes('<script>alert(1)</script>'));
    if (format === "markdown") assert(!rendered.includes('[x](javascript:alert(1))'));
    const literal = format === "markdown" ? rendered.replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n))) : rendered;
    for (const item of record.items) assert(literal.includes(item.hint.code));
    writeFileSync(join(output, `review-notes.${language}.${format === "html" ? "html" : "md"}`), rendered);
  }
}
assert.throws(() => renderReviewNotes(record, "pdf"));
writeFileSync(join(output, "review-notes.json"), text);
writeFileSync(join(output, "review-notes-session.json"), await makeSession(null, sources, "zh-CN", at));
writeFileSync(join(output, "corrupt-review-notes.json"), text.replace('"sha256": "', '"sha256": "0'));
const wrongSources = { ...sources, study_json: sources.study_json + " " };
writeFileSync(join(output, "wrong-input-review-notes.json"), await encodeReviewNotes(await createReviewNotes(evaluate, wrongSources, at)));
checks.push("bilingual documents retain pending work, literal notes and scope without active content");
process.stdout.write(JSON.stringify({ status: "passed", native_preflight_cases: native.length, bilingual_documents: 4,
  hint_count: record.items.length, independent_node_payload_hash: true, checks }));
