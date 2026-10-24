///|
pub(all) struct BatchCase {
  id : String
  study : String
  input : String
} derive(Debug, Eq)

///|
pub extend BatchCase with @debug.Debug::{to_repr}

///|
pub extend BatchCase with Eq::{equal, not_equal}

///|
pub(all) struct BatchResult {
  id : String
  status : String
  message : String
  report_path : String?
  visit_count : Int
  review_hint_count : Int
} derive(Debug, Eq)

///|
pub extend BatchResult with @debug.Debug::{to_repr}

///|
pub extend BatchResult with Eq::{equal, not_equal}

///|
fn safe_case_id(id : String) -> Bool {
  if id.is_empty() ||
    id.length() > 64 ||
    !id
    .iter()
    .all(c => {
      (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '_' ||
      c == '-'
    }) {
    return false
  }
  let lower = id.to_lower()
  ![
    "con", "prn", "aux", "nul", "com1", "com2", "com3", "com4", "com5", "com6", "com7",
    "com8", "com9", "lpt1", "lpt2", "lpt3", "lpt4", "lpt5", "lpt6", "lpt7", "lpt8",
    "lpt9",
  ].contains(lower)
}

///|
fn decode_batch(value : Json) -> Array[BatchCase] raise StudyDecodeError {
  let root = object(value, "$", ["schema_version", "cases"])
  guard required(root, "schema_version", "$") is Number(1.0, ..) else {
    raise StudyDecodeError(
      "$.schema_version", "Only batch schema version 1 is supported.",
    )
  }
  guard required(root, "cases", "$") is Array(cases) &&
    !cases.is_empty() &&
    cases.length() <= 1000 else {
    raise StudyDecodeError("$.cases", "Expected between 1 and 1000 cases.")
  }
  let result : Array[BatchCase] = []
  let seen : Map[String, Bool] = Map([])
  for i, value in cases {
    let path = "$.cases[\{i}]"
    let item = object(value, path, ["id", "study", "input"])
    let id = string_field(item, "id", path)
    if !safe_case_id(id) || seen.contains(id.to_lower()) {
      raise StudyDecodeError(
        path + ".id",
        "Use a unique portable ID (ASCII letters, digits, underscore or hyphen); device names are reserved.",
      )
    }
    seen[id.to_lower()] = true
    let study = string_field(item, "study", path)
    let input = string_field(item, "input", path)
    if study.is_blank() ||
      input.is_blank() ||
      study.contains_char('\u{0}') ||
      input.contains_char('\u{0}') {
      raise StudyDecodeError(
        path, "Study and input file paths must be nonblank without NUL.",
      )
    }
    result.push({ id, study, input, })
  }
  result
}

///|
/// Paths are resolved by the CLI relative to the batch manifest, never the CWD.
pub fn parse_batch_json(
  text : String,
) -> Result[Array[BatchCase], Array[Diagnostic]] {
  let value = @json.parse(text) catch {
    error => return Err([diagnostic("batch_schema", error.to_string())])
  }
  try decode_batch(value) catch {
    StudyDecodeError(path, message) =>
      Err([diagnostic("batch_schema", message, field=path)])
  } noraise {
    cases => Ok(cases)
  }
}

///|
pub fn render_batch_index_json(results : Array[BatchResult]) -> String {
  let entries : Array[Json] = results.map(r => {
    "id": r.id,
    "status": r.status,
    "message": r.message,
    "report_path": optional_string(r.report_path),
    "visit_count": r.visit_count,
    "review_hint_count": r.review_hint_count,
  })
  let document : Json = {
    "schema_version": 1,
    "scope": "target_lesions_only",
    "case_count": results.length(),
    "success_count": results.filter(r => r.status == "success").length(),
    "failure_count": results.filter(r => r.status != "success").length(),
    "cases": entries.to_json(),
  }
  document.stringify(indent=2) + "\n"
}

///|
pub fn render_batch_index_html(
  results : Array[BatchResult],
  language? : ReportLanguage = English,
) -> String {
  let out = StringBuilder()
  out.write_string(
    "<!doctype html><html lang=\"" +
    tr(language, "en", "zh-CN") +
    "\"><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>" +
    tr(language, "Batch review index", "批量复核索引") +
    "</title><style>body{max-width:1100px;margin:40px auto;padding:24px;font:14px/1.7 system-ui;background:#f6f3ed;color:#263348}table{width:100%;border-collapse:collapse;background:white}td,th{padding:14px;border-bottom:1px solid #ddd;text-align:left;overflow-wrap:anywhere}a{color:#247b68}</style><h1>" +
    tr(language, "Batch target-lesion review", "批量靶病灶复核") +
    "</h1><p>" +
    tr(
      language, "Independent synthetic case IDs; target-lesion results only. Failed cases remain in this index.",
      "各编号独立复核，结果仅描述靶病灶；失败记录保留在索引中。",
    ) +
    "</p><table><thead><tr>" +
    tr(
      language, "<th>Case</th><th>Status</th><th>Visits / review hints</th><th>Detail</th>",
      "<th>编号</th><th>状态</th><th>随访数 / 复核提示数</th><th>详情</th>",
    ) +
    "</tr></thead><tbody>",
  )
  for r in results {
    let id = html_escape(r.id)
    // The link is generated from a validated portable ID, never a source path.
    let link = if safe_case_id(r.id) && r.status == "success" {
      "<a href=\"" + id + "/report.html\">" + id + "</a>"
    } else {
      id
    }
    let status = match r.status {
      "success" => tr(language, "success", "成功")
      "input_error" => tr(language, "input error", "输入错误")
      _ => tr(language, "I/O error", "读写错误")
    }
    out.write_string(
      "<tr><td>" +
      link +
      "</td><td>" +
      status +
      "</td><td>\{r.visit_count} / \{r.review_hint_count}</td><td>" +
      html_escape(
        if r.status == "success" {
          tr(language, "Target-lesion report", "靶病灶报告")
        } else {
          r.message
        },
      ) +
      "</td></tr>",
    )
  }
  out.write_string("</tbody></table></html>\n")
  out.to_string()
}
