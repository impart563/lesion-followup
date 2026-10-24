import assert from "node:assert/strict";
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { pathToFileURL } from "node:url";
import { resolve, join } from "node:path";
import { createHash } from "node:crypto";

const output = resolve(process.argv[2]);
const { evaluate } = await import(pathToFileURL(join(output, "browser.js")));
const { COLUMNS, DRAFT_KEY, invoke, serializeTable, rowLocations, makeDraft, readDraft, createReview, printDocument, printFragment } = await import(pathToFileURL(join(output, "workbench.mjs")));
const expected = JSON.parse(readFileSync(0, "utf8"));
const sources = { study_json: readFileSync("examples/study.json", "utf8"), followup_csv: readFileSync("examples/followup.csv", "utf8") };
const checks = [];
const check = name => checks.push(name);
const load = input => invoke(evaluate, { action: "editor", ...input });
const review = (input, format = "json") => invoke(evaluate, { action: "review", ...input, format });
const decode = load(sources);
assert.equal(decode.ok, true);
assert.equal(decode.preflight.valid, true);
assert.equal(decode.result.rows.length, 8);
const canonical = serializeTable(decode.result);
for (const [format, text] of Object.entries(expected)) assert.equal(review(canonical, format).result.content, text);
check("table import/export preserves all five native CLI reports");

const edited = structuredClone(decode.result);
edited.rows[2][5] = "9.0";
const revised = serializeTable(edited);
const audit = JSON.parse(review(revised).result.content);
assert.deepEqual(audit.assessments.map(a => a.target_response), ["PR", "PR", "PD", "NE"]);
assert.equal(audit.assessments[2].prior_nadir_mm, "19.0");
assert.deepEqual(load(revised).result, edited);
edited.rows[2][5] = "9.01";
const invalid = serializeTable(edited);
assert.equal(load(invalid).ok, true);
assert.equal(load(invalid).preflight.valid, false);
assert.equal(review(invalid).ok, false);
assert.equal(review(invalid).result, null);
assert.equal(review(invalid).preflight.diagnostics[0].field, "diameter_mm");
check("measurement edits replay the nadir; editable precision errors still block reports");

const note = '<script>alert("复核")</script>, "quoted"\r\n第二行🙂\r第三行';
const row = ["v1", "2026-01-02", "ct-venous-5mm", "T1", "not_evaluable", "", note];
const missing = ["v1", "2026-01-02", "ct-venous-5mm", "N1", "missing", "", ""];
const quotedModel = { study: decode.result.study, rows: [row, missing] };
const quoted = serializeTable(quotedModel);
quoted.followup_csv = "\ufeff" + quoted.followup_csv.replace(/(?<!\r)\n/g, "\r\n");
const parsedQuoted = load(quoted);
assert.equal(parsedQuoted.ok, true);
assert.equal(parsedQuoted.result.rows[0][6], note);
assert.deepEqual(rowLocations([row, missing]), [{ start: 2, end: 4 }, { start: 5, end: 5 }]);
const ne = JSON.parse(review(serializeTable(parsedQuoted.result)).result.content);
assert.equal(ne.assessments[0].target_response, "NE");
assert.equal(ne.assessments[0].sum_mm, null);
assert.equal(ne.assessments[0].measurements[0].observation.note, note);
check("MoonBit decodes quoted BOM/CRLF/Unicode CSV; missing observations and notes survive");

const structural = structuredClone(decode.result);
structural.study.targets[0].baseline_mm = "9.9";
assert.equal(load(serializeTable(structural)).ok, true);
assert.equal(load(serializeTable(structural)).preflight.valid, false);
for (const csv of ["bad\n", COLUMNS.join(",") + '\n"open', COLUMNS.join(",") + "\nv1\n"]) {
  const response = load({ ...sources, followup_csv: csv });
  assert.equal(response.ok, false); assert.equal(response.result, null);
}
check("structural values remain editable while malformed table shapes are rejected");

const draftText = makeDraft(invalid, "zh-CN", "2026-10-25T00:00:00.000Z");
const draft = readDraft(draftText);
assert.deepEqual({ study_json: draft.study_json, followup_csv: draft.followup_csv }, invalid);
assert.equal(draft.language, "zh-CN");
for (const change of [{ schema_version: 99 }, { kind: "other" }, { saved_at: "invalid" }, { language: "zh" }, { study_json: {} }, { followup_csv: null }, { extra: true }]) {
  assert.throws(() => readDraft(JSON.stringify({ ...draft, ...change })));
}
for (const bad of ["{", "[]", "null", "{}"]) assert.throws(() => readDraft(bad));
assert.match(DRAFT_KEY, /^impart563\.lesion-followup\./);
check("strict draft containers preserve unfinished text and reject corrupt or incompatible versions");

const fullReview = await createReview(evaluate, revised, "zh-CN");
assert.equal(fullReview.fingerprint, createHash("sha256").update(JSON.stringify([revised.study_json, revised.followup_csv])).digest("hex"));
const maliciousReview = await createReview(evaluate, serializeTable(quotedModel), "zh-CN");
for (const mode of ["summary", "full"]) {
  const html = printDocument(fullReview, mode);
  assert.ok(html.includes(fullReview.fingerprint));
  assert.ok(html.includes('href="#complete-evidence"'));
  assert.ok(html.includes('id="complete-evidence"'));
  for (let i = 0; i < 4; i++) assert.ok(html.includes(`id="visit-${i}"`) && html.includes(`href="#visit-${i}"`));
  assert.ok(html.includes("19.0") && html.includes("靶病灶"));
  assert.ok(!/<(?:script|iframe|img|link)\b/i.test(html));
  assert.ok(printFragment(html).startsWith("<style>:host"));
  const unsafe = printDocument(maliciousReview, mode);
  assert.ok(!unsafe.includes("<script>"));
  assert.ok(unsafe.includes("&lt;script&gt;"));
}
assert.throws(() => printDocument(fullReview, "other"));
assert.throws(() => printFragment("broken"));
check("two print layouts link to complete escaped evidence and share an independently verified input hash");

const fixtureDir = join(output, "acceptance"); mkdirSync(fixtureDir, { recursive: true });
const longModel = { study: structuredClone(decode.result.study), rows: [] };
longModel.study.study_id = "synthetic-long-review";
for (let i = 0; i < 36; i++) {
  const date = new Date(Date.UTC(2026, 0, 2 + i)).toISOString().slice(0, 10);
  longModel.rows.push([`visit-${i + 1}`, date, "ct-venous-5mm", "T1", i === 14 ? "not_evaluable" : "measured", i === 14 ? "" : "20.0", i === 14 ? "人工复核,\"多行说明\"\n" + "长说明".repeat(90) : ""]);
  longModel.rows.push([`visit-${i + 1}`, date, "ct-venous-5mm", "N1", "measured", "15.0", ""]);
}
const longSources = serializeTable(longModel);
const longReview = await createReview(evaluate, longSources, "zh-CN");
assert.equal(longReview.audit.assessments.length, 36);
assert.equal(longReview.audit.assessments[14].target_response, "NE");
for (const [name, data] of [["small", fullReview], ["long", longReview]]) {
  for (const mode of ["summary", "full"]) writeFileSync(join(fixtureDir, name + "-" + mode + ".html"), printDocument(data, mode));
}
writeFileSync(join(fixtureDir, "long-draft.json"), makeDraft(longSources, "zh-CN", "2026-10-25T00:00:00.000Z"));
writeFileSync(join(fixtureDir, "corrupt-draft.json"), JSON.stringify({ ...draft, schema_version: 99 }));
writeFileSync(join(fixtureDir, "invalid-draft.json"), draftText);
writeFileSync(join(fixtureDir, "study.json"), revised.study_json);
writeFileSync(join(fixtureDir, "followup.csv"), revised.followup_csv);
check("36-visit print fixtures include long Unicode notes and NE without changing clinical values");

const index = readFileSync(join(output, "index.html"), "utf8");
const app = readFileSync(join(output, "app.mjs"), "utf8");
assert.ok(index.includes("connect-src 'none'"));
assert.ok(index.includes('sandbox hidden'));
assert.ok(!/\b(fetch\s*\(|XMLHttpRequest|WebSocket|sendBeacon\s*\()/.test(app));
assert.ok(!/\b(?:src|href)\s*=\s*["'](?:https?:)?\/\//i.test(index));
assert.ok(!app.includes('window.open') && !app.includes('target = "_blank"'));
check("workbench uses local assets, blocks network connections and previews print content without navigation");
process.stdout.write(JSON.stringify({ checks, print_fixture_visits: 36, print_fixture_observations: 72 }));
