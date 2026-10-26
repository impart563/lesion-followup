// Observation form transport. The MoonBit core owns precision, state and clinical rules.
import { invoke, serializeTable } from "./workbench.mjs";
const exact = (value, keys) => value && typeof value === "object" && !Array.isArray(value) &&
  Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key));
function fail(message, preflight = null) { const error = new Error(message); error.preflight = preflight; throw error; }
const valueOf = row => row ? { state: row[4], diameter_mm: row[5], note: row[6] } : null;

export function observationForm(model, visit_id) {
  const rows = model.rows.filter(row => row[0] === visit_id);
  if (!rows.length) fail("这次随访已不存在，请重新选择。");
  return model.study.targets.map(target => ({ lesion_id: target.id, organ: target.organ, kind: target.kind,
    baseline_mm: target.baseline_mm, ...(valueOf(rows.find(row => row[3] === target.id)) || { state: "missing", diameter_mm: "", note: "" }) }));
}

export function describeObservation(value) {
  if (!value) return "未录入观察";
  return value.state === "measured" ? `已测量 ${value.diameter_mm} mm` : value.state === "not_evaluable" ?
    "无法评价：" + value.note : ({ absent: "已消失", too_small: "过小，无法可靠测量", missing: "未测量" })[value.state] || value.state;
}

export function prepareObservationEdit(evaluate, sources, operation) {
  if (!exact(operation, ["kind", "visit_id", "measurements"]) || operation.kind !== "observations" ||
      typeof operation.visit_id !== "string" || !Array.isArray(operation.measurements)) fail("本次观察的字段不完整，请重新填写。");
  const decoded = invoke(evaluate, { action: "editor", ...sources });
  if (!decoded.ok || !decoded.preflight.valid) fail("请先修正当前记录，再录入整次观察。", decoded.preflight);
  const model = structuredClone(decoded.result), form = observationForm(model, operation.visit_id);
  const values = new Map();
  for (const item of operation.measurements) {
    if (!exact(item, ["lesion_id", "state", "diameter_mm", "note"]) || Object.values(item).some(value => typeof value !== "string") ||
        values.has(item.lesion_id) || !form.some(target => target.lesion_id === item.lesion_id)) fail("请为每个基线靶病灶保留一条观察，不能重复或引用其他病灶。");
    values.set(item.lesion_id, item);
  }
  if (values.size !== form.length) fail("本次观察不完整，请核对全部基线靶病灶。");
  const existing = model.rows.filter(row => row[0] === operation.visit_id), changes = [];
  const replacement = form.map(target => {
    const value = values.get(target.lesion_id), before = valueOf(existing.find(row => row[3] === target.lesion_id));
    const after = { state: value.state, diameter_mm: value.diameter_mm, note: value.note };
    if (JSON.stringify(before) !== JSON.stringify(after)) changes.push({ lesion_id: target.lesion_id, before, after });
    return [...existing[0].slice(0, 3), target.lesion_id, value.state, value.diameter_mm, value.note];
  });
  const first = model.rows.findIndex(row => row[0] === operation.visit_id);
  model.rows = [...model.rows.slice(0, first), ...replacement, ...model.rows.slice(first).filter(row => row[0] !== operation.visit_id)];
  const candidate = { study_json: sources.study_json, followup_csv: serializeTable(model).followup_csv };
  const preflight = invoke(evaluate, { action: "preflight", ...candidate }).preflight;
  if (!preflight.valid) fail("本次观察未通过检查，请核对状态、直径与无法评价原因。", preflight);
  return { sources: candidate, preflight, summary: { kind: "observations", id: operation.visit_id, date: existing[0][1],
    observations: replacement.length, visit_count: preflight.visit_count, hint_count: preflight.review_hints.length, changes } };
}
