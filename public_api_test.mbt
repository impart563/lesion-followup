///|
test "root facade constructs domain values without subpackage imports" {
  let study : @lib.Study = {
    id: "facade",
    baseline_date: "2026-01-01",
    technique_id: "ct",
    slice_thickness_tenths_mm: 50,
    targets: [
      { id: "T1", organ: "liver", kind: NonNodal, baseline_tenths_mm: 200, },
    ],
  }
  let visit : @lib.Visit = {
    id: "v",
    date: "2026-01-02",
    technique_id: "ct",
    measurements: [{ lesion_id: "T1", observation: Measured(250), }],
  }
  guard @lib.replay_track(study, [visit]) is Ok(t) else {
    fail("valid facade input rejected")
  }
  assert_eq(t.assessments[0].response.code(), "PD")
  assert_true(@lib.render_audit_html(t).contains("Target burden over time"))
}
