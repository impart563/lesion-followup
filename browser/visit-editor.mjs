// Shape edits only. MoonBit validates every proposed track; no measurements are inferred.
import { invoke, serializeTable } from "./workbench.mjs";
import { prepareObservationEdit } from "./observation-editor.mjs";

const exact = (value, keys) => value && typeof value === "object" && !Array.isArray(value) &&
  Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key));
function fail(message, preflight = null) { const error = new Error(message); error.preflight = preflight; throw error; }

export function visitSummaries(model) {
  const groups = new Map();
  for (const row of model.rows) {
    if (!groups.has(row[0])) groups.set(row[0], { id: row[0], date: row[1], technique_id: row[2], observations: 0 });
    groups.get(row[0]).observations++;
  }
  return [...groups.values()];
}

export function prepareVisitEdit(evaluate, sources, operation) {
  if (operation?.kind === "observations") return prepareObservationEdit(evaluate, sources, operation);
  const keys = operation?.kind === "remove" ? ["kind", "visit_id"] : operation?.kind === "append" ?
    ["kind", "id", "date", "technique_id"] : ["kind", "visit_id", "id", "date", "technique_id"];
  if (!exact(operation, keys) || !["append", "update", "remove"].includes(operation.kind) ||
      keys.some(key => typeof operation[key] !== "string")) fail("随访操作的字段不完整，请重新填写。");
  const decoded = invoke(evaluate, { action: "editor", ...sources });
  if (!decoded.ok || !decoded.preflight.valid) fail("请先修正当前记录，再进行整次随访操作。", decoded.preflight);
  const model = structuredClone(decoded.result), visits = visitSummaries(model);
  const existing = operation.kind === "append" ? null : visits.find(visit => visit.id === operation.visit_id);
  if (operation.kind !== "append" && !existing) fail("这次随访已不存在，请重新选择。");
  if (operation.kind !== "remove" && visits.some(visit => visit.id === operation.id && visit.id !== existing?.id)) fail("随访编号已存在，请为每次随访使用不同编号。");
  let observations;
  if (operation.kind === "append") {
    observations = model.study.targets.length;
    model.rows.push(...model.study.targets.map(target => [operation.id, operation.date, operation.technique_id, target.id, "missing", "", ""]));
  } else if (operation.kind === "update") {
    observations = existing.observations;
    model.rows = model.rows.map(row => row[0] === operation.visit_id ? [operation.id, operation.date, operation.technique_id, ...row.slice(3)] : row);
  } else {
    observations = existing.observations;
    model.rows = model.rows.filter(row => row[0] !== operation.visit_id);
  }
  // Preserve the study text exactly. Only the deliberately edited CSV is serialized.
  const candidate = { study_json: sources.study_json, followup_csv: serializeTable(model).followup_csv };
  const preflight = invoke(evaluate, { action: "preflight", ...candidate }).preflight;
  if (!preflight.valid) fail("随访信息未通过检查，请核对编号、日期和采集标识。", preflight);
  return { sources: candidate, summary: { kind: operation.kind, id: operation.kind === "remove" ? existing.id : operation.id,
    date: operation.kind === "remove" ? existing.date : operation.date, observations, visit_count: preflight.visit_count,
    hint_count: preflight.review_hints.length }, preflight };
}

export function createVisitPlanner(evaluate, getRevision, apply) {
  let ready = null;
  return {
    invalidate() { ready = null; },
    preview(sources, operation) {
      ready = null;
      const revision = getRevision(), result = prepareVisitEdit(evaluate, sources, operation);
      if (revision !== getRevision()) fail("记录已变化，请重新检查随访信息。");
      ready = { revision, result }; return structuredClone(result.summary);
    },
    canApply() { return ready !== null && ready.revision === getRevision(); },
    apply() {
      if (!ready || ready.revision !== getRevision()) { ready = null; fail("随访预览已失效，请重新检查后再应用。"); }
      const result = structuredClone(ready.result); ready = null; apply(result);
    },
  };
}
