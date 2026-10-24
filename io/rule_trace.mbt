///|
fn checks_json(a : @evidence.VisitAssessment) -> Json {
  let checks : Array[Json] = @replay.explain_assessment(a).map(c => {
    "code": c.code,
    "lesion_id": optional_string(c.lesion_id),
    "left": optional_int(c.left),
    "operator": c.operator,
    "right": c.right,
    "passed": match c.passed {
      Some(v) => v.to_json()
      None => Json::null()
    },
    "active": c.active,
  })
  checks.to_json()
}

///|
fn trace_context(
  a : @evidence.VisitAssessment,
  language : ReportLanguage,
) -> String {
  let components = a.measurements
    .map(m => m.lesion_id + "=" + mm_or_missing(m.effective_tenths_mm))
    .join(" + ")
  tr(language, "Diameter components / mm: ", "直径组成 / mm：") +
  components +
  " → S=" +
  mm_or_missing(a.sum_tenths_mm) +
  "; B=" +
  format_diameter_mm(a.baseline_sum_tenths_mm) +
  "; N=" +
  format_diameter_mm(a.nadir_sum_tenths_mm) +
  " (" +
  a.nadir_visit_id +
  "). " +
  tr(
    language, "S=current sum; B=baseline; N=prior eligible minimum. Comparisons below use 0.1 mm integers and integer cross-products. Inactive criteria are skipped by an earlier gate. Findings explain NE and history gates.",
    "S 为本次总和，B 为基线，N 为此前可用最低值。下表采用 0.1 mm 整数及整数交叉乘积；未启用项被更早的条件阻断。NE 与历史背景门槛见复核提示。",
  )
}

///|
fn check_status(c : @evidence.RuleCheck, language : ReportLanguage) -> String {
  let outcome = match c.passed {
    Some(true) => tr(language, "true", "满足")
    Some(false) => tr(language, "false", "不满足")
    None => tr(language, "unavailable", "不可用")
  }
  outcome +
  " / " +
  tr(
    language,
    if c.active {
      "active"
    } else {
      "inactive"
    },
    if c.active {
      "启用"
    } else {
      "未启用"
    },
  )
}

///|
fn check_label(code : String, language : ReportLanguage) -> String {
  match code {
    "complete_measurements" =>
      tr(language, "Complete measurements", "测量完整")
    "comparable_technique" =>
      tr(language, "Matching technique ID", "采集标识一致")
    "context_open" =>
      tr(language, "History gate open", "既往背景门槛未阻断")
    "non_nodal_cr" =>
      tr(language, "Non-nodal CR: 0.0 mm", "非淋巴结 CR：0.0 mm")
    "node_cr_short_axis" =>
      tr(
        language, "Node CR: short axis below 10.0 mm", "淋巴结 CR：短轴小于 10.0 mm",
      )
    "pd_relative_5S_ge_6N" =>
      tr(language, "PD relative growth: 5S >= 6N", "PD 相对增幅：5S >= 6N")
    "pd_absolute_S_minus_N_ge_50" =>
      tr(
        language, "PD absolute increase: at least 5.0 mm", "PD 绝对增加：至少 5.0 mm",
      )
    _ =>
      tr(
        language, "PR from baseline: 10S <= 7B", "PR 较基线缩小：10S <= 7B",
      )
  }
}

///|
fn trace_html(
  a : @evidence.VisitAssessment,
  language : ReportLanguage,
) -> String {
  let out = StringBuilder()
  out.write_string(
    "<h3>" +
    tr(language, "Exact calculation conditions", "逐条件计算解释") +
    "</h3><p>" +
    html_escape(trace_context(a, language)) +
    "</p><div class=\"table-scroll\"><table><thead><tr>" +
    tr(
      language, "<th>Criterion / target</th><th>Integer comparison</th><th>Result / use</th>",
      "<th>条件 / 病灶</th><th>整数比较</th><th>结果 / 是否启用</th>",
    ) +
    "</tr></thead><tbody>",
  )
  for c in @replay.explain_assessment(a) {
    out.write_string(
      "<tr><td>" +
      html_escape(check_label(c.code, language)) +
      "<br><code>" +
      c.code +
      "</code> " +
      html_escape(c.lesion_id.unwrap_or("")) +
      "</td><td>" +
      c.left.map(v => v.to_string()).unwrap_or("n/a") +
      " " +
      html_escape(c.operator) +
      " \{c.right}</td><td>" +
      check_status(c, language) +
      "</td></tr>",
    )
  }
  out.write_string("</tbody></table></div>")
  out.to_string()
}

///|
fn trace_markdown(
  a : @evidence.VisitAssessment,
  language : ReportLanguage,
) -> String {
  let out = StringBuilder()
  out.write_string(
    "\n### " +
    tr(language, "Exact calculation conditions", "逐条件计算解释") +
    "\n\n" +
    markdown_escape(trace_context(a, language)) +
    "\n\n" +
    tr(
      language, "| Criterion / target | Integer comparison | Result / use |\n", "| 条件 / 病灶 | 整数比较 | 结果 / 是否启用 |\n",
    ) +
    "|---|---|---|\n",
  )
  for c in @replay.explain_assessment(a) {
    out.write_string(
      "| " +
      markdown_escape(check_label(c.code, language)) +
      " / " +
      c.code +
      " " +
      markdown_escape(c.lesion_id.unwrap_or("")) +
      " | " +
      c.left.map(v => v.to_string()).unwrap_or("n/a") +
      " " +
      c.operator +
      " \{c.right} | " +
      check_status(c, language) +
      " |\n",
    )
  }
  out.to_string()
}
