///|
fn visit_input_json(v : @visit.Visit) -> Json {
  let measurements : Array[Json] = v.measurements.map(m => {
    "lesion_id": m.lesion_id,
    "observation": observation_json(m.observation),
  })
  {
    "id": v.id,
    "date": v.date,
    "technique_id": v.technique_id,
    "measurements": measurements.to_json(),
  }
}

///|
fn change(
  visit_id : String,
  field : String,
  before : String?,
  after : String?,
  lesion_id? : String,
) -> @evidence.InputChange {
  { visit_id, lesion_id, field, before, after, }
}

///|
/// Compare replayed tracks of the same exact baseline profile. Visit and lesion
/// identity, rather than array position, aligns changes. Inputs remain untouched.
pub fn compare_tracks(
  before : @evidence.Trajectory,
  after : @evidence.Trajectory,
) -> Result[@evidence.TrackRevision, Array[Diagnostic]] {
  if before.study != after.study {
    return Err([
      diagnostic(
        "revision_baseline",
        "Revisions require the same study identity, baseline, acquisition and ordered target set.",
        field="$.study",
      ),
    ])
  }
  let changes = []
  let impacts : Array[@evidence.VisitImpact] = []
  let old_visits : Map[String, @visit.Visit] = Map([])
  let old_assessments : Map[String, @evidence.VisitAssessment] = Map([])
  let new_ids : Map[String, Bool] = Map([])
  for v in before.visits {
    old_visits[v.id] = v
  }
  for a in before.assessments {
    old_assessments[a.visit_id] = a
  }
  for i, v in after.visits {
    new_ids[v.id] = true
    match old_visits.get(v.id) {
      None =>
        changes.push(
          change(v.id, "visit", None, Some(visit_input_json(v).stringify())),
        )
      Some(old) => {
        if old.date != v.date {
          changes.push(change(v.id, "date", Some(old.date), Some(v.date)))
        }
        if old.technique_id != v.technique_id {
          changes.push(
            change(
              v.id,
              "technique_id",
              Some(old.technique_id),
              Some(v.technique_id),
            ),
          )
        }
        let old_measurements : Map[String, @visit.Observation] = Map([])
        let new_measurements : Map[String, @visit.Observation] = Map([])
        for m in old.measurements {
          old_measurements[m.lesion_id] = m.observation
        }
        for m in v.measurements {
          new_measurements[m.lesion_id] = m.observation
        }
        for target in after.study.targets {
          let original = old_measurements.get(target.id)
          let revised = new_measurements.get(target.id)
          if original != revised {
            changes.push(
              change(
                v.id,
                "observation",
                original.map(o => observation_json(o).stringify()),
                revised.map(o => observation_json(o).stringify()),
                lesion_id=target.id,
              ),
            )
          }
        }
      }
    }
    let original = old_assessments.get(v.id)
    let revised = after.assessments[i]
    if original != Some(revised) {
      impacts.push({ visit_id: v.id, before: original, after: Some(revised), })
    }
  }
  for v in before.visits {
    if !new_ids.contains(v.id) {
      changes.push(
        change(v.id, "visit", Some(visit_input_json(v).stringify()), None),
      )
      impacts.push({
        visit_id: v.id,
        before: old_assessments.get(v.id),
        after: None,
      })
    }
  }
  Ok({ study_id: after.study.id, changes, impacts, })
}

///|
fn impact_json(a : @evidence.VisitAssessment?) -> Json {
  guard a is Some(a) else { return Json::null() }
  let findings : Array[Json] = a.findings.map(f => {
    "code": f.code,
    "lesion_id": optional_string(f.lesion_id),
    "message": f.message,
  })
  {
    "date": a.date,
    "target_response": a.response.code(),
    "sum_mm": optional_mm(a.sum_tenths_mm),
    "prior_nadir_mm": format_diameter_mm(a.nadir_sum_tenths_mm),
    "prior_nadir_visit_id": a.nadir_visit_id,
    "findings": findings.to_json(),
    "rule_checks": checks_json(a),
  }
}

///|
pub fn render_revision_json(revision : @evidence.TrackRevision) -> String {
  let changes : Array[Json] = revision.changes.map(c => {
    "visit_id": c.visit_id,
    "lesion_id": optional_string(c.lesion_id),
    "field": c.field,
    "before": optional_string(c.before),
    "after": optional_string(c.after),
  })
  let impacts : Array[Json] = revision.impacts.map(i => {
    "visit_id": i.visit_id,
    "before": impact_json(i.before),
    "after": impact_json(i.after),
  })
  let document : Json = {
    "schema_version": 1,
    "scope": "target_lesions_only",
    "study_id": revision.study_id,
    "input_changes": changes.to_json(),
    "affected_visits": impacts.to_json(),
  }
  document.stringify(indent=2) + "\n"
}

///|
fn impact_label(a : @evidence.VisitAssessment?) -> String {
  match a {
    None => "—"
    Some(a) =>
      a.date +
      " / " +
      a.response.code() +
      " / S=" +
      mm_or_missing(a.sum_tenths_mm) +
      " mm / N=" +
      format_diameter_mm(a.nadir_sum_tenths_mm) +
      " mm (" +
      a.nadir_visit_id +
      ")"
  }
}

///|
pub fn render_revision_markdown(
  revision : @evidence.TrackRevision,
  language? : ReportLanguage = English,
) -> String {
  let out = StringBuilder()
  out.write_string(
    "# " +
    tr(language, "Target-lesion revision comparison", "靶病灶修订对比") +
    "\n\n" +
    markdown_escape(revision.study_id) +
    "\n\n" +
    tr(language, "Input changes", "输入变化") +
    ": \{revision.changes.length()}; " +
    tr(language, "Affected visits", "受影响随访") +
    ": \{revision.impacts.length()}\n\n",
  )
  out.write_string(
    tr(
      language, "| Visit | Target | Field | Before | After |\n", "| 随访 | 病灶 | 字段 | 修订前 | 修订后 |\n",
    ) +
    "|---|---|---|---|---|\n",
  )
  for c in revision.changes {
    out.write_string(
      "| " +
      markdown_escape(c.visit_id) +
      " | " +
      markdown_escape(c.lesion_id.unwrap_or("—")) +
      " | " +
      markdown_escape(c.field) +
      " | " +
      markdown_escape(c.before.unwrap_or("—")) +
      " | " +
      markdown_escape(c.after.unwrap_or("—")) +
      " |\n",
    )
  }
  out.write_string(
    "\n" +
    tr(
      language, "| Affected visit | Before date / category / sum / prior minimum | After date / category / sum / prior minimum |\n",
      "| 受影响随访 | 修订前 日期 / 分类 / 总和 / 此前最低值 | 修订后 日期 / 分类 / 总和 / 此前最低值 |\n",
    ) +
    "|---|---|---|\n",
  )
  for i in revision.impacts {
    out.write_string(
      "| " +
      markdown_escape(i.visit_id) +
      " | " +
      markdown_escape(impact_label(i.before)) +
      " | " +
      markdown_escape(impact_label(i.after)) +
      " |\n",
    )
  }
  out.write_string(
    "\n" +
    tr(
      language, "Both tracks are independently replayed. Findings and rule checks in JSON explain changes even when the category is unchanged. Target-lesion results only.\n",
      "两版记录分别独立重算。即使分类未变，JSON 中的复核提示和条件比较仍可追溯变化。结果仅描述靶病灶。\n",
    ),
  )
  out.to_string()
}

///|
pub fn render_revision_html(
  revision : @evidence.TrackRevision,
  language? : ReportLanguage = English,
) -> String {
  let out = StringBuilder()
  out.write_string(
    "<!doctype html><html lang=\"" +
    tr(language, "en", "zh-CN") +
    "\"><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>" +
    tr(language, "Revision comparison", "修订对比") +
    "</title><style>body{max-width:1100px;margin:40px auto;padding:24px;font:14px/1.7 system-ui;background:#f6f3ed;color:#263348}.scroll{overflow:auto}table{width:100%;border-collapse:collapse;background:white;margin:20px 0}td,th{padding:14px;border-bottom:1px solid #ddd;text-align:left;overflow-wrap:anywhere}code{white-space:pre-wrap}h1{font-size:28px}</style><h1>" +
    tr(language, "Target-lesion revision comparison", "靶病灶修订对比") +
    "</h1><p>" +
    html_escape(revision.study_id) +
    "</p><p>" +
    tr(language, "Input changes", "输入变化") +
    ": \{revision.changes.length()}; " +
    tr(language, "Affected visits", "受影响随访") +
    ": \{revision.impacts.length()}</p><div class=\"scroll\"><table><thead><tr>" +
    tr(
      language, "<th>Visit</th><th>Target / field</th><th>Before</th><th>After</th>",
      "<th>随访</th><th>病灶 / 字段</th><th>修订前</th><th>修订后</th>",
    ) +
    "</tr></thead><tbody>",
  )
  for c in revision.changes {
    out.write_string(
      "<tr><td>" +
      html_escape(c.visit_id) +
      "</td><td>" +
      html_escape(c.lesion_id.unwrap_or("—")) +
      " / " +
      html_escape(c.field) +
      "</td><td><code>" +
      html_escape(c.before.unwrap_or("—")) +
      "</code></td><td><code>" +
      html_escape(c.after.unwrap_or("—")) +
      "</code></td></tr>",
    )
  }
  out.write_string(
    "</tbody></table></div><h2>" +
    tr(language, "Downstream impact", "后续影响") +
    "</h2><div class=\"scroll\"><table><thead><tr>" +
    tr(
      language, "<th>Affected visit</th><th>Before date / category / sum / prior minimum</th><th>After date / category / sum / prior minimum</th>",
      "<th>受影响随访</th><th>修订前 日期 / 分类 / 总和 / 此前最低值</th><th>修订后 日期 / 分类 / 总和 / 此前最低值</th>",
    ) +
    "</tr></thead><tbody>",
  )
  for i in revision.impacts {
    out.write_string(
      "<tr><td>" +
      html_escape(i.visit_id) +
      "</td><td>" +
      html_escape(impact_label(i.before)) +
      "</td><td>" +
      html_escape(impact_label(i.after)) +
      "</td></tr>",
    )
  }
  out.write_string(
    "</tbody></table></div><p>" +
    tr(
      language, "Independent replay of both tracks; target-lesion results only. JSON retains findings and exact comparisons for each affected visit.",
      "两版记录分别重算；结果仅描述靶病灶。JSON 保留每次受影响随访的复核提示与整数比较。",
    ) +
    "</p></html>\n",
  )
  out.to_string()
}
