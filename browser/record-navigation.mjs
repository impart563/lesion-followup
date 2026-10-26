// Search changes only the visible row indices; identifiers and source cells stay exact.
const states = { measured: "已测量", absent: "已消失", too_small: "过小 无法可靠测量", missing: "未测量", not_evaluable: "无法评价" };
const normalize = value => String(value ?? "").normalize("NFKC").toLowerCase();

export function filterObservationRows(model, { visit_id = null, query = "" } = {}) {
  if (!model) return [];
  const terms = normalize(query).trim().split(/\s+/u).filter(Boolean);
  const targets = new Map(model.study.targets.map(target => [target.id, target]));
  return model.rows.flatMap((row, index) => {
    if (visit_id !== null && row[0] !== visit_id) return [];
    const target = targets.get(row[3]);
    const text = normalize([...row, target?.organ, states[row[4]], target?.kind === "lymph_node" ? "淋巴结 短轴" : target ? "非淋巴结 最长径" : ""].join(" "));
    return terms.every(term => text.includes(term)) ? [index] : [];
  });
}

export function locateObservation(model, hint) {
  if (!model || !hint?.visit_id || hint.source === "study_json" || !model.rows.some(row => row[0] === hint.visit_id)) return null;
  if (hint.lesion_id && !model.study.targets.some(target => target.id === hint.lesion_id)) return null;
  // A baseline target may have no row yet; the observation form retains it as missing.
  return { visit_id: hint.visit_id, lesion_id: hint.lesion_id || null };
}
