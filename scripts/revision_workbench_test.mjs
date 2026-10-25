import assert from "node:assert/strict";
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { resolve, join } from "node:path";
import { pathToFileURL } from "node:url";
import { createHash } from "node:crypto";

const folder = resolve(process.argv[2]);
const { evaluate } = await import(pathToFileURL(join(folder, "browser.js")));
const { createComparison, makeSession, readSession, invoke, sourceFingerprint } = await import(pathToFileURL(join(folder, "workbench.mjs")));
const { examples } = await import(pathToFileURL(join(folder, "examples.mjs")));
const native = JSON.parse(readFileSync(0, "utf8"));
const checks = [];
let parity = 0;
for (const test of native) {
  const result = await createComparison(evaluate, test.before, test.current, test.language);
  assert.deepEqual(result.outputs, test.outputs, test.name);
  parity += 3;
}
checks.push("three-format bilingual comparison outputs match independent native replays");
const change = await createComparison(evaluate, examples.multi, examples.revised, "zh-CN");
assert.equal(change.audit.input_changes.length, 1);
assert.deepEqual(change.audit.affected_visits.map(v => v.visit_id), ["week-4", "week-6", "week-8"]);
assert.equal(change.audit.affected_visits[1].before.target_response, "PR");
assert.equal(change.audit.affected_visits[1].after.target_response, "PD");
assert.equal(change.audit.affected_visits[2].after.target_response, "NE");
assert.equal(change.fingerprints.before, createHash("sha256").update(JSON.stringify([examples.multi.study_json, examples.multi.followup_csv])).digest("hex"));
checks.push("revision preserves changed nadir, downstream PD/NE and exact original fingerprints");

const incomplete = { ...examples.revised, followup_csv: examples.revised.followup_csv.replace("20.0,", "20.01,") };
for (const [before, current, side] of [[incomplete, examples.multi, "before"], [examples.multi, incomplete, "after"]]) {
  await assert.rejects(createComparison(evaluate, before, current, "en"), error => {
    assert.equal(error.comparisonResponse.result, null);
    assert.equal(error.comparisonResponse.preflight[side].valid, false);
    assert.equal(error.comparisonResponse.preflight[side].diagnostics[0].line, 2);
    return true;
  });
}
const incompatible = { ...examples.multi, study_json: examples.multi.study_json.replace('"30.0"', '"31.0"') };
await assert.rejects(createComparison(evaluate, examples.multi, incompatible, "en"), error => {
  assert.equal(error.comparisonResponse.error_kind, "comparison");
  assert.equal(error.comparisonResponse.diagnostics[0].code, "revision_baseline");
  return true;
});
for (const change of [{ compare_study_json: null }, { format: "csv" }, { extra: true }]) {
  const result = invoke(evaluate, { action: "compare", ...examples.multi,
    compare_study_json: examples.multi.study_json, compare_followup_csv: examples.multi.followup_csv, ...change });
  assert.equal(result.error_kind, "request"); assert.equal(result.result, null);
}
checks.push("separate preflights, incompatible baselines and strict requests never produce partial comparisons");

const fixedTime = "2026-10-25T00:00:00.000Z";
const text = await makeSession(examples.multi, examples.revised, "zh-CN", fixedTime);
const session = await readSession(text);
assert.deepEqual(session.before, examples.multi); assert.deepEqual(session.current, examples.revised);
const { sha256, ...payload } = JSON.parse(text);
assert.equal(sha256, createHash("sha256").update(JSON.stringify(payload)).digest("hex"));
const unfinished = { study_json: '{"unfinished":', followup_csv: "bad header\r\n复核🙂" };
const unfinishedText = await makeSession(null, unfinished, "en", fixedTime);
assert.deepEqual((await readSession(unfinishedText)).current, unfinished);
assert.equal((await readSession(unfinishedText)).before, null);
const retained = { ...examples.multi };
const pending = makeSession(examples.multi, retained, "en", fixedTime);
retained.followup_csv = "changed after save began";
assert.deepEqual((await readSession(await pending)).current, examples.multi);
checks.push("portable sessions retain both original pairs, unfinished Unicode text and a stable payload snapshot");

for (const altered of [{ ...JSON.parse(text), language: "en" },
  { ...JSON.parse(text), before: examples.revised }, { ...JSON.parse(text), schema_version: 99 },
  { ...JSON.parse(text), extra: true }, { ...JSON.parse(text), sha256: "0".repeat(64) },
  { ...JSON.parse(text), saved_at: "2026-02-31T00:00:00.000Z" },
  { ...JSON.parse(text), current: { ...examples.multi, extra: true } }]) {
  await assert.rejects(readSession(JSON.stringify(altered)));
}
for (const bad of ["{", "[]", "null", "{}"]) await assert.rejects(readSession(bad));
const restored = await readSession(text);
assert.deepEqual((await createComparison(evaluate, restored.before, restored.current, restored.language)).outputs, change.outputs);
checks.push("tampered or incompatible sessions are rejected; valid restoration recomputes the same evidence");
const expected = JSON.parse(readFileSync("examples/review-cases/expected.json", "utf8"));
for (const test of expected.cases) {
  assert.equal(examples[test.id].study_json, readFileSync(resolve("examples/review-cases", test.study), "utf8"));
  assert.equal(examples[test.id].followup_csv, readFileSync(resolve("examples/review-cases", test.input), "utf8"));
  const response = invoke(evaluate, { action: "review", ...examples[test.id] });
  assert.deepEqual(JSON.parse(response.result.content).assessments.map(a => a.target_response), test.expected.map(a => a.target_response));
}
checks.push("bundled examples match the original synthetic files and independent hand calculations");
const fixture = join(folder, "acceptance"); mkdirSync(fixture, { recursive: true });
writeFileSync(join(fixture, "review-session.json"), text);
writeFileSync(join(fixture, "corrupt-session.json"), JSON.stringify({ ...JSON.parse(text), current: examples.multi }));
writeFileSync(join(fixture, "unfinished-session.json"), unfinishedText);
writeFileSync(join(fixture, "incompatible-session.json"), await makeSession(examples.multi, incompatible, "zh-CN", fixedTime));
process.stdout.write(JSON.stringify({ checks, native_format_comparisons: parity, bundled_examples: 4 }));
