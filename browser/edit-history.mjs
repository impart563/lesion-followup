// Current-input text history only; no persistence, reference, language or notes.
export const HISTORY_LIMITS = Object.freeze({ steps: 40, bytes: 8 * 1024 * 1024 });
const encoder = new TextEncoder();
const copy = value => ({ study_json: value.study_json, followup_csv: value.followup_csv });
const same = (a, b) => a.study_json === b.study_json && a.followup_csv === b.followup_csv;

export function createEditHistory(initial, limits = HISTORY_LIMITS) {
  if (!Number.isSafeInteger(limits.steps) || limits.steps < 1 || !Number.isSafeInteger(limits.bytes) || limits.bytes < 1) throw new Error("Invalid history limits");
  let entries = [], position = 0, group = null, limited = false;
  const entry = (sources, label) => ({ sources: copy(sources), label, bytes: encoder.encode(JSON.stringify([sources.study_json, sources.followup_csv])).length });
  const total = () => entries.reduce((sum, item) => sum + item.bytes, 0);
  function trim() {
    while (entries.length > 1 && (entries.length - 1 > limits.steps || total() > limits.bytes)) {
      entries.shift(); position--; limited = true;
    }
    if (total() > limits.bytes) limited = true;
  }
  function reset(sources) { entries = [entry(sources, "")]; position = 0; group = null; limited = false; trim(); }
  reset(initial);
  return {
    reset,
    settle() { group = null; },
    record(sources, label = "编辑记录", key = null) {
      if (same(entries[position].sources, sources)) return false;
      entries.splice(position + 1);
      if (key !== null && key === group && position > 0) entries[position] = entry(sources, label);
      else { entries.push(entry(sources, label)); position++; }
      group = key; trim(); return true;
    },
    undo() { if (!position) return null; group = null; return copy(entries[--position].sources); },
    redo() { if (position === entries.length - 1) return null; group = null; return copy(entries[++position].sources); },
    status() { return { undo: position, redo: entries.length - 1 - position, limited,
      undoLabel: position ? entries[position].label : "", redoLabel: position < entries.length - 1 ? entries[position + 1].label : "" }; },
  };
}
