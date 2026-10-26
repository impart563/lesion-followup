import assert from "node:assert/strict";
import { readFileSync, writeFileSync } from "node:fs";
import { resolve, join } from "node:path";
import { pathToFileURL } from "node:url";
const folder = resolve(process.argv[2]);
const load = name => import(pathToFileURL(join(folder, name)));
const { evaluate } = await load("browser.js");
const { invoke, serializeTable, makeSession, readSession } = await load("workbench.mjs");
const { prepareVisitEdit, createVisitPlanner, visitSummaries } = await load("visit-editor.mjs");
const { createEditHistory, HISTORY_LIMITS } = await load("edit-history.mjs");
const current = { study_json: readFileSync("examples/study.json", "utf8"), followup_csv: readFileSync("examples/followup.csv", "utf8") };
const model = source => invoke(evaluate, { action: "editor", ...source }).result;
const initial = structuredClone(current), cases = [], checks = [];
function collect(name, source) {
  const outputs = Object.fromEntries(["json", "csv", "html", "markdown", "svg"].map(format => {
    const response = invoke(evaluate, { action: "review", ...source, format, language: "zh-CN" });
    assert.equal(response.ok, true); return [format, response.result.content];
  }));
  cases.push({ name, source, preflight: invoke(evaluate, { action: "preflight", ...source }).preflight, outputs });
}
const append = { kind: "append", id: "week-10", date: "2026-03-15", technique_id: "ct-venous-5mm" };
const added = prepareVisitEdit(evaluate, current, append);
assert.deepEqual(current, initial); assert.equal(added.sources.study_json, current.study_json);
assert.deepEqual(model(added.sources).rows.slice(0, 8), model(current).rows);
assert.deepEqual(model(added.sources).rows.slice(8), [
  ["week-10", "2026-03-15", "ct-venous-5mm", "T1", "missing", "", ""],
  ["week-10", "2026-03-15", "ct-venous-5mm", "N1", "missing", "", ""],
]);
collect("append-missing", added.sources);
assert.equal(JSON.parse(cases[0].outputs.json).assessments.at(-1).target_response, "NE");
for (let count = 1; count <= 5; count++) {
  const study = structuredClone(model(current).study);
  study.targets = Array.from({ length: count }, (_, i) => ({ id: `T${i+1}`, organ: `organ-${i+1}`, kind: "non_nodal", baseline_mm: "30.0" }));
  const source = { study_json: JSON.stringify(study), followup_csv: "visit_id,date,technique_id,lesion_id,state,diameter_mm,note\n" };
  const result = prepareVisitEdit(evaluate, source, append);
  assert.equal(model(result.sources).rows.length, count);
  assert.deepEqual(model(result.sources).rows.map(row => row[3]), study.targets.map(target => target.id));
}
checks.push("append covers one to five targets, blank missing observations, unchanged existing cells and exact study text");

const quoted = model(current);
quoted.rows[0][4] = "not_evaluable"; quoted.rows[0][5] = "";
quoted.rows[0][6] = '合成说明, "引号"\r\n第二行 Ω 😀';
// Keep the reader's reason on a not-evaluable observation without interpretation.
const raw = serializeTable(quoted);
raw.study_json = current.study_json.replace(/\n/g, "\r\n");
raw.followup_csv = raw.followup_csv.replace(/(?<!\r)\n/g, "\r\n");
const updated = prepareVisitEdit(evaluate, raw, { kind: "update", visit_id: "week-2", id: "复核-2", date: "2026-01-16", technique_id: "ct-reviewed" });
assert.equal(updated.sources.study_json, raw.study_json);
const after = model(updated.sources).rows, before = model(raw).rows;
for (let i = 0; i < after.length; i++) {
  assert.deepEqual(after[i].slice(3), before[i].slice(3));
  if (i < 2) assert.deepEqual(after[i].slice(0, 3), ["复核-2", "2026-01-16", "ct-reviewed"]);
  else assert.deepEqual(after[i], before[i]);
}
assert.equal(visitSummaries(model(updated.sources))[0].observations, 2);
collect("update-unicode-crlf", updated.sources);
const removed = prepareVisitEdit(evaluate, raw, { kind: "remove", visit_id: "week-6" });
assert.deepEqual(model(removed.sources).rows, before.filter(row => row[0] !== "week-6"));
collect("remove-middle", removed.sources);
let empty = current;
for (const visit of visitSummaries(model(current))) empty = prepareVisitEdit(evaluate, empty, { kind: "remove", visit_id: visit.id }).sources;
assert.equal(model(empty).rows.length, 0);
collect("remove-all", empty);
const reopened = prepareVisitEdit(evaluate, empty, append);
collect("append-to-empty", reopened.sources);
checks.push("whole-visit metadata and removal preserve unaffected observations, Unicode/CRLF notes and core findings");

const invalidOperations = [null, { ...append, kind: "other" }, { ...append, extra: true }, { ...append, id: 3 },
  { ...append, id: "week-2" }, { ...append, id: "" }, { ...append, date: "2026-02-30" },
  { ...append, date: "2026-01-01" }, { ...append, date: "2026-02-01" }, { ...append, technique_id: "" },
  { kind: "update", visit_id: "absent", id: "a", date: "2026-01-10", technique_id: "ct" },
  { kind: "update", visit_id: "week-2", id: "week-4", date: "2026-01-16", technique_id: "ct" },
  { kind: "update", visit_id: "week-2", id: "week-2", date: "2026-03-02", technique_id: "ct" },
  { kind: "remove", visit_id: "absent" }, { kind: "remove", visit_id: "week-2", id: "extra" }];
for (const operation of invalidOperations) assert.throws(() => prepareVisitEdit(evaluate, current, operation));
assert.throws(() => prepareVisitEdit(evaluate, { ...current, followup_csv: current.followup_csv.replace("20.0", "20.01") }, append));
assert.throws(() => prepareVisitEdit(evaluate, { ...current, followup_csv: "bad\n" }, append));
assert.deepEqual(current, initial);

let revision = 0, applied = [];
const planner = createVisitPlanner(evaluate, () => revision, result => applied.push(result));
const preview = planner.preview(current, append); preview.id = "mutated";
assert.equal(applied.length, 0); assert.equal(planner.canApply(), true);
revision++; assert.equal(planner.canApply(), false); assert.throws(() => planner.apply());
planner.preview(current, append); planner.invalidate(); assert.throws(() => planner.apply());
planner.preview(current, append); assert.throws(() => planner.preview(current, invalidOperations[4]));
assert.equal(planner.canApply(), false);
planner.preview(current, append); planner.apply(); assert.equal(applied.length, 1);
assert.deepEqual(applied[0].sources, added.sources); assert.equal(applied[0].summary.id, "week-10");
assert.throws(() => planner.apply());
checks.push("strict operations and native preflight reject malformed, duplicate and out-of-order edits; stale or changed previews never apply");

const history = createEditHistory(raw), rawCopy = structuredClone(raw);
let edit = { ...raw, followup_csv: "unfinished" };
history.record(edit, "raw", "csv"); history.record({ ...edit, followup_csv: "unfinished2" }, "raw", "csv");
assert.equal(history.status().undo, 1); assert.deepEqual(history.undo(), rawCopy);
assert.equal(history.redo().followup_csv, "unfinished2"); history.settle();
history.record(added.sources, "append"); history.record(removed.sources, "remove");
assert.deepEqual(history.undo(), added.sources); assert.deepEqual(history.undo(), { ...raw, followup_csv: "unfinished2" });
assert.deepEqual(history.undo(), rawCopy); assert.equal(history.undo(), null);
const returned = history.redo(); returned.study_json = "mutated";
assert.deepEqual(history.undo(), rawCopy); assert.equal(history.redo().study_json, raw.study_json);
history.record(updated.sources, "new branch"); assert.equal(history.redo(), null); assert.equal(history.status().redo, 0);
history.reset(current); assert.deepEqual(history.status(), { undo: 0, redo: 0, limited: false, undoLabel: "", redoLabel: "" });
assert.equal(history.record(current), false);
for (let i=0;i<45;i++) history.record({ ...current, followup_csv: String(i) }, "step");
assert.equal(history.status().undo, HISTORY_LIMITS.steps); assert.equal(history.status().limited, true);
const bounded = createEditHistory({ study_json: "", followup_csv: "" }, { steps: 40, bytes: 120 });
for (let i=0;i<5;i++) bounded.record({ study_json: String(i).repeat(40), followup_csv: "" });
assert.ok(bounded.status().undo <= 1); assert.equal(bounded.status().limited, true);
bounded.record({ study_json: "x".repeat(300), followup_csv: "" }); assert.equal(bounded.undo(), null);
bounded.reset(raw); assert.equal(bounded.status().undo, 0);
const session = await readSession(await makeSession(rawCopy, added.sources, "zh-CN"));
assert.deepEqual(session.before, rawCopy); assert.deepEqual(session.current, added.sources);
checks.push("bounded text history coalesces fields, restores exact raw inputs, isolates snapshots, drops redo branches and resets on external loads");
writeFileSync(join(folder, "acceptance/visit-added-session.json"), await makeSession(current, added.sources, "zh-CN"));
process.stdout.write(JSON.stringify({ status: "passed", checks, rejected_operations: invalidOperations.length+2,
  target_counts: 5, native_cases: cases }));
