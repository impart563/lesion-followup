import { invoke, readSession } from "./workbench.mjs";
import { readZip, writeZip } from "./archive.mjs";

export const BATCH_LIMITS = Object.freeze({ files: 20, fileBytes: 2 * 1024 * 1024 });
const artifacts = ["report.html", "audit.json", "audit.csv", "chart.svg"];

export function createBundle(evaluate, sources, language) {
  const response = invoke(evaluate, { action: "bundle", ...sources, language });
  if (!response.ok) { const error = new Error("记录未通过检查，暂时无法生成报告包。"); error.response = response; throw error; }
  return { files: response.result.files, quality: response.preflight };
}

// Process independently; a clinically NE observation is a successful core result.
export async function reviewBatch(evaluate, files, language, { onProgress = () => {}, cancelled = () => false } = {}) {
  if (!files.length || files.length > BATCH_LIMITS.files) throw new Error("每批请选择 1–20 份复核会话。");
  const rows = [];
  for (let i = 0; i < files.length; i++) {
    if (cancelled()) return null;
    const row = { id: `case-${String(i + 1).padStart(3, "0")}`, name: files[i].name,
      status: "input_error", message: "", visit_count: 0, review_hint_count: 0, session: null, bundle: null };
    try {
      if (files[i].size > BATCH_LIMITS.fileBytes) throw new Error("会话超过 2 MiB，请拆分后重试。");
      let text;
      try { text = await files[i].text(); } catch { row.status = "io_error"; throw new Error("文件读取失败，请重新选择该文件。"); }
      row.session = await readSession(text);
      const bundle = createBundle(evaluate, row.session.current, language);
      row.bundle = bundle.files;
      row.status = "success"; row.message = "target_lesions_only";
      row.visit_count = bundle.quality.visit_count; row.review_hint_count = bundle.quality.review_hints.length;
    } catch (error) {
      const quality = error.response?.preflight;
      row.quality = quality;
      row.visit_count = quality?.visit_count || 0; row.review_hint_count = quality?.review_hints.length || 0;
      row.message = quality ? JSON.stringify(quality) : error.message;
      row.detail = error.message.replace(/，当前记录保持不变。$/, "。");
    }
    if (cancelled()) return null;
    rows.push(row); onProgress([...rows], files.length);
    await new Promise(resolve => setTimeout(resolve, 0));
  }
  if (cancelled()) return null;
  const cases = rows.map(({ id, status, message, visit_count, review_hint_count }) => ({ id, status, message, visit_count, review_hint_count }));
  const index = invoke(evaluate, { action: "batch-index", language, cases });
  if (!index.ok) throw new Error("批量索引生成失败，请核对记录。");
  return { rows, language, index: index.result.files };
}

export function batchZip(batch) {
  return writeZip([...batch.index, ...batch.rows.flatMap(row => (row.bundle || []).map(file => ({ ...file, name: row.id + "/" + file.name })))]);
}

export async function verifyArchive(evaluate, bytes) {
  const files = await readZip(bytes), groups = new Map();
  if (files.some(file => file.name === "handoff.json")) throw new Error("这是完整交接包，请使用上方的“检查交接包”入口。");
  for (const file of files) {
    if (["index.json", "index.html"].includes(file.name)) continue;
    const at = file.name.lastIndexOf("/"), prefix = file.name.slice(0, at + 1), name = file.name.slice(at + 1);
    if (!groups.has(prefix)) groups.set(prefix, []);
    groups.get(prefix).push({ name, content: file.content });
  }
  if (!groups.size || groups.size > 20) throw new Error("归档中没有可核查的报告包，或数量超过 20 份。");
  return [...groups].map(([prefix, entries]) => {
    const manifest = entries.find(f => f.name === "manifest.json");
    const files = entries.filter(f => f.name !== "manifest.json");
    if (files.length > 4 || files.some(f => !artifacts.includes(f.name))) {
      return { id: prefix.slice(0, -1) || "当前报告", ok: false, diagnostics: [{ code: "archive_files", message: "报告目录中包含清单之外的文件。" }] };
    }
    const result = invoke(evaluate, { action: "verify-bundle", manifest: manifest?.content || "", files });
    return { id: prefix.slice(0, -1) || "当前报告", ok: result.ok, diagnostics: result.diagnostics };
  });
}
