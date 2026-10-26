import { createVisitPlanner, visitSummaries } from "./visit-editor.mjs";
import { escapeHtml as esc } from "./workbench.mjs";

export function mountVisitEditor({ getEvaluate, getSources, getModel, getQuality, getRevision, getBusy, apply, noticeText, notify }) {
  const $ = id => document.getElementById(id);
  let mode = "append", revision = getRevision();
  const planner = createVisitPlanner(request => getEvaluate()(request), getRevision, apply);
  const titles = { append: "新增一次随访", update: "修改随访信息", remove: "移除这次随访" };
  function invalidate(text = "填写后先检查，再确认应用到当前记录。") {
    planner.invalidate(); $("visit-edit-preview").hidden = true;
    $("visit-edit-status").textContent = text; refresh();
  }
  function setMode(value) {
    mode = value;
    $("visit-dialog-title").textContent = titles[mode];
    $("visit-existing-label").hidden = mode === "append";
    $("remove-visit").hidden = mode !== "update";
    $("visit-fields").hidden = mode === "remove";
    $("visit-dialog-help").textContent = mode === "append" ? "为每个基线靶病灶建立一条未测量观察，再逐项补充本次读片结果。" :
      mode === "update" ? "编号、日期与采集标识会同步到本次全部观察，已有测量值和说明保持原样。" : "将移除本次全部观察，其他随访保持原样。应用后可在测量记录中撤销。";
    $("apply-visit-edit").textContent = mode === "append" ? "确认新增随访" : mode === "update" ? "保存随访信息" : "确认移除随访";
    invalidate();
  }
  function fillExisting() {
    const selected = visitSummaries(getModel()).find(visit => visit.id === $("visit-existing").value);
    if (selected) {
      $("visit-id").value = selected.id; $("visit-date").value = selected.date; $("visit-technique").value = selected.technique_id;
    }
    invalidate();
  }
  function refresh() {
    const next = getRevision();
    if (revision !== next) {
      revision = next;
      invalidateWithoutRefresh();
    }
    const ready = !!getEvaluate() && !!getModel() && !!getQuality()?.valid && !getBusy();
    if ($("new-visit")) $("new-visit").disabled = !ready;
    if ($("manage-visit")) $("manage-visit").disabled = !ready || !getModel()?.rows.length;
    $("preview-visit-edit").disabled = !ready;
    $("apply-visit-edit").disabled = !ready || !planner.canApply();
  }
  function invalidateWithoutRefresh() {
    planner.invalidate(); $("visit-edit-preview").hidden = true;
    if ($("visit-dialog").open) $("visit-edit-status").textContent = "当前记录已更新，请关闭窗口后重新选择随访。";
  }
  function open(kind, selectedId = null) {
    if (!getQuality()?.valid || !getModel() || getBusy()) return;
    const visits = visitSummaries(getModel());
    $("visit-existing").innerHTML = visits.map(visit => `<option value="${esc(visit.id)}">${esc(visit.id)} · ${esc(visit.date)} · ${visit.observations} 条观察</option>`).join("");
    if (selectedId) $("visit-existing").value = selectedId;
    revision = getRevision(); setMode(kind);
    if (kind === "append") {
      $("visit-id").value = ""; $("visit-date").value = ""; $("visit-technique").value = getModel().study.technique_id;
    } else fillExisting();
    $("visit-dialog").showModal(); $(kind === "append" ? "visit-id" : "visit-date").focus();
  }
  $("close-visit-dialog").addEventListener("click", () => $("visit-dialog").close());
  $("visit-dialog").addEventListener("close", () => invalidate());
  for (const id of ["visit-id", "visit-date", "visit-technique"]) $(id).addEventListener("input", () => invalidate());
  $("visit-existing").addEventListener("change", fillExisting);
  $("remove-visit").addEventListener("click", () => setMode("remove"));
  $("preview-visit-edit").addEventListener("click", () => {
    invalidate();
    const operation = mode === "remove" ? { kind: mode, visit_id: $("visit-existing").value } :
      { kind: mode, ...(mode === "update" ? { visit_id: $("visit-existing").value } : {}),
        id: $("visit-id").value, date: $("visit-date").value, technique_id: $("visit-technique").value };
    try {
      const summary = planner.preview(getSources(), operation);
      $("visit-edit-preview").textContent = `${summary.id} · ${summary.date}：${mode === "append" ? "新增" : mode === "remove" ? "移除" : "更新"} ${summary.observations} 条观察。应用后共 ${summary.visit_count} 次随访、${summary.hint_count} 项人工核查提示。${mode === "append" ? "直径留空，需补充本次测量。" : ""}`;
      $("visit-edit-preview").hidden = false;
      $("visit-edit-status").textContent = "随访信息检查通过，请确认后应用。";
    } catch (error) {
      const issue = error.preflight && [...error.preflight.diagnostics, ...error.preflight.input_issues][0];
      $("visit-edit-status").textContent = issue ? noticeText(issue) : error.message;
    }
    refresh();
  });
  $("apply-visit-edit").addEventListener("click", () => {
    if (getBusy()) return;
    try { planner.apply(); $("visit-dialog").close(); }
    catch (error) { invalidate(error.message); notify(error.message, true); }
  });
  refresh(); return { open, refresh };
}
