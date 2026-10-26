import { createReviewNotes, updateReviewNotes, encodeReviewNotes, readReviewNotes, renderReviewNotes,
  reviewProgress, REVIEW_KEY, REVIEW_LIMITS } from "./review-notes.mjs";
import { escapeHtml as esc } from "./workbench.mjs";

export function mountReviewNotes({ getEvaluate, getSources, getQuality, getLanguage, getBusy, noticeText, download, notify, openObservation = null, onChange = () => {} }) {
  const $ = id => document.getElementById(id);
  const signature = () => { const s = getSources(); return JSON.stringify([s.study_json, s.followup_csv]); };
  let record = null, binding = null, current = signature(), epoch = 0, busy = false, saved = false, lastError = "";
  const active = () => record && binding === signature();

  function refresh() {
    const sig = signature();
    if (sig !== current) { current = sig; epoch++; }
    const ready = !!getEvaluate(), matching = active(), locked = busy || getBusy();
    $("start-review-notes").disabled = !ready || locked || !getQuality()?.valid;
    $("review-notes-work").hidden = !record;
    for (const id of ["save-review-notes", "export-review-html", "export-review-markdown"]) $(id).disabled = !matching || locked;
    $("export-review-json").disabled = !record || locked;
    $("import-review-notes").disabled = !ready || locked || !$("review-notes-file").files.length;
    $("review-summary-note").readOnly = !matching || locked;
    document.querySelectorAll("#review-notes-items textarea").forEach(el => { el.readOnly = !matching || locked; });
    document.querySelectorAll("#review-notes-items input[type=checkbox]").forEach(el => { el.disabled = !matching || locked; });
    document.querySelectorAll("#review-notes-items [data-open-observation]").forEach(el => { el.disabled = !matching || locked || !getQuality()?.valid; });
    let hasLocal = false;
    try { hasLocal = !!localStorage.getItem(REVIEW_KEY); } catch { /* Explicit save/restore reports storage failures. */ }
    $("restore-review-notes").disabled = !ready || !hasLocal || locked;
    $("clear-review-notes-copy").disabled = !hasLocal || locked;
    $("review-notes-state").textContent = !record ? "尚未开始" : !matching ? "原版本 · 只读" : saved ? "已保存到本机" : "有未保存的记录";
    $("review-notes-status").textContent = lastError || (!record ? "载入有效测量记录后，即可开始人工核查。" : !matching ?
      "当前输入已变化，以下内容保留原版本的核查记录，只能查阅或导出 JSON 备份。重新开始可核查当前输入。" :
      "按原始提示逐项记录查看情况。标记已查看后，提示仍保留在临床复核报告中。");
    $("review-notes-status").classList.toggle("error", !!lastError);
    if (record) {
      const progress = reviewProgress(record);
      $("review-notes-counts").textContent = `${progress.total} 项提示 · ${progress.reviewed} 项已查看 · ${progress.pending} 项待核查`;
      $("review-notes-context").textContent = `${record.context.study_id} · 基线 ${record.context.baseline_date} · ${record.context.visit_count} 次随访`;
      $("review-notes-fingerprint").textContent = record.context.source_sha256;
    }
    onChange();
  }

  function render() {
    if (!record) {
      $("review-summary-note").value = ""; $("review-notes-items").replaceChildren();
      for (const id of ["review-notes-counts", "review-notes-context", "review-notes-fingerprint"]) $(id).textContent = "";
      refresh(); return;
    }
    $("review-summary-note").value = record.summary_note;
    const filter = $("review-notes-filter").value;
    const items = record.items.filter(item => filter === "all" || item.status === filter);
    $("review-notes-empty").hidden = !!items.length;
    $("review-notes-empty").textContent = record.items.length ? "当前筛选下没有提示。" : "本次没有需要单独记录的自动提示，可在上方填写本轮复核说明。";
    $("review-notes-items").innerHTML = items.map(item => `<article class="review-note-card"><div class="review-note-heading"><div><strong>${esc(item.hint.visit_id || "整份记录")}${item.hint.lesion_id ? " · " + esc(item.hint.lesion_id) : ""}</strong><span>${esc(item.hint.code)}</span></div><label class="review-viewed"><input type="checkbox" data-review-id="${item.id}" ${item.status === "reviewed" ? "checked" : ""}>已查看</label></div><p>${esc(noticeText(item.hint))}</p><details class="review-original"><summary>原始提示与位置</summary><p>${esc(item.hint.message)}</p><p>${esc([item.hint.source, item.hint.field, item.hint.line ? "第 " + item.hint.line + " 行" : "", item.hint.column ? "第 " + item.hint.column + " 列" : ""].filter(Boolean).join(" · "))}</p></details><label class="review-note-label">核查备注<textarea data-note-id="${item.id}" aria-label="${esc(item.id)} 核查备注" maxlength="${REVIEW_LIMITS.note}" rows="3" placeholder="记录已核对的信息，或仍需进一步确认的内容。">${esc(item.note)}</textarea></label>${openObservation && item.hint.visit_id ? `<button type="button" class="quiet review-observation-link" data-open-observation="${item.id}">录入本次观察 →</button>` : ""}</article>`).join("");
    refresh();
  }

  function edit(change) {
    if (!active() || busy || getBusy()) return;
    record = updateReviewNotes(record, change); epoch++; saved = false; lastError = ""; refresh();
  }
  $("review-summary-note").addEventListener("input", () => edit({ summary_note: $("review-summary-note").value }));
  $("review-notes-items").addEventListener("input", event => {
    const id = event.target.dataset.noteId;
    const item = record?.items.find(item => item.id === id);
    if (item) edit({ id, status: item.status, note: event.target.value });
  });
  $("review-notes-items").addEventListener("change", event => {
    const id = event.target.dataset.reviewId;
    const item = record?.items.find(item => item.id === id);
    if (item) { edit({ id, status: event.target.checked ? "reviewed" : "pending", note: item.note }); render(); }
  });
  $("review-notes-items").addEventListener("click", event => {
    const button = event.target.closest?.("[data-open-observation]");
    if (!button || !active() || busy || getBusy() || !getQuality()?.valid) return;
    const item = record.items.find(item => item.id === button.dataset.openObservation);
    if (item) openObservation?.(item.hint);
  });
  $("review-notes-filter").addEventListener("change", render);
  $("review-notes-file").addEventListener("change", () => { epoch++; refresh(); });

  function bind(id, action) {
    $(id).addEventListener("click", async () => {
      if (busy) return;
      lastError = ""; busy = true; refresh();
      const token = epoch;
      const guard = () => { if (token !== epoch) throw new Error("操作期间输入或核查记录已变化，请重新执行。"); };
      try { await action(guard); }
      catch (error) { lastError = error.message; notify(error.message, true); }
      finally { busy = false; refresh(); }
    });
  }
  function apply(value, isLocal) {
    record = value; binding = signature(); epoch++; saved = isLocal;
    $("review-notes-filter").value = "all"; render();
  }
  bind("start-review-notes", async guard => {
    const value = await createReviewNotes(getEvaluate(), getSources()); guard(); apply(value, false);
    notify("人工核查清单已建立，可逐项记录查看情况与备注。");
  });
  bind("save-review-notes", async guard => {
    if (!active()) throw new Error("请先核对当前输入对应的核查记录。");
    const text = await encodeReviewNotes(record); guard(); localStorage.setItem(REVIEW_KEY, text); saved = true;
    notify("核查记录已保存到本机。测量草稿与复核会话需分别保存。");
  });
  bind("restore-review-notes", async guard => {
    const text = localStorage.getItem(REVIEW_KEY);
    if (!text) throw new Error("本机没有核查记录副本。");
    const value = await readReviewNotes(text, getEvaluate(), getSources()); guard(); apply(value, true);
    notify("核查记录已恢复，原始输入与核心提示均已重新核对。");
  });
  bind("clear-review-notes-copy", async () => { localStorage.removeItem(REVIEW_KEY); saved = false; notify("本机核查副本已清除，页面内的核查记录保持不变。"); });
  bind("export-review-json", async guard => {
    if (!record) throw new Error("请先建立核查记录。");
    const text = await encodeReviewNotes(record); guard(); download("target-review-notes.json", text, "application/json");
  });
  bind("import-review-notes", async guard => {
    const file = $("review-notes-file").files[0];
    if (!file || file.size > REVIEW_LIMITS.bytes) throw new Error("请选择不超过 4 MiB 的核查记录 JSON。");
    const value = await readReviewNotes(await file.text(), getEvaluate(), getSources()); guard(); apply(value, false);
    notify("核查记录已载入，当前测量输入未作修改。");
  });
  for (const format of ["html", "markdown"]) bind("export-review-" + format, async () => {
    if (!active()) throw new Error("原核查记录与当前输入不一致，请重新开始核查。");
    download("target-review-notes." + (format === "html" ? "html" : "md"), renderReviewNotes(record, format, getLanguage()), format === "html" ? "text/html" : "text/markdown");
  });
  refresh();
  return { refresh, version: () => epoch, isBusy: () => busy,
    hasCurrentRecord: () => !!active(),
    snapshot: () => active() ? structuredClone(record) : null,
    adopt(value) { lastError = ""; apply(value === null ? null : structuredClone(value), false); },
  };
}
