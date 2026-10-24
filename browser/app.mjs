import { COLUMNS, DRAFT_KEY, invoke, serializeTable, rowLocations, makeDraft, readDraft, createReview, printDocument, printFragment, escapeHtml as esc } from "./workbench.mjs";

const $ = id => document.getElementById(id);
const state = { evaluate: null, model: null, quality: null, report: null, revision: 0, saved: null, busy: false };
const inputNames = ["随访编号", "日期", "采集标识", "病灶编号", "观察状态", "直径 mm", "读片者说明"];
const stateNames = { measured: "已测量", absent: "已消失", too_small: "过小，无法可靠测量", missing: "未测量", not_evaluable: "无法评价" };
const urls = [];
const printShadow = $("print-render").attachShadow({ mode: "open" });
printShadow.addEventListener("click", event => {
  const link = event.target.closest?.('a[href^="#"]');
  const target = link && printShadow.getElementById(link.getAttribute("href").slice(1));
  if (target) { event.preventDefault(); target.scrollIntoView({ block: "start" }); }
});
const source = () => ({ study_json: $("study-source").value, followup_csv: $("csv-source").value });
const signature = () => JSON.stringify([source(), $("language").value]);
const message = (text, error = false) => { $("app-status").textContent = text; $("app-status").classList.toggle("error", error); };

function bind(id, handler) {
  $(id).addEventListener("click", () => Promise.resolve().then(handler).catch(error => message(error.message, true)));
}

function showView(name) {
  const names = { records: "测量记录", quality: "记录核查", report: "复核报告", draft: "草稿" };
  document.querySelectorAll("[data-panel]").forEach(el => { el.hidden = el.dataset.panel !== name; });
  document.querySelectorAll(".workspace-nav [data-view]").forEach(el => {
    el.classList.toggle("active", el.dataset.view === name);
    if (el.dataset.view === name) el.setAttribute("aria-current", "page"); else el.removeAttribute("aria-current");
  });
  $("view-name").textContent = names[name];
  $("inline-print").hidden = true;
}

function updateContext() {
  const hasData = !!(source().study_json || source().followup_csv);
  const study = state.model?.study;
  const q = state.quality;
  $("welcome").hidden = hasData;
  $("record-title").textContent = study?.study_id || "靶病灶随访";
  $("record-meta").textContent = study ? `基线 ${study.baseline_date}　·　${study.targets.length} 个靶病灶　·　${q?.visit_count ?? 0} 次随访` : hasData ? "记录已保留，请核对原始文件与检查结果。" : "导入配套文件，或先从合成示例开始。";
  const errors = q ? q.diagnostics.length + q.input_issues.length : 0;
  const hints = q?.review_hints.length || 0;
  $("record-state").textContent = !hasData ? "等待载入记录" : errors ? "有待修正项" : hints ? "待人工核查" : "记录检查通过";
  $("record-state").classList.toggle("ready", hasData && !errors && !hints);
  $("record-state").classList.toggle("warning", hasData && !!(errors || hints));
  $("records-badge").textContent = hasData ? q?.visit_count ?? "—" : "—";
  $("quality-badge").textContent = hasData ? errors + hints : "—";
  $("quality-badge").classList.toggle("attention", !!(errors || hints));
  $("data-notice").hidden = !hasData || !(errors || hints);
  $("data-notice-text").textContent = errors ? `有 ${errors} 项记录需要调整，修正后即可生成报告。` : `有 ${hints} 项观察需要人工核查，相关提示会保留在报告中。`;
}

document.querySelectorAll("[data-view]").forEach(el => el.addEventListener("click", () => showView(el.dataset.view)));
document.querySelectorAll("[data-open-import]").forEach(el => el.addEventListener("click", () => $("import-dialog").showModal()));
document.querySelectorAll("[data-use-example]").forEach(el => el.addEventListener("click", () => $("load-example").click()));
bind("close-import", () => $("import-dialog").close());

function noticeText(notice) {
  const descriptions = {
    csv_diameter: "请填写 0–1000 mm 的直径，最多保留一位小数。输入值不会被自动四舍五入。",
    csv_header: "随访文件的表头与要求不一致，请核对列名和顺序。",
    csv_columns: "这条随访记录的列数不完整，请核对 CSV 中的分隔符与引号。",
    csv_quoting: "随访文件中的引号未正确闭合，请在原始文件中核对。",
    json_syntax: "研究配置暂时无法读取，请检查 JSON 的括号、引号和分隔符。",
    study_schema: "研究配置的字段或数据格式不符合要求，请核对下方原始诊断。",
    invalid_date: "请核对日期是否存在，并使用 YYYY-MM-DD 格式。",
    visit_order: "随访应按日期严格递增排列，且晚于基线日期。",
    unknown_target: "这条观察引用了基线中不存在的病灶编号，请核对两处编号。",
    duplicate_id: "记录中出现重复编号或重复观察，请核对对应的随访与病灶。",
    target_count: "请核对基线靶病灶数量，本版本支持固定的 1–5 个靶病灶。",
    organ_target_count: "同一器官组最多纳入两个靶病灶，请核对器官分组。",
    invalid_target: "请核对基线病灶的编号、器官组、类型与直径。",
    invalid_study: "请核对研究编号、采集信息与 CT 层厚。",
    invalid_measurement: "这条观察的测量信息不完整或不一致，请核对状态、直径与说明。",
    missing_measurement: "本次随访缺少该病灶的有效测量；缺失值不会按零填补。",
    reader_not_evaluable: "读片者已注明无法评价，请结合原始说明复核。",
    default_5mm: "该病灶使用过小观察所约定的 5.0 mm 默认值，请确认观察状态。",
    technique_mismatch: "本次采集标识与基线不同，需要人工确认可比性。",
    track_requires_review: "既往已出现靶病灶 PD，后续记录保留为 NE，需结合更完整的评价背景复核。",
    reappearance_after_target_cr: "既往靶病灶 CR 后再次出现可见病灶，需要结合评价背景复核。",
    prior_pr_context_required: "既往达到 PR 后已不再满足其阈值，且未满足 PD 条件，需要进一步复核。",
    no_followup: "尚无随访记录，可以继续补充观察。",
  };
  if (notice.code === "csv_state") {
    if (notice.message.includes("requires a reason")) return "无法评价时，请填写读片者说明。";
    if (notice.message.includes("Only measured rows")) return "当前观察状态不使用直径，请核对并清空不适用的测量值。";
    if (notice.message.includes("note")) return "读片者说明用于记录无法评价的原因，请核对观察状态与说明。";
    return "请选择一种支持的观察状态。";
  }
  return descriptions[notice.code] || "请核对这条记录，原始诊断保留在下方。";
}

function updateButtons() {
  const ready = !!state.evaluate;
  for (const id of ["load-example", "import-inputs", "apply-source", "check-input", "save-draft", "export-draft", "import-draft", "export-study", "export-csv"]) $(id).disabled = !ready || state.busy;
  $("generate-report").disabled = !ready || state.busy || !state.quality?.valid;
  for (const id of ["export-report", "print-summary", "print-full", "export-print"]) $(id).disabled = !state.report;
  updateContext();
}

function discardReport() {
  state.report = null;
  $("inline-print").hidden = true;
  printShadow.replaceChildren();
  $("report-preview").hidden = true;
  $("report-preview").removeAttribute("srcdoc");
  $("report-summary").replaceChildren();
  $("report-overview").replaceChildren();
  $("report-tools").hidden = true;
  $("report-empty").hidden = false;
  $("report-status").textContent = "记录更新后，请重新生成报告，以便核对当前测量。";
}

function draftStatus() {
  const changed = state.saved !== signature();
  if (state.saved !== null) $("draft-status").textContent = changed ? "有尚未保存的修改。本机草稿仍保留上次保存的内容。" : "当前记录已保存，随时可以从这里继续。";
}

function targetFor(notice) {
  if (!state.model) return notice.source === "study_json" ? $("study-source") : $("csv-source");
  if (notice.source === "study_json") {
    const field = notice.field?.replace(/^\$\./, "");
    return document.querySelector(`[data-study-path="${CSS.escape(field || "")}"]`) || $("study-source");
  }
  const ranges = rowLocations(state.model.rows);
  const index = ranges.findIndex(row => notice.line >= row.start && notice.line <= row.end);
  return document.querySelector(`[data-row="${index}"][data-column="${COLUMNS.indexOf(notice.field)}"]`) || $("csv-source");
}

function renderQuality() {
  document.querySelectorAll(".invalid").forEach(el => { el.classList.remove("invalid"); el.removeAttribute("aria-invalid"); });
  const q = state.quality;
  if (!q) { $("quality-status").textContent = "载入记录后，这里会显示检查结果。"; $("quality-items").replaceChildren(); updateButtons(); return; }
  const errors = [...q.diagnostics, ...q.input_issues];
  $("quality-status").textContent = `${q.valid ? "格式与记录检查已通过" : "有记录需要调整"} · ${q.visit_count} 次随访 · ${errors.length} 项待修正 · ${q.review_hints.length} 项待核查`;
  $("quality-items").innerHTML = `<div class="quality-grid"><article class="quality-card"><h3>需要修正<span>${errors.length}</span></h3><ul id="blocking-list" class="notice-list"></ul></article><article class="quality-card"><h3>人工核查<span>${q.review_hints.length}</span></h3><ul id="hint-list" class="notice-list hints"></ul></article></div>`;
  for (const [notices, parent, blocking] of [[errors, $("blocking-list"), true], [q.review_hints, $("hint-list"), false]]) {
    if (!notices.length) { const li = document.createElement("li"); li.className = "empty-notice"; li.textContent = blocking ? "未发现需要修正的记录。" : "暂无需要额外核查的观察。"; parent.append(li); }
    for (const n of notices) {
      const li = document.createElement("li");
      const description = document.createElement("div");
      const heading = document.createElement("div"); heading.className = "notice-heading";
      heading.textContent = [n.source === "study_json" ? "研究配置" : "随访记录", n.visit_id, n.lesion_id, n.line ? `第 ${n.line} 行` : null].filter(Boolean).join(" · ");
      description.className = "notice-description"; description.textContent = noticeText(n);
      const detail = document.createElement("details"), summary = document.createElement("summary"), original = document.createElement("p"); summary.textContent = "查看原始诊断"; original.textContent = `${n.code} · ${n.field || "—"}${n.column ? " · 列 " + n.column : ""}：${n.message}`; detail.append(summary, original);
      const focus = document.createElement("button"); focus.textContent = "前往对应记录 →"; focus.type = "button";
      focus.addEventListener("click", () => { showView("records"); if ($("visit-filter")) { $("visit-filter").value = "all"; filterRows(); } const target = targetFor(n); if (target.closest("details")) target.closest("details").open = true; if (target.tagName === "TEXTAREA" && ["study-source", "csv-source"].includes(target.id)) $("source-details").open = true; target.focus(); });
      li.append(heading, description, detail, focus); parent.append(li);
      if (blocking) { const target = targetFor(n); target.classList.add("invalid"); target.setAttribute("aria-invalid", "true"); }
    }
  }
  updateButtons();
}

function validate() {
  if (!state.evaluate) return;
  const response = invoke(state.evaluate, { action: "preflight", ...source() });
  state.quality = response.preflight;
  renderQuality();
}

function changed(fromTable = false) {
  state.revision++;
  discardReport();
  if (fromTable) { const texts = serializeTable(state.model); $("study-source").value = texts.study_json; $("csv-source").value = texts.followup_csv; }
  draftStatus();
  validate();
}

function input(value, attrs = "", tag = "input") {
  return tag === "textarea" ? `<textarea ${attrs}>${esc(value)}</textarea>` : `<input type="text" value="${esc(value)}" ${attrs}>`;
}

function renderTables() {
  const host = $("table-editor");
  if (!state.model) { host.innerHTML = source().study_json || source().followup_csv ? '<p class="editing-note">原始文件有待确认的内容。可直接编辑原文，再点击“更新表格”。</p>' : ""; return; }
  const study = state.model.study;
  const fields = [["study_id", "研究编号"], ["baseline_date", "基线日期"], ["technique_id", "采集标识"], ["slice_thickness_mm", "CT 层厚 mm"]];
  const visits = [...new Set(state.model.rows.map(row => row[0]))];
  const targetRows = study.targets.map((t, i) => {
    const textCells = ["id", "organ"].map(k => `<td>${input(t[k], `data-study-path="targets[${i}].${k}" aria-label="基线 ${i + 1} ${k}"`)}</td>`).join("");
    return `<tr>${textCells}<td><select data-study-path="targets[${i}].kind" aria-label="基线 ${i + 1} kind"><option value="non_nodal" ${t.kind === "non_nodal" ? "selected" : ""}>非淋巴结 · 最长径</option><option value="lymph_node" ${t.kind === "lymph_node" ? "selected" : ""}>淋巴结 · 短轴</option></select></td><td>${input(t.baseline_mm, `inputmode="decimal" data-study-path="targets[${i}].baseline_mm" aria-label="基线 ${i + 1} baseline_mm"`)}</td><td><button data-remove-target="${i}" aria-label="删除基线病灶 ${i + 1}">删除</button></td></tr>`;
  }).join("");
  const observationRows = state.model.rows.map((row, i) => {
    const cells = row.map((cell, j) => {
      const attrs = `data-row="${i}" data-column="${j}" aria-label="观察 ${i + 1} ${COLUMNS[j]}"`;
      if (j === 4) return `<td><select ${attrs}>${[...new Set(["measured", "absent", "too_small", "missing", "not_evaluable", cell])].map(v => `<option value="${esc(v)}" ${v === cell ? "selected" : ""}>${esc(stateNames[v] || v)}</option>`).join("")}</select></td>`;
      return `<td>${input(cell, attrs + (j === 5 ? ' inputmode="decimal"' : ""), j === 6 ? "textarea" : "input")}</td>`;
    }).join("");
    return `<tr data-observation-row="${i}">${cells}<td><button data-remove-row="${i}" aria-label="删除观察 ${i + 1}">删除</button></td></tr>`;
  }).join("");
  host.innerHTML = `
    <details id="baseline-details" class="surface baseline-card">
      <summary class="surface-head"><div><h3>基线与靶病灶</h3><p>${study.targets.length} 个靶病灶 · 基线 ${esc(study.baseline_date)}</p></div><span>查看与编辑 <b>⌄</b></span></summary>
      <div class="surface-body"><div class="fields">${fields.map(([key, name]) => `<label>${name}${input(study[key], `data-study-path="${key}" aria-label="${name}"`)}</label>`).join("")}</div></div>
      <div class="surface-head"><div><h3>基线靶病灶</h3><p>非淋巴结记录最长径，淋巴结记录短轴。</p></div><button id="add-target" class="quiet">＋ 添加病灶</button></div>
      <div class="table-scroll"><table class="target-table"><thead><tr><th>病灶编号</th><th>器官组</th><th>病灶类型</th><th>基线直径 mm</th><th></th></tr></thead><tbody>${targetRows}</tbody></table></div>
    </details>
    <section class="surface"><div class="surface-head"><div><h2>随访观察</h2><p>逐次核对测量值，保留未测量与无法评价的原始观察。</p></div><label class="compact-label">随访<select id="visit-filter" aria-label="筛选随访"><option value="all">全部随访</option>${visits.map((v, i) => `<option value="${i}">${esc(v || "未填写编号")}</option>`).join("")}</select></label></div>
      <div class="table-scroll"><table class="observation-table"><thead><tr>${inputNames.map(n => `<th>${n}</th>`).join("")}<th></th></tr></thead><tbody>${observationRows}</tbody></table></div>
      <div class="table-foot"><button id="add-row" class="quiet">＋ 添加观察</button><p class="muted">${state.model.rows.length} 条观察 · 直径最多一位小数</p></div>
    </section>`;
  $("visit-filter").addEventListener("change", filterRows);
  host.querySelectorAll("[data-study-path]").forEach(el => el.addEventListener("input", () => {
    const match = el.dataset.studyPath.match(/^targets\[(\d+)\]\.(\w+)$/);
    if (match) study.targets[Number(match[1])][match[2]] = el.value;
    else study[el.dataset.studyPath] = el.value;
    changed(true);
  }));
  host.querySelectorAll("[data-row][data-column]").forEach(el => el.addEventListener("input", () => {
    state.model.rows[Number(el.dataset.row)][Number(el.dataset.column)] = el.value;
    if (Number(el.dataset.column) === 0) {
      $("visit-filter").innerHTML = '<option value="all">全部随访</option>' + [...new Set(state.model.rows.map(row => row[0]))].map((v, i) => `<option value="${i}">${esc(v || "未填写编号")}</option>`).join("");
      filterRows();
    }
    changed(true);
  }));
  const redraw = () => { const baselineOpen = $("baseline-details").open; changed(true); renderTables(); $("baseline-details").open = baselineOpen; renderQuality(); };
  host.querySelectorAll("[data-remove-target]").forEach(el => el.addEventListener("click", () => { study.targets.splice(Number(el.dataset.removeTarget), 1); redraw(); }));
  host.querySelectorAll("[data-remove-row]").forEach(el => el.addEventListener("click", () => { state.model.rows.splice(Number(el.dataset.removeRow), 1); redraw(); }));
  $("add-target").addEventListener("click", () => { study.targets.push({ id: "", organ: "", kind: "non_nodal", baseline_mm: "" }); redraw(); });
  $("add-row").addEventListener("click", () => { state.model.rows.push(["", "", study.technique_id, "", "missing", "", ""]); redraw(); });
}

function filterRows() {
  const selected = $("visit-filter").value;
  const visits = [...new Set(state.model.rows.map(row => row[0]))];
  document.querySelectorAll("[data-observation-row]").forEach(el => {
    el.hidden = selected !== "all" && state.model.rows[Number(el.dataset.observationRow)][0] !== visits[Number(selected)];
  });
}

function applySources() {
  const response = invoke(state.evaluate, { action: "editor", ...source() });
  state.model = response.ok ? response.result : null;
  state.quality = response.preflight;
  state.revision++;
  discardReport(); renderTables(); renderQuality(); draftStatus();
  message(response.ok ? "记录已载入，可以继续编辑或查看核查结果。" : "部分内容暂时无法载入表格，原始文件已保留。", !response.ok);
  if (!response.ok) $("source-details").open = true;
}

function replaceSources(sources) {
  $("study-source").value = sources.study_json; $("csv-source").value = sources.followup_csv;
  applySources();
}

function download(name, content, type = "text/plain") {
  const url = URL.createObjectURL(new Blob([content], { type: type + ";charset=utf-8" })); urls.push(url);
  const link = document.createElement("a"); link.href = url; link.download = name; link.click();
}

function localDraftStatus() {
  try {
    const text = localStorage.getItem(DRAFT_KEY);
    $("restore-draft").disabled = !text; $("clear-draft").disabled = !text;
    if (text) { const draft = readDraft(text); $("draft-status").textContent = `上次保存于 ${new Date(draft.saved_at).toLocaleString("zh-CN", { hour12: false })}。`; }
    else $("draft-status").textContent = "还没有本机草稿。点击右上角“保存草稿”可保留当前进度。";
  } catch (error) { $("draft-status").textContent = "暂时无法读取本机草稿：" + error.message; }
}

function restore(text, savedOnDevice) {
  const draft = readDraft(text); // Validate the whole container before changing any input.
  $("language").value = draft.language;
  replaceSources(draft);
  state.saved = savedOnDevice ? signature() : null;
  showView("records");
  $("draft-status").textContent = savedOnDevice ? "草稿已恢复，可以继续复核。" : "草稿文件已载入，尚未保存到本机。";
}

bind("load-example", () => {
  const result = invoke(state.evaluate, { action: "template", template: $("template").value, language: "zh-CN" });
  const files = Object.fromEntries(result.result.files.map(file => [file.name, file.content]));
  replaceSources({ study_json: files["study.json"], followup_csv: files["followup.csv"] });
  $("import-dialog").close(); showView("records");
  $("input-status").textContent = "当前使用合成示例，可自由编辑并体验完整流程。";
});
bind("import-inputs", async () => {
  const study = $("study-file").files[0], csv = $("csv-file").files[0];
  if (!study || !csv) throw new Error("请同时选择研究 JSON 与随访 CSV。");
  state.busy = true; updateButtons();
  const revision = state.revision;
  try { const texts = await Promise.all([study.text(), csv.text()]); if (revision !== state.revision) throw new Error("读取文件期间输入已改变，请重新导入。"); replaceSources({ study_json: texts[0], followup_csv: texts[1] }); $("input-status").textContent = `${study.name} · ${csv.name}`; $("import-dialog").close(); showView("records"); }
  finally { state.busy = false; updateButtons(); }
});
bind("apply-source", applySources);
bind("check-input", () => { validate(); message(state.quality.valid ? "记录检查完成，人工核查项已列在下方。" : "有记录需要调整，请查看下方提示。", !state.quality.valid); });
for (const id of ["study-source", "csv-source"]) $(id).addEventListener("input", () => { state.model = null; renderTables(); changed(); });
$("language").addEventListener("change", () => changed());
bind("save-draft", () => { const text = makeDraft(source(), $("language").value); localStorage.setItem(DRAFT_KEY, text); state.saved = signature(); localDraftStatus(); draftStatus(); message("草稿已保存，下次打开可从“草稿”中恢复。"); });
bind("restore-draft", () => { const text = localStorage.getItem(DRAFT_KEY); if (!text) throw new Error("本机没有草稿。"); restore(text, true); });
bind("clear-draft", () => { localStorage.removeItem(DRAFT_KEY); state.saved = null; localDraftStatus(); message("本机草稿已清除，当前正在编辑的记录不受影响。"); });
bind("export-draft", () => download("lesion-followup-draft.json", makeDraft(source(), $("language").value), "application/json"));
bind("import-draft", async () => { const file = $("draft-file").files[0]; if (!file) throw new Error("请选择草稿文件。"); const revision = state.revision; const text = await file.text(); if (revision !== state.revision) throw new Error("读取草稿期间输入已改变，请重新载入。"); restore(text, false); });
bind("export-study", () => download("study.json", source().study_json, "application/json"));
bind("export-csv", () => download("followup.csv", source().followup_csv, "text/csv"));
bind("generate-report", async () => {
  validate(); if (!state.quality?.valid) throw new Error("请先完成记录修正，再生成报告。");
  const revision = state.revision;
  state.busy = true; updateButtons();
  try {
    const report = await createReview(state.evaluate, source(), $("language").value);
    if (revision !== state.revision) { message("输入已改变，请重新生成当前报告。"); return; }
    state.report = report;
    const labels = { CR: "完全缓解", PR: "部分缓解", SD: "稳定", PD: "进展", NE: "无法评价" };
    $("report-summary").innerHTML = `<p class="distribution-title">靶病灶分类分布</p><div class="counts">${Object.entries(report.audit.summary.response_counts).map(([code, count]) => `<div><span class="response-code">${esc(code)}</span><small>${labels[code]}</small><strong>${count}<span>次</span></strong></div>`).join("")}</div><details class="provenance"><summary>查看本次输入标识</summary><p class="fingerprint">SHA-256 · ${report.fingerprint}</p></details>`;
    const last = report.audit.assessments.at(-1);
    $("report-overview").innerHTML = `<div class="review-grid"><section class="surface trend-card"><div class="surface-head"><div><h3>靶病灶总和趋势</h3><p>NE 随访保留间隔，不进入最低值计算。</p></div><span class="unit-tag">mm</span></div><div class="trend-plot">${report.outputs.svg}</div></section><section class="surface latest-card"><p class="muted">最近一次随访</p><h3>${esc(last?.visit_id || "暂无随访")}</h3><p class="latest-date">${esc(last?.date || "—")}</p><div class="latest-size">${esc(last?.sum_mm ?? "—")}<small>mm</small></div><span class="latest-response">${esc(last?.target_response || "—")} · ${last ? labels[last.target_response] : "暂无评价"}</span><dl><div><dt>基线总和</dt><dd>${esc(last?.baseline_sum_mm ?? "—")} mm</dd></div><div><dt>此前最低值</dt><dd>${esc(last?.prior_nadir_mm ?? "—")} mm</dd></div><div><dt>最低值来源</dt><dd>${esc(last?.prior_nadir_visit_id ?? "—")}</dd></div></dl></section></div>`;
    $("report-evidence").open = false;
    $("report-tools").hidden = false; $("report-empty").hidden = true; showView("report");
    $("report-preview").srcdoc = report.outputs.html; $("report-preview").hidden = false;
    $("report-status").textContent = `共 ${report.audit.assessments.length} 次随访，趋势、测量明细与打印内容均基于当前记录。`;
    message("报告已更新，可查看测量依据、导出或打印。");
  } finally { state.busy = false; updateButtons(); }
});
bind("export-report", () => {
  if (!state.report) throw new Error("请先生成当前报告。");
  const format = $("report-format").value;
  const extensions = { html: "html", json: "json", csv: "csv", markdown: "md", svg: "svg" };
  download("target-review." + extensions[format], state.report.outputs[format]);
});
for (const mode of ["summary", "full"]) bind("print-" + mode, () => {
  if (!state.report) throw new Error("请先生成当前报告。");
  printShadow.innerHTML = printFragment(printDocument(state.report, mode));
  $("print-mode").value = mode;
  $("inline-print").hidden = false;
  $("inline-print").scrollIntoView({ block: "start" });
  $("print-heading").textContent = mode === "summary" ? "摘要打印预览" : "完整证据打印预览";
  message("页面内打印视图已展开；可打印或导出独立打印 HTML。");
});
bind("close-print", () => { $("inline-print").hidden = true; showView("report"); $("report-status").scrollIntoView({ block: "center" }); });
bind("print-page", () => { if (!state.report || $("inline-print").hidden) throw new Error("请先预览当前打印视图。"); window.print(); });
bind("export-print", () => {
  if (!state.report) throw new Error("请先生成当前报告。");
  const mode = $("print-mode").value;
  download("target-review-print-" + mode + ".html", printDocument(state.report, mode), "text/html");
});
window.addEventListener("pagehide", () => urls.forEach(url => URL.revokeObjectURL(url)));

try {
  state.evaluate = (await import("./browser.js")).evaluate;
  updateButtons(); localDraftStatus(); message("工作区已就绪，所有测量均在本机处理。");
} catch (error) { message("本地计算模块载入失败：" + error.message, true); }
