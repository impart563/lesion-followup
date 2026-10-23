///|
fn example_trajectory() -> @evidence.Trajectory raise {
  let study : @lesion.Study = {
    id: "synthetic <review> & \"quoted\"",
    baseline_date: "2026-01-01",
    technique_id: "ct",
    slice_thickness_tenths_mm: 50,
    targets: [
      { id: "T1", organ: "liver", kind: NonNodal, baseline_tenths_mm: 200, },
    ],
  }
  let visits : Array[@visit.Visit] = [
    {
      id: "first",
      date: "2026-01-02",
      technique_id: "ct",
      measurements: [{ lesion_id: "T1", observation: Measured(200), }],
    },
    {
      id: "second",
      date: "2026-01-03",
      technique_id: "ct",
      measurements: [
        {
          lesion_id: "T1",
          observation: NotEvaluable(
            "<script>alert(1)</script>, \"note\"\nline 2",
          ),
        },
      ],
    },
    {
      id: "third",
      date: "2026-01-04",
      technique_id: "ct",
      measurements: [{ lesion_id: "T1", observation: Measured(250), }],
    },
  ]
  match @replay.replay_track(study, visits) {
    Ok(t) => t
    Err(_) => fail("fixture invalid")
  }
}

///|
test "versioned JSON retains original observations and target scope" {
  let t = example_trajectory()
  let report = @json.parse(@io.render_audit_json(t))
  assert_true(
    report
    is {
      "schema_version": Number(1.0, ..),
      "scope": String("target_lesions_only"),
      ..
    },
  )
  assert_true(@io.render_audit_json(t).contains("\"effective_mm\": null"))
  assert_true(@io.render_audit_json(t).contains("reader_not_evaluable"))
  for
    render in [
      @io.render_audit_json, @io.render_audit_csv, @io.render_audit_markdown, @io.render_trajectory_svg,
      @io.render_audit_html, @io.render_audit_manifest,
    ] {
    assert_eq(render(t), render(t))
  }
}

///|
test "HTML and SVG escape input and do not load active content" {
  let t = example_trajectory()
  let html = @io.render_audit_html(t)
  assert_true(!html.contains("<script>"))
  assert_true(html.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
  assert_true(html.contains("&amp; &quot;quoted&quot;"))
  assert_true(!html.contains("<link"))
  assert_true(!html.contains("<img"))
  assert_true(html.contains("Content-Security-Policy"))
  let svg = @io.render_trajectory_svg(t)
  assert_eq(svg.split("<circle ").count(), 4)
  assert_eq(svg.split("stroke-width=\"2.5\"").count(), 2)
  assert_true(svg.contains("NE; excluded from trend line"))
}

///|
test "CSV round-trip quoting preserves a multiline reader reason" {
  let csv = @io.render_audit_csv(example_trajectory())
  assert_true(
    csv.contains("\"<script>alert(1)</script>, \"\"note\"\"\nline 2\""),
  )
  assert_true(csv.contains("assessment,second,2026-01-03,NE,,,,,,20.0"))
  assert_true(csv.contains("finding,third,2026-01-04,PD"))
}

///|
test "validation reports separate parse diagnostics from structural issues" {
  let report = @json.parse(
    @io.render_validation_json(
      [
        {
          code: "csv_diameter",
          message: "bad",
          line: Some(2),
          column: Some(10),
          field: Some("diameter_mm"),
        },
      ],
      [],
      0,
    ),
  )
  assert_true(report is { "valid": False, "diagnostics": Array([_, ..]), .. })
  assert_true(
    @json.parse(@io.render_validation_json([], [], 3))
    is { "valid": True, "visit_count": Number(3.0, ..), .. },
  )
}
