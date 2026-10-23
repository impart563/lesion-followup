///|
fn template_pair(name : String) -> (String, String) raise {
  guard @io.input_template_files(name) is Ok(files) else {
    fail("template missing")
  }
  (files[0].1, files[1].1)
}

///|
test "both matched templates parse and replay without any input repair" {
  for name in ["single", "multi"] {
    let (profile, csv) = template_pair(name)
    let preflight = @io.preflight_inputs(profile, csv)
    assert_true(preflight.is_valid())
    assert_true(preflight.review_hints.is_empty())
    guard @io.parse_study_json(profile) is Ok(study) &&
      @io.parse_followup_csv(csv) is Ok(visits) else {
      fail("invalid template")
    }
    assert_eq(study.targets.length(), if name == "single" { 1 } else { 2 })
    assert_eq(visits.length(), 4)
    assert_true(@replay.replay_track(study, visits) is Ok(_))
  }
  assert_true(@io.input_template_files("unknown") is Err(_))
}

///|
test "preflight locates structural CSV errors after a quoted multiline field" {
  let (profile, _) = template_pair("single")
  let csv = "visit_id,date,technique_id,lesion_id,state,diameter_mm,note\r\n" +
    "v1,2026-01-02,ct-venous-5mm,T1,not_evaluable,,\"line 1\r\nline 2\"\r\n" +
    "v2,2026-02-30,ct-venous-5mm,T1,measured,20.0,\r\n"
  let report = @io.preflight_inputs(profile, csv)
  assert_true(!report.is_valid())
  assert_eq(report.input_issues[0].code, "invalid_date")
  assert_eq(report.input_issues[0].source, "followup_csv")
  assert_eq(report.input_issues[0].line, Some(4))
  assert_eq(report.input_issues[0].column, Some(4))
  assert_eq(report.input_issues[0].field, Some("date"))
  assert_true(report.review_hints.is_empty())
}

///|
test "preflight preserves source distinction and JSON structural field paths" {
  let (profile, csv) = template_pair("single")
  let invalid = profile.replace(old="30.0", new="9.9")
  let report = @io.preflight_inputs(invalid, csv)
  assert_true(!report.is_valid())
  assert_eq(report.input_issues[0].field, Some("$.targets[0].baseline_mm"))
  let syntax = @io.preflight_inputs("{", "wrong\n")
  assert_eq(syntax.diagnostics.length(), 2)
  assert_eq(syntax.diagnostics[0].source, "study_json")
  assert_eq(syntax.diagnostics[1].source, "followup_csv")
  assert_true(syntax.input_issues.is_empty())
}

///|
test "preflight separates valid but review-required data and anchors omitted targets" {
  let (profile, _) = template_pair("multi")
  let csv = "visit_id,date,technique_id,lesion_id,state,diameter_mm,note\n" +
    "v1,2026-01-02,changed,N1,too_small,,\n"
  let report = @io.preflight_inputs(profile, csv)
  assert_true(report.is_valid())
  assert_eq(report.review_hints.length(), 3)
  let missing = report.review_hints[0]
  assert_eq(missing.code, "missing_measurement")
  assert_eq(missing.lesion_id, Some("T1"))
  assert_eq(missing.line, Some(2))
  assert_eq(missing.field, None)
  assert_eq(report.review_hints[1].code, "default_5mm")
  assert_eq(report.review_hints[1].field, Some("state"))
  assert_eq(report.review_hints[2].code, "technique_mismatch")
  assert_eq(report.review_hints[2].field, Some("technique_id"))
  let chinese = @io.render_preflight_markdown(
    report,
    language=SimplifiedChinese,
  )
  assert_true(chinese.contains("人工复核提示"))
  assert_true(chinese.contains("默认值"))
  let machine = @json.parse(@io.render_preflight_json(report))
  assert_true(
    machine is { "valid": True, "review_hints": Array([_, _, _]), .. },
  )
}

///|
test "localized reports preserve user text, categories and exact values" {
  let t = example_trajectory()
  let english = @io.render_audit_html_in(t, English)
  let chinese = @io.render_audit_html_in(t, SimplifiedChinese)
  assert_eq(english, @io.render_audit_html(t))
  assert_true(chinese.contains("lang=\"zh-CN\""))
  assert_true(chinese.contains("靶病灶分类"))
  assert_true(chinese.contains("基线"))
  assert_true(chinese.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
  assert_true(
    chinese.contains("synthetic &lt;review&gt; &amp; &quot;quoted&quot;"),
  )
  for code in ["SD", "NE", "PD"] {
    assert_true(chinese.contains(">" + code + "</span>"))
  }
  assert_true(chinese.contains("25.0"))
  let markdown = @io.render_audit_markdown_in(t, SimplifiedChinese)
  assert_true(markdown.contains("单病灶趋势"))
  assert_true(markdown.contains("PD progressive") == false)
}

///|
test "lesion trends retain NE observations but break lines and distinguish defaults" {
  let (profile, _) = template_pair("multi")
  guard @io.parse_study_json(profile) is Ok(study) else { fail("profile") }
  let visits : Array[@visit.Visit] = [
    {
      id: "gap",
      date: "2026-01-02",
      technique_id: study.technique_id,
      measurements: [{ lesion_id: "T1", observation: Measured(250), }],
    },
    {
      id: "defaults",
      date: "2026-01-03",
      technique_id: study.technique_id,
      measurements: [
        { lesion_id: "T1", observation: TooSmallToMeasure, },
        { lesion_id: "N1", observation: Absent, },
      ],
    },
  ]
  guard @replay.replay_track(study, visits) is Ok(t) else { fail("track") }
  let svg = @io.render_lesion_trends_svg(t)
  assert_true(
    svg.contains(
      "data-visit-id=\"gap\" data-state=\"measured\" data-visit-response=\"NE\" data-effective-mm=\"25.0\"",
    ),
  )
  assert_true(
    svg.contains(
      "data-state=\"too_small\" data-visit-response=\"PR\" data-effective-mm=\"5.0\"",
    ),
  )
  assert_true(
    svg.contains("<path data-visit-id=\"gap\" data-state=\"missing\""),
  )
  assert_true(
    svg.contains(
      "data-state=\"absent\" data-visit-response=\"PR\" data-effective-mm=\"0.0\"",
    ),
  )
  assert_true(!svg.contains("stroke-width=\"2\"/>"))
  assert_true(svg.contains("Longest diameter"))
  assert_true(svg.contains("Node short axis"))
}
