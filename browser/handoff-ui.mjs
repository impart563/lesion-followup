import { createHandoff, createHandoffReceiver } from "./handoff.mjs";
import { ZIP_LIMITS } from "./archive.mjs";
import { escapeHtml as esc } from "./workbench.mjs";

export function mountHandoff({ getEvaluate, getSession, getQuality, getNotes, getRevision, getBusy, apply, download, notify }) {
  const $ = id => document.getElementById(id);
  let busy = false, revision = getRevision(), preview = null, available = null;
  const receiver = createHandoffReceiver(request => getEvaluate()(request), getRevision, apply);

  function refresh() {
    const next = getRevision();
    if (next !== revision) {
      revision = next; receiver.invalidate();
      if (preview) $("handoff-import-status").textContent = "工作区已更新，请重新检查交接包，再决定是否载入。";
      preview = null; $("handoff-preview").hidden = true;
    }
    const matching = getNotes().hasCurrentRecord();
    if (matching !== available) { $("handoff-include-notes").checked = matching; available = matching; }
    const ready = !!getEvaluate(), locked = busy || getBusy();
    $("handoff-include-notes").disabled = locked || !matching;
    $("handoff-notes-state").textContent = matching ? "可一并保存当前人工核查记录。" : "当前没有与输入匹配的人工核查记录，将保存测量会话与报告。";
    $("export-handoff").disabled = !ready || locked || !getQuality()?.valid;
    $("inspect-handoff").disabled = !ready || locked || !$("handoff-file").files.length;
    $("apply-handoff").disabled = locked || !receiver.canLoad();
  }

  function render(summary) {
    const notes = summary.notes;
    $("handoff-preview").innerHTML = `<div class="handoff-preview-heading"><strong>${esc(summary.study_id)}</strong><span class="batch-state passed">文件核查与报告重算一致</span></div><dl><div><dt>基线</dt><dd>${esc(summary.baseline_date)}</dd></div><div><dt>随访记录</dt><dd>${summary.visit_count} 次 · ${summary.hint_count} 项人工核查提示</dd></div><div><dt>对照版本</dt><dd>${summary.has_reference ? "已保留" : "未包含"}</dd></div><div><dt>人工核查</dt><dd>${notes ? `${notes.reviewed} 项已查看 · ${notes.pending} 项待核查` : "未包含，将清除页面内原有核查记录"}</dd></div><div><dt>报告语言</dt><dd>${summary.language === "en" ? "English" : "中文"}</dd></div><div><dt>打包时间（UTC+8）</dt><dd>${esc(new Intl.DateTimeFormat("zh-CN", { dateStyle: "medium", timeStyle: "short", timeZone: "Asia/Shanghai" }).format(new Date(summary.created_at)))}</dd></div></dl><details class="provenance"><summary>查看核查依据 · ${summary.file_count} 个文件</summary><p>当前输入 SHA-256</p><p class="fingerprint">${summary.source_sha256}</p><p>交接清单 SHA-256</p><p class="fingerprint">${summary.manifest_sha256}</p></details><p class="muted">仅预览核对后的元数据，不执行收到的 HTML。点击下方载入后，替换当前页面的两版输入、语言与人工核查记录；本机草稿和核查副本需另行保存。</p>`;
    $("handoff-preview").hidden = false;
  }

  function bind(id, handler) {
    $(id).addEventListener("click", async () => {
      if (busy || getBusy()) return;
      busy = true; refresh();
      try { await handler(); }
      catch (error) { $(id === "export-handoff" ? "handoff-export-status" : "handoff-import-status").textContent = error.message; notify(error.message, true); }
      finally { busy = false; refresh(); }
    });
  }
  $("handoff-file").addEventListener("change", () => {
    receiver.invalidate(); preview = null; $("handoff-preview").hidden = true;
    $("handoff-import-status").textContent = "文件已选择，检查完成后可预览并载入。"; refresh();
  });
  bind("export-handoff", async () => {
    const token = getRevision(), session = getSession();
    const notes = $("handoff-include-notes").checked ? getNotes().snapshot() : null;
    $("handoff-export-status").textContent = "正在生成当前报告并整理交接文件…";
    const bytes = await createHandoff(getEvaluate(), session.before, session.current, session.language, notes);
    if (token !== getRevision()) throw new Error("打包期间记录已变化，请重新导出当前交接包。");
    download("lesion-followup-handoff.zip", bytes, "application/zip");
    $("handoff-export-status").textContent = notes ? "已导出测量会话、当前报告和人工核查记录。" : "已导出测量会话与当前报告，未包含人工核查记录。";
    notify("完整交接包已导出，可在另一工作区检查后继续复核。");
  });
  bind("inspect-handoff", async () => {
    const file = $("handoff-file").files[0];
    receiver.invalidate(); preview = null; $("handoff-preview").hidden = true;
    if (!file || file.size > ZIP_LIMITS.bytes) throw new Error("请选择不超过 64 MiB 的完整交接 ZIP。");
    $("handoff-import-status").textContent = "正在核对文件、会话与备注，并重新生成报告…";
    const summary = await receiver.inspect(() => file.arrayBuffer().catch(() => { throw new Error("文件暂时无法读取，请重新选择交接 ZIP。"); }));
    preview = summary; render(summary);
    $("handoff-import-status").textContent = "检查完成。确认下方内容后，可载入整组复核记录。";
  });
  bind("apply-handoff", async () => {
    receiver.load(); preview = null; $("handoff-preview").hidden = true;
    $("handoff-import-status").textContent = "交接记录已载入，可继续比较、生成报告或记录人工核查。";
    notify("完整交接记录已载入页面。本机草稿与核查副本未自动改写。");
  });
  refresh();
  return { refresh };
}
