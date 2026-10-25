// Human observations are separate from the core's clinical findings and categories.
import { invoke, sourceFingerprint, escapeHtml as esc } from "./workbench.mjs";

export const REVIEW_KEY = "impart563.lesion-followup.review-notes.v1";
export const REVIEW_LIMITS = Object.freeze({ items: 1000, note: 2000, summary: 6000, bytes: 4 * 1024 * 1024 });
const KIND = "lesion-followup-review-notes";
const HINT_KEYS = ["code", "message", "source", "field", "line", "column", "visit_id", "lesion_id"];
const fail = detail => { throw new Error(`核查记录${detail}，现有记录保持不变。`); };
const exact = (value, keys) => value && !Array.isArray(value) && typeof value === "object" &&
  Object.keys(value).length === keys.length && keys.every(k => Object.hasOwn(value, k));
const timestamp = value => typeof value === "string" && /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(value) &&
  Number.isFinite(Date.parse(value)) && new Date(value).toISOString() === value;
const bounded = (value, max) => typeof value === "string" && value.length <= max;
const nullableText = value => value === null || bounded(value, 100000);
const position = value => value === null || (Number.isSafeInteger(value) && value > 0);

function hintValue(value) {
  if (!exact(value, HINT_KEYS) || !["code", "message", "source"].every(k => bounded(value[k], 100000)) ||
      !["field", "visit_id", "lesion_id"].every(k => nullableText(value[k])) || !position(value.line) || !position(value.column)) fail("中的提示字段损坏");
  return Object.fromEntries(HINT_KEYS.map(k => [k, value[k]]));
}

// Fixed property order is part of the v1 SHA-256 contract.
function payload(value) {
  if (!exact(value, ["schema_version", "kind", "created_at", "updated_at", "context", "summary_note", "items"]) ||
      value.schema_version !== 1 || value.kind !== KIND || !timestamp(value.created_at) || !timestamp(value.updated_at) ||
      value.updated_at < value.created_at || !bounded(value.summary_note, REVIEW_LIMITS.summary) || !Array.isArray(value.items) ||
      value.items.length > REVIEW_LIMITS.items) fail("类型、版本、时间或字段不受支持");
  const c = value.context;
  if (!exact(c, ["source_sha256", "study_id", "baseline_date", "visit_count"]) ||
      typeof c.source_sha256 !== "string" || !/^[0-9a-f]{64}$/.test(c.source_sha256) ||
      !bounded(c.study_id, 100000) || !bounded(c.baseline_date, 10) || !Number.isSafeInteger(c.visit_count) || c.visit_count < 0) fail("缺少有效的输入标识");
  const items = value.items.map((item, index) => {
    if (!exact(item, ["id", "hint", "status", "note", "updated_at"]) || item.id !== `hint-${index + 1}` ||
        !["pending", "reviewed"].includes(item.status) || !bounded(item.note, REVIEW_LIMITS.note) ||
        !timestamp(item.updated_at) || item.updated_at < value.created_at || item.updated_at > value.updated_at) fail("中的逐项记录损坏");
    return { id: item.id, hint: hintValue(item.hint), status: item.status, note: item.note, updated_at: item.updated_at };
  });
  return { schema_version: 1, kind: KIND, created_at: value.created_at, updated_at: value.updated_at,
    context: { source_sha256: c.source_sha256, study_id: c.study_id, baseline_date: c.baseline_date, visit_count: c.visit_count },
    summary_note: value.summary_note, items };
}

async function hash(text) {
  const bytes = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)));
  return Array.from(bytes, b => b.toString(16).padStart(2, "0")).join("");
}

export async function createReviewNotes(evaluate, sources, now = new Date().toISOString()) {
  const result = invoke(evaluate, { action: "editor", ...sources });
  if (!result.ok || !result.preflight.valid) throw new Error("请先修正输入问题，再开始记录人工核查。");
  if (result.preflight.review_hints.length > REVIEW_LIMITS.items) throw new Error("人工核查提示超过 1000 项，请拆分记录后重试。");
  return payload({ schema_version: 1, kind: KIND, created_at: now, updated_at: now,
    context: { source_sha256: await sourceFingerprint(sources), study_id: result.result.study.study_id,
      baseline_date: result.result.study.baseline_date, visit_count: result.preflight.visit_count }, summary_note: "",
    items: result.preflight.review_hints.map((hint, index) => ({ id: `hint-${index + 1}`, hint, status: "pending", note: "", updated_at: now })) });
}

export function updateReviewNotes(record, change, now = new Date().toISOString()) {
  const current = payload(record);
  if (!timestamp(now)) fail("修改时间无效");
  // A local clock correction must not move a record backwards.
  const at = now < current.updated_at ? current.updated_at : now;
  if (exact(change, ["summary_note"])) return payload({ ...current, updated_at: at, summary_note: change.summary_note });
  if (!exact(change, ["id", "status", "note"]) || !current.items.some(i => i.id === change.id)) fail("修改项不存在");
  return payload({ ...current, updated_at: at, items: current.items.map(item => item.id === change.id ?
    { ...item, status: change.status, note: change.note, updated_at: at } : item) });
}

export async function encodeReviewNotes(record) {
  const value = payload(record);
  const text = JSON.stringify({ ...value, sha256: await hash(JSON.stringify(value)) }, null, 2) + "\n";
  if (new TextEncoder().encode(text).length > REVIEW_LIMITS.bytes) fail("超过 4 MiB，无法保存");
  return text;
}

export async function readReviewNotes(text, evaluate, sources) {
  if (typeof text !== "string" || new TextEncoder().encode(text).length > REVIEW_LIMITS.bytes) fail("超过 4 MiB");
  let value;
  try { value = JSON.parse(text); } catch { fail("不是有效 JSON"); }
  if (!exact(value, ["schema_version", "kind", "created_at", "updated_at", "context", "summary_note", "items", "sha256"]) ||
      typeof value.sha256 !== "string" || !/^[0-9a-f]{64}$/.test(value.sha256)) fail("缺少有效的完整性摘要");
  const { sha256, ...fields } = value, canonical = payload(fields);
  if (await hash(JSON.stringify(canonical)) !== sha256) fail("与完整性摘要不一致");
  if (await sourceFingerprint(sources) !== canonical.context.source_sha256) fail("与当前原始输入不匹配");
  const expected = await createReviewNotes(evaluate, sources, canonical.created_at);
  if (JSON.stringify(canonical.context) !== JSON.stringify(expected.context) ||
      JSON.stringify(canonical.items.map(i => i.hint)) !== JSON.stringify(expected.items.map(i => i.hint))) fail("与当前原始输入或核心提示不匹配");
  return canonical;
}

export function reviewProgress(record) {
  const reviewed = record.items.filter(item => item.status === "reviewed").length;
  return { total: record.items.length, reviewed, pending: record.items.length - reviewed };
}

function md(value) {
  // Numeric entities keep untrusted text literal in CommonMark, including line markers.
  return Array.from(String(value), c => /[\p{L}\p{N} ]/u.test(c) ? c : c === "\n" ? "<br>\n" : `&#${c.codePointAt(0)};`).join("");
}

export function renderReviewNotes(record, format, language = "zh-CN") {
  const value = payload(record), en = language === "en";
  if (!["html", "markdown"].includes(format) || !["en", "zh-CN"].includes(language)) throw new Error("不支持的核查记录格式或语言。");
  const t = (zh, english) => en ? english : zh;
  const title = t("人工核查记录", "Human review notes");
  const scope = t("本文件记录人工查看情况和备注，仅涉及靶病灶。已查看不代表问题已解决、整体疗效已确定或临床验证通过。核心提示和分类保持原样。", "This document records human viewing status and notes for target lesions only. Viewed does not mean resolved, overall response determined, or clinically validated. Core findings and classifications remain unchanged.");
  const integrity = t("输入标识对应原始文本，SHA-256 不认证记录人或来源。时间由本机提供。", "The input fingerprint identifies source text. SHA-256 does not authenticate a reviewer or origin. Times are supplied by the local device.");
  const counts = reviewProgress(value), c = value.context;
  const status = item => item.status === "reviewed" ? t("已查看", "Viewed") : t("待核查", "Pending");
  const location = h => [h.visit_id, h.lesion_id, h.source, h.field, h.line ? t(`第 ${h.line} 行`, `line ${h.line}`) : "",
    h.column ? t(`第 ${h.column} 列`, `column ${h.column}`) : ""].filter(Boolean).join(" · ");
  const summary = `${t("提示", "Hints")} ${counts.total} · ${t("已查看", "Viewed")} ${counts.reviewed} · ${t("待核查", "Pending")} ${counts.pending}`;
  if (format === "markdown") return `# ${title}\n\n${md(c.study_id)} · ${t("基线", "Baseline")} ${md(c.baseline_date)} · ${c.visit_count} ${t("次随访", "visits")}\n\n${summary}\n\n${scope}\n\nSHA-256: ${c.source_sha256}\n\n${t("创建", "Created")}: ${value.created_at} · ${t("更新", "Updated")}: ${value.updated_at}\n\n## ${t("本轮复核说明", "Review summary")}\n\n${md(value.summary_note) || t("未填写", "Not recorded")}\n\n` + value.items.map((item, i) => `## ${i + 1}. ${md(item.hint.code)} · ${status(item)}\n\n${md(location(item.hint))}\n\n${md(item.hint.message)}\n\n${t("备注", "Note")}: ${md(item.note) || t("未填写", "Not recorded")}\n\n${t("更新", "Updated")}: ${item.updated_at}\n\n`).join("") + `${integrity}\n`;
  return `<!doctype html><html lang="${en ? "en" : "zh-CN"}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'"><title>${title} · ${esc(c.study_id)}</title><style>body{font:15px/1.8 system-ui,sans-serif;color:#263b32;background:#f7f8f5;max-width:940px;margin:40px auto;padding:0 24px}h1{font-size:28px}h2{font-size:18px}article,header{background:white;border:1px solid #d8e2da;border-radius:10px;padding:22px;margin:18px 0}.scope{color:#526159}.fingerprint{overflow-wrap:anywhere;font-size:12px}.note{white-space:pre-wrap;overflow-wrap:anywhere}.meta{font-size:12px;color:#526159}.status{font-weight:600;color:#42614e}@media print{body{background:white;margin:0;font-size:10pt}article{break-inside:avoid}header{border:0;padding:0}@page{size:A4;margin:14mm}}</style></head><body><header><h1>${title}</h1><p>${esc(c.study_id)} · ${t("基线", "Baseline")} ${esc(c.baseline_date)} · ${c.visit_count} ${t("次随访", "visits")}</p><p class="status">${summary}</p><p class="scope">${scope}</p><p class="fingerprint">SHA-256: ${c.source_sha256}</p><p class="meta">${value.created_at} → ${value.updated_at}</p></header><section><h2>${t("本轮复核说明", "Review summary")}</h2><p class="note">${esc(value.summary_note) || t("未填写", "Not recorded")}</p></section>${value.items.map((item, i) => `<article><h2>${i + 1}. ${esc(item.hint.code)} <span class="status">· ${status(item)}</span></h2><p class="meta">${esc(location(item.hint))}</p><p class="note">${esc(item.hint.message)}</p><p class="note">${esc(item.note) || t("未填写备注", "No note recorded")}</p><p class="meta">${item.updated_at}</p></article>`).join("")}<footer class="scope">${integrity}</footer></body></html>\n`;
}
