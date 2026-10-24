// Presentation and persistence contracts only. Clinical rules live in MoonBit.
export const COLUMNS = ["visit_id", "date", "technique_id", "lesion_id", "state", "diameter_mm", "note"];
export const DRAFT_KEY = "impart563.lesion-followup.draft.v1";

export function invoke(evaluate, request) {
  return JSON.parse(evaluate(JSON.stringify({ schema_version: 1, ...request })));
}

function csvCell(text) {
  return /[",\r\n]/.test(text) ? '"' + text.replaceAll('"', '""') + '"' : text;
}

export function serializeTable(model) {
  return {
    study_json: JSON.stringify(model.study, null, 2) + "\n",
    followup_csv: [COLUMNS, ...model.rows].map(row => row.map(csvCell).join(",")).join("\n") + "\n",
  };
}

// Locations belong to the canonical CSV currently displayed after table edits.
// Quoted physical newlines are counted; no CSV decoding is implemented here.
export function rowLocations(rows) {
  let line = 2;
  return rows.map(row => {
    const start = line;
    line += 1 + row.reduce((count, cell) => count + (cell.match(/\r\n|\r|\n/g) || []).length, 0);
    return { start, end: line - 1 };
  });
}

export function makeDraft(sources, language, now = new Date().toISOString()) {
  return JSON.stringify({ schema_version: 1, kind: "lesion-followup-draft", saved_at: now,
    language, study_json: sources.study_json, followup_csv: sources.followup_csv }, null, 2) + "\n";
}

export function readDraft(text) {
  let value;
  try { value = JSON.parse(text); } catch { throw new Error("草稿不是有效 JSON，当前输入保持不变。"); }
  if (!value || Array.isArray(value) || value.schema_version !== 1 || value.kind !== "lesion-followup-draft") {
    throw new Error("草稿类型或版本不受支持，当前输入保持不变。");
  }
  const keys = ["schema_version", "kind", "saved_at", "language", "study_json", "followup_csv"];
  if (Object.keys(value).length !== keys.length || Object.keys(value).some(key => !keys.includes(key)) ||
      typeof value.study_json !== "string" || typeof value.followup_csv !== "string" ||
      !["en", "zh-CN"].includes(value.language) || typeof value.saved_at !== "string" ||
      !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(value.saved_at) ||
      !Number.isFinite(Date.parse(value.saved_at))) {
    throw new Error("草稿字段损坏，当前输入保持不变。");
  }
  return value;
}

export async function createReview(evaluate, sources, language) {
  const outputs = {};
  let quality;
  for (const format of ["json", "html", "csv", "markdown", "svg"]) {
    const response = invoke(evaluate, { action: "review", ...sources, language, format });
    if (!response.ok) throw new Error("当前输入未通过校验，不能生成报告。");
    outputs[format] = response.result.content;
    quality = response.preflight;
  }
  const bytes = new TextEncoder().encode(JSON.stringify([sources.study_json, sources.followup_csv]));
  const hash = new Uint8Array(await globalThis.crypto.subtle.digest("SHA-256", bytes));
  const fingerprint = Array.from(hash, b => b.toString(16).padStart(2, "0")).join("");
  return { audit: JSON.parse(outputs.json), outputs, quality, fingerprint };
}

export function escapeHtml(text) {
  return String(text ?? "").replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;").replaceAll("'", "&#39;");
}

export function printDocument(review, mode) {
  if (!["summary", "full"].includes(mode)) throw new Error("未知打印布局。");
  const { audit, fingerprint } = review;
  const fullHtml = review.outputs.html;
  const style = fullHtml.match(/<style>([\s\S]*?)<\/style>/)?.[1];
  const body = fullHtml.match(/<body>([\s\S]*?)<\/body>/)?.[1];
  if (!style || !body) throw new Error("完整证据文档不完整。");
  const label = mode === "summary" ? "摘要" : "完整证据";
  const rows = audit.assessments.map((a, i) => `<tr><td><a class="screen-only" href="#visit-${i}">${escapeHtml(a.visit_id)}</a><span class="print-only">${escapeHtml(a.visit_id)}</span><br>${escapeHtml(a.date)}</td><td>${escapeHtml(a.target_response)}</td><td>${escapeHtml(a.sum_mm ?? "—")}</td><td>${escapeHtml(a.baseline_sum_mm)}</td><td>${escapeHtml(a.prior_nadir_mm)}<br>${escapeHtml(a.prior_nadir_visit_id)}</td><td>${a.findings.map(f => escapeHtml(f.code)).join("<br>") || "—"}</td></tr>`).join("");
  return `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'"><title>靶病灶${label} · ${escapeHtml(audit.study.study_id)}</title><style>${style}
@page{size:A4;margin:12mm}.print-only{display:none}*{box-sizing:border-box}.print-cover{max-width:1100px;margin:24px auto;padding:0 24px}.fingerprint{font-size:10px;overflow-wrap:anywhere}.print-help{padding:12px;background:#eaf3ef}.print-summary th,.print-summary td{overflow-wrap:anywhere}.print-summary table{table-layout:fixed}.evidence-section{border-top:2px solid #aac3b9;margin-top:30px}.print-scope{font-size:12px}.print-cover h1{font-size:26px}
@media print{.screen-only{display:none!important}.print-only{display:inline}html,body{width:auto;margin:0;background:white;font-size:10pt}.print-cover,.wrap{max-width:none;width:auto;margin:0;padding:0}.print-help{display:none}.panel,details,.evidence-section{break-inside:auto!important}.evidence-section{break-before:page}.panel{margin:10px 0;padding:10px}.table-scroll{overflow:visible!important}table{width:100%;table-layout:fixed;font-size:8pt}td,th{padding:5px!important;white-space:normal!important;overflow-wrap:anywhere;word-break:normal}thead{display:table-header-group}tr{break-inside:avoid}h1,h2,h3,summary{break-after:avoid}svg{display:block;max-width:100%;max-height:240mm;height:auto}p,.finding,.meta{overflow-wrap:anywhere}.details-inner{margin:10px 0}details::details-content{content-visibility:visible}.fingerprint{font-size:7pt}.cards{gap:5px}.card{padding:6px}.card strong{font-size:18px}${mode === "summary" ? ".evidence-section{display:none!important}" : ""}}
</style></head><body data-print-mode="${mode}"><section class="print-cover print-summary"><p class="print-help">${label}打印布局 · 使用浏览器打印（Ctrl+P）。屏幕下方保留同次复核的完整证据，摘要打印时仅输出本节。</p><h1>靶病灶随访复核 · ${label}</h1><p><strong>${escapeHtml(audit.study.study_id)}</strong> · 基线 ${escapeHtml(audit.study.baseline_date)} · ${audit.assessments.length} 次随访</p><p class="print-scope">仅供人工测量的 CT 靶病灶复核；不确定整体疗效，不提供治疗建议，不代表临床验证。NE 保留原始观察与复核要求。</p><p class="fingerprint">输入标识 SHA-256：${escapeHtml(fingerprint)}</p><p class="screen-only"><a href="#complete-evidence">查看本次完整测量、趋势与逐条件计算证据</a>。随访编号链接到对应证据。</p><p class="print-only">与完整证据对照时，请核对研究编号、基线日期和上方输入标识。</p><table><thead><tr><th>随访 / 日期</th><th>靶病灶结果</th><th>总和 / mm</th><th>基线总和 / mm</th><th>此前最低值 / 来源</th><th>复核与规则代码</th></tr></thead><tbody>${rows}</tbody></table></section><section id="complete-evidence" class="evidence-section">${body}</section></body></html>`;
}

export function printFragment(document) {
  const style = document.match(/<style>([\s\S]*?)<\/style>/)?.[1];
  const body = document.match(/<body[^>]*>([\s\S]*?)<\/body>/)?.[1];
  if (!style || !body) throw new Error("打印文档不完整。");
  return `<style>:host{display:block;font:14px/1.6 system-ui,sans-serif;color:#263348}@media print{:host{font-size:10pt}}${style}</style>${body}`;
}
