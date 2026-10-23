///|
/// A source location or visit anchor. Missing rows have no fabricated field location.
pub(all) struct ReviewNotice {
  code : String
  message : String
  source : String
  field : String?
  line : Int?
  column : Int?
  visit_id : String?
  lesion_id : String?
} derive(Debug, Eq)

///|
pub extend ReviewNotice with @debug.Debug::{to_repr}

///|
pub extend ReviewNotice with Eq::{equal, not_equal}

///|
/// Parse errors and structural errors block replay; review hints do not.
pub(all) struct PreflightReport {
  visit_count : Int
  diagnostics : Array[ReviewNotice]
  input_issues : Array[ReviewNotice]
  review_hints : Array[ReviewNotice]
} derive(Debug, Eq)

///|
pub extend PreflightReport with @debug.Debug::{to_repr}

///|
pub extend PreflightReport with Eq::{equal, not_equal}

///|
pub fn PreflightReport::is_valid(self : PreflightReport) -> Bool {
  self.diagnostics.is_empty() && self.input_issues.is_empty()
}

///|
fn notice(
  code : String,
  message : String,
  visit_id? : String,
  lesion_id? : String,
) -> ReviewNotice {
  {
    code,
    message,
    source: "memory",
    field: None,
    line: None,
    column: None,
    visit_id,
    lesion_id,
  }
}

///|
/// Inspect the validated track using the same replay findings as the report.
/// This preflight supplies no response categories and never changes input values.
pub fn preflight_track(
  study : @lesion.Study,
  visits : Array[@visit.Visit],
) -> PreflightReport {
  let issues = @replay.validate_track(study, visits).map(i => {
    notice(
      i.code.code(),
      i.message,
      visit_id?=i.visit_id,
      lesion_id?=i.lesion_id,
    )
  })
  let hints = []
  if issues.is_empty() {
    if visits.is_empty() {
      hints.push(notice("no_followup", "No follow-up visits were supplied."))
    }
    if @replay.replay_track(study, visits) is Ok(trajectory) {
      for a in trajectory.assessments {
        for f in a.findings {
          if [
              "missing_measurement", "reader_not_evaluable", "default_5mm", "technique_mismatch",
              "track_requires_review", "reappearance_after_target_cr", "prior_pr_context_required",
            ].contains(f.code) {
            hints.push(
              notice(
                f.code,
                f.message,
                visit_id=a.visit_id,
                lesion_id?=f.lesion_id,
              ),
            )
          }
        }
      }
    }
  }
  {
    visit_count: visits.length(),
    diagnostics: [],
    input_issues: issues,
    review_hints: hints,
  }
}

///|
fn id_valid(text : String) -> Bool {
  !text.is_blank() &&
  text == text.trim().to_owned() &&
  text.length() <= 128 &&
  text.iter().all(c => c.to_int() >= 32 && c.to_int() != 127)
}

///|
fn locate_notice(
  item : ReviewNotice,
  study : @lesion.Study,
  rows : Array[Array[CsvCell]],
) -> ReviewNotice {
  if item.visit_id is Some(id) {
    let matches = rows.filter(row => {
      row.length() == 7 &&
      row[0].text == id &&
      (match item.lesion_id {
        Some(target) => row[3].text == target
        None => true
      })
    })
    let mut field = match item.code {
      "invalid_date" | "visit_order" => 1
      "unknown_target" | "duplicate_id" =>
        if item.lesion_id is Some(_) {
          3
        } else {
          0
        }
      "invalid_study" =>
        if !matches.is_empty() && !id_valid(matches[0][0].text) {
          0
        } else {
          2
        }
      "invalid_measurement" => 5
      "technique_mismatch" => 2
      "reader_not_evaluable" => 6
      "track_requires_review"
      | "reappearance_after_target_cr"
      | "prior_pr_context_required" => 0
      _ => 4
    }
    if !matches.is_empty() {
      let row = if item.code == "duplicate_id" {
        matches[matches.length() - 1]
      } else {
        matches[0]
      }
      if item.code == "invalid_measurement" && row[4].text == "not_evaluable" {
        field = 6
      }
      let names = [
        "visit_id", "date", "technique_id", "lesion_id", "state", "diameter_mm",
        "note",
      ]
      return {
        ..item,
        source: "followup_csv",
        field: Some(names[field]),
        line: Some(row[field].line),
        column: Some(row[field].column),
      }
    }
    // An omitted target has no cell: point at the visit, without naming a field.
    for row in rows {
      if row.length() == 7 && row[0].text == id {
        return {
          ..item,
          source: "followup_csv",
          line: Some(row[0].line),
          column: Some(row[0].column),
        }
      }
    }
    return { ..item, source: "followup_csv", }
  }
  let mut field = match item.code {
    "invalid_date" => "$.baseline_date"
    "target_count" => "$.targets"
    "no_followup" =>
      return { ..item, source: "followup_csv", line: Some(1), column: Some(1), }
    _ =>
      if item.message.has_prefix("This version supports CT slices") {
        "$.slice_thickness_mm"
      } else if !id_valid(study.id) {
        "$.study_id"
      } else {
        "$.technique_id"
      }
  }
  if item.lesion_id is Some(id) {
    for i, target in study.targets {
      if target.id == id {
        let part = match item.code {
          "duplicate_id" => "id"
          "organ_target_count" => "organ"
          "invalid_target" if item.message.has_prefix("Baseline diameter") =>
            "baseline_mm"
          "invalid_target" if item.message.has_prefix("All lymph-node targets") =>
            "organ"
          _ =>
            if !id_valid(target.id) {
              "id"
            } else if !id_valid(target.organ) ||
              (target.kind is LymphNode) != (target.organ == "lymph_nodes") {
              "organ"
            } else {
              "baseline_mm"
            }
        }
        field = "$.targets[\{i}].\{part}"
        if item.code != "duplicate_id" {
          break
        }
      }
    }
  }
  { ..item, source: "study_json", field: Some(field), }
}

///|
/// Combined JSON/CSV preflight with physical CSV locations and JSON field paths.
/// Review hints are only derived after both inputs parse and validate in full.
pub fn preflight_inputs(
  study_text : String,
  csv_text : String,
) -> PreflightReport {
  let diagnostics = []
  let study = match parse_study_json(study_text) {
    Ok(value) => Some(value)
    Err(errors) => {
      for d in errors {
        diagnostics.push({
          ..notice(d.code, d.message),
          source: "study_json",
          field: d.field,
          line: d.line,
          column: d.column,
        })
      }
      None
    }
  }
  let visits = match parse_followup_csv(csv_text) {
    Ok(value) => Some(value)
    Err(errors) => {
      for d in errors {
        diagnostics.push({
          ..notice(d.code, d.message),
          source: "followup_csv",
          field: d.field,
          line: d.line,
          column: d.column,
        })
      }
      None
    }
  }
  guard study is Some(study) && visits is Some(visits) else {
    return {
      visit_count: match visits {
        Some(v) => v.length()
        None => 0
      },
      diagnostics,
      input_issues: [],
      review_hints: [],
    }
  }
  let result = preflight_track(study, visits)
  let rows = match csv_rows(csv_text) {
    Ok(rows) => rows[1:].to_owned()
    Err(_) => []
  }
  {
    ..result,
    input_issues: result.input_issues.map(i => locate_notice(i, study, rows)),
    review_hints: result.review_hints.map(i => locate_notice(i, study, rows)),
  }
}

///|
fn notice_json(item : ReviewNotice) -> Json {
  {
    "code": item.code,
    "message": item.message,
    "source": item.source,
    "field": optional_string(item.field),
    "line": optional_int(item.line),
    "column": optional_int(item.column),
    "visit_id": optional_string(item.visit_id),
    "lesion_id": optional_string(item.lesion_id),
  }
}

///|
/// Additive validation schema: machine-readable messages and codes are language independent.
pub fn render_preflight_json(report : PreflightReport) -> String {
  let document : Json = {
    "schema_version": 1,
    "valid": report.is_valid(),
    "visit_count": report.visit_count,
    "scope": "input_quality_and_review_hints",
    "diagnostics": report.diagnostics.map(notice_json).to_json(),
    "input_issues": report.input_issues.map(notice_json).to_json(),
    "review_hints": report.review_hints.map(notice_json).to_json(),
  }
  document.stringify(indent=2) + "\n"
}

///|
pub fn render_preflight_markdown(
  report : PreflightReport,
  language? : ReportLanguage = English,
) -> String {
  let out = StringBuilder()
  out.write_string(
    tr(language, "# Input quality preflight\n\n", "# 输入质量预检\n\n"),
  )
  out.write_string(
    tr(language, "Visits", "随访数") +
    ": \{report.visit_count}; " +
    tr(language, "Parse issues", "解析问题") +
    ": \{report.diagnostics.length()}; " +
    tr(language, "Structural issues", "结构问题") +
    ": \{report.input_issues.length()}; " +
    tr(language, "Review hints", "复核提示") +
    ": \{report.review_hints.length()}\n\n",
  )
  out.write_string(
    tr(
      language, "Valid input does not establish clinical comparability or overall response. Reader notes are preserved.\n",
      "输入有效不代表已确认临床可比性或整体疗效。读片者原始说明保留。\n",
    ),
  )
  for
    (heading, items) in [
      (tr(language, "Parse issues", "解析问题"), report.diagnostics),
      (tr(language, "Structural issues", "结构问题"), report.input_issues),
      (tr(language, "Review hints", "人工复核提示"), report.review_hints),
    ] {
    out.write_string("\n## " + heading + "\n\n")
    if items.is_empty() {
      out.write_string(tr(language, "None.\n", "无。\n"))
    }
    for item in items {
      let location = match (item.line, item.column) {
        (Some(line), Some(column)) => ":\{line}:\{column}"
        _ => ""
      }
      let detail = if heading ==
        tr(language, "Review hints", "人工复核提示") {
        finding_label(
          { code: item.code, message: item.message, lesion_id: item.lesion_id, },
          language,
        )
      } else {
        diagnostic_message(item.code, item.message, language)
      }
      out.write_string(
        "- `" +
        item.code +
        "` " +
        markdown_escape(
          item.source +
          location +
          " " +
          item.field.unwrap_or("") +
          " " +
          item.visit_id.unwrap_or("") +
          " " +
          item.lesion_id.unwrap_or(""),
        ) +
        ": " +
        markdown_escape(detail) +
        "\n",
      )
    }
  }
  out.to_string()
}
