///|
fn html_escape(text : String) -> String {
  text
  .replace_all(old="&", new="&amp;")
  .replace_all(old="<", new="&lt;")
  .replace_all(old=">", new="&gt;")
  .replace_all(old="\"", new="&quot;")
  .replace_all(old="'", new="&#39;")
}

///|
fn markdown_escape(text : String) -> String {
  html_escape(text)
  .replace_all(old="\\", new="\\\\")
  .replace_all(old="|", new="\\|")
  .replace_all(old="\r", new="")
  .replace_all(old="\n", new="<br>")
}

///|
fn percent(value : Int?) -> String {
  guard value is Some(value) else { return "n/a" }
  let sign = if value < 0 { "-" } else { "+" }
  let absolute = if value < 0 { -value.to_int64() } else { value.to_int64() }
  let fraction = (absolute % 100).to_string().pad_start(2, '0')
  "\{sign}\{absolute / 100}.\{fraction}%"
}

///|
fn mm_or_missing(value : Int?) -> String {
  match value {
    Some(value) => format_diameter_mm(value)
    None => "n/a"
  }
}

///|
/// Text report of target-only categories, references and individual findings.
pub fn render_audit_markdown(trajectory : @evidence.Trajectory) -> String {
  render_audit_markdown_in(trajectory, English)
}

///|
/// Localized presentation; input-derived text and machine codes are preserved.
pub fn render_audit_markdown_in(
  trajectory : @evidence.Trajectory,
  language : ReportLanguage,
) -> String {
  let out = StringBuilder()
  out.write_string(
    tr(
      language, "# Target-lesion follow-up review\n\nStudy: ", "# 靶病灶随访复核\n\n研究编号： ",
    ) +
    markdown_escape(trajectory.study.id) +
    "\n\n",
  )
  out.write_string(
    tr(
      language, "RECIST 1.1 target subset. Categories describe target lesions only.\n\n",
      "RECIST 1.1 靶病灶子集。分类仅描述靶病灶。\n\n",
    ),
  )
  out.write_string(
    tr(
      language, "| Visit | Date | Target category | Sum (mm) | From baseline | Prior nadir (mm) | Nadir visit | From nadir |\n|---|---|---|---:|---:|---:|---|---:|\n",
      "| 随访 | 日期 | 靶病灶分类 | 总和 (mm) | 较基线 | 此前最低值 (mm) | 最低值来源随访 | 较最低值 |\n|---|---|---|---:|---:|---:|---|---:|\n",
    ),
  )
  for a in trajectory.assessments {
    out.write_string(
      "| " +
      markdown_escape(a.visit_id) +
      " | " +
      a.date +
      " | " +
      a.response.code() +
      " | " +
      mm_or_missing(a.sum_tenths_mm) +
      " | " +
      percent(a.baseline_change_basis_points) +
      " | " +
      format_diameter_mm(a.nadir_sum_tenths_mm) +
      " | " +
      markdown_escape(a.nadir_visit_id) +
      " | " +
      percent(a.nadir_change_basis_points) +
      " |\n",
    )
  }
  for a in trajectory.assessments {
    out.write_string(
      "\n## " + markdown_escape(a.visit_id) + " / " + a.response.code() + "\n\n",
    )
    for m in a.measurements {
      out.write_string(
        "- " +
        markdown_escape(m.lesion_id) +
        ": " +
        observation_label(m.observation, language) +
        tr(language, ", effective ", "，采用直径 ") +
        mm_or_missing(m.effective_tenths_mm) +
        " mm\n",
      )
    }
    for f in a.findings {
      out.write_string(
        "- `" +
        f.code +
        "`: " +
        markdown_escape(finding_label(f, language)) +
        "\n",
      )
    }
  }
  out.write_string(
    render_lesion_section_markdown(trajectory, language) +
    "\n" +
    glossary(language) +
    "\n",
  )
  out.to_string()
}

///|
fn csv_cell(value : String) -> String {
  if value.contains_char(',') ||
    value.contains_char('"') ||
    value.contains_char('\n') ||
    value.contains_char('\r') {
    "\"" + value.replace_all(old="\"", new="\"\"") + "\""
  } else {
    value
  }
}

///|
fn csv_row(values : Array[String]) -> String {
  values.map(csv_cell).join(",") + "\n"
}

///|
/// Typed detail rows. Blank numeric fields represent unavailable values.
pub fn render_audit_csv(trajectory : @evidence.Trajectory) -> String {
  let out = StringBuilder()
  out.write_string(
    "row_type,visit_id,date,target_response,lesion_id,kind,state,diameter_mm,sum_mm,baseline_sum_mm,prior_nadir_mm,prior_nadir_visit_id,baseline_change_pct,nadir_change_pct,code,message\n",
  )
  for a in trajectory.assessments {
    let base = [
      "assessment",
      a.visit_id,
      a.date,
      a.response.code(),
      "",
      "",
      "",
      "",
      match a.sum_tenths_mm {
        Some(v) => format_diameter_mm(v)
        None => ""
      },
      format_diameter_mm(a.baseline_sum_tenths_mm),
      format_diameter_mm(a.nadir_sum_tenths_mm),
      a.nadir_visit_id,
      if a.baseline_change_basis_points is Some(_) {
        percent(a.baseline_change_basis_points)
      } else {
        ""
      },
      if a.nadir_change_basis_points is Some(_) {
        percent(a.nadir_change_basis_points)
      } else {
        ""
      },
      "",
      "",
    ]
    out.write_string(csv_row(base))
    for m in a.measurements {
      let row = base.copy()
      row[0] = "measurement"
      row[4] = m.lesion_id
      row[5] = kind_name(m.kind)
      row[6] = state_name(m.observation)
      row[7] = match m.effective_tenths_mm {
        Some(value) => format_diameter_mm(value)
        None => ""
      }
      row[15] = match m.observation {
        NotEvaluable(reason) => reason
        _ => ""
      }
      out.write_string(csv_row(row))
    }
    for f in a.findings {
      let row = base.copy()
      row[0] = "finding"
      row[4] = f.lesion_id.unwrap_or("")
      row[14] = f.code
      row[15] = f.message
      out.write_string(csv_row(row))
    }
  }
  out.to_string()
}
