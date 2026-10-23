///|
/// Presentation language only. Machine-readable codes and reader notes stay intact.
pub(all) enum ReportLanguage {
  English
  SimplifiedChinese
} derive(Debug, Eq)

///|
pub extend ReportLanguage with @debug.Debug::{to_repr}

///|
pub extend ReportLanguage with Eq::{equal, not_equal}

///|
fn tr(language : ReportLanguage, english : String, chinese : String) -> String {
  match language {
    English => english
    SimplifiedChinese => chinese
  }
}

///|
fn axis_label(kind : @lesion.LesionKind, language : ReportLanguage) -> String {
  match kind {
    NonNodal => tr(language, "Longest diameter", "最长径")
    LymphNode => tr(language, "Node short axis", "淋巴结短轴")
  }
}

///|
fn observation_label(
  observation : @visit.Observation,
  language : ReportLanguage,
) -> String {
  match observation {
    Measured(_) => tr(language, "measured", "实际测量")
    Absent => tr(language, "absent (0.0 mm)", "明确消失（0.0 mm）")
    TooSmallToMeasure =>
      tr(
        language, "too_small (5.0 mm default)", "可见但过小（默认 5.0 mm）",
      )
    Missing => tr(language, "missing (no value)", "漏测（无数值）")
    NotEvaluable(_) =>
      tr(
        language, "not_evaluable (reader reason)", "无法评价（读片者说明）",
      )
  }
}

///|
fn finding_label(
  finding : @evidence.Finding,
  language : ReportLanguage,
) -> String {
  if language == English {
    return finding.message
  }
  match finding.code {
    "default_5mm" =>
      "靶病灶可见但无法可靠测量；使用明确标注的 5.0 mm 默认值。"
    "missing_measurement" =>
      "缺少靶病灶测量；不推算直径，也不填为零。"
    "reader_not_evaluable" => "读片者说明：" + finding.message
    "node_below_10mm" =>
      "淋巴结短轴小于 10.0 mm；实际直径仍保留在总和中。"
    "technique_mismatch" =>
      "采集标识与基线不同；可比性需要人工复核。"
    "target_cr" =>
      "全部靶病灶符合本规则配置的靶病灶完全缓解条件。"
    "target_pr" =>
      "直径总和较基线减少至少 30%，且不满足靶病灶 PD 条件。"
    "target_pd" =>
      "相对于此前可用最低值，同时满足至少 20% 增长及至少 5.0 mm 绝对增加。"
    "target_sd" =>
      "靶病灶测量未达到 CR、PR 或同时满足的两项 PD 条件。"
    "prior_pr_context_required" =>
      "此前靶病灶 PR 不再达到基线缩小阈值，且未满足 PD；确认与持续性需要额外评价背景。"
    "reappearance_after_target_cr" =>
      "靶病灶 CR 后再次出现；需要整体评价背景，本次及后续随访保留为 NE。"
    "track_requires_review" =>
      "此前的进展或背景复核门槛持续生效；本次随访保留为 NE。"
    "no_followup" => "尚未提供随访记录。"
    _ => "复核提示：" + finding.message
  }
}

///|
fn glossary(language : ReportLanguage) -> String {
  tr(
    language, "Target-only terms: CR complete response; PR partial response; SD stable disease; PD progressive disease; NE not evaluable. Baseline is the initial target sum; prior nadir is the lowest earlier eligible sum. n/a means unavailable, never zero.",
    "靶病灶术语：CR 完全缓解；PR 部分缓解；SD 疾病稳定；PD 疾病进展；NE 无法评价。基线是初始靶病灶总和；此前最低值是更早可用随访中的最小总和。n/a 表示数值不可用，不代表零。",
  )
}

///|
/// Localized diagnostic summary; the original detail is retained verbatim.
fn diagnostic_message(
  code : String,
  detail : String,
  language : ReportLanguage,
) -> String {
  if language == English {
    return detail
  }
  let summary = match code {
    "json_syntax" => "JSON 语法错误"
    "study_schema" => "研究配置字段不符合约定"
    "csv_header" => "CSV 表头不符合约定"
    "csv_columns" => "CSV 列数不正确"
    "csv_quoting" => "CSV 引号格式错误"
    "csv_diameter" => "CSV 直径格式或精度不正确"
    "csv_state" => "观察状态与直径或说明不匹配"
    "csv_metadata" => "同次随访的日期或采集标识不一致"
    "csv_visit_order" => "同次随访的记录必须连续"
    "invalid_date" => "日期无效"
    "visit_order" => "随访日期须在基线之后严格递增"
    "duplicate_id" => "标识重复或使用了保留标识"
    "unknown_target" => "测量引用了基线集合之外的病灶"
    "invalid_study" => "研究或随访元数据不符合约定"
    "invalid_target" => "基线靶病灶不符合输入约定"
    "invalid_measurement" => "测量值或无法评价的说明不符合约定"
    "target_count" => "靶病灶数量不符合约定"
    "organ_target_count" => "同一器官组的靶病灶数量超限"
    _ => "请核对输入或复核背景"
  }
  summary + "（" + detail + "）"
}
