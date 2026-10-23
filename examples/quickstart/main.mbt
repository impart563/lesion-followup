///|
fn main {
  let study : @lib.Study = {
    id: "synthetic-consumer",
    baseline_date: "2026-01-01",
    technique_id: "ct-5mm",
    slice_thickness_tenths_mm: 50,
    targets: [
      { id: "T1", organ: "liver", kind: NonNodal, baseline_tenths_mm: 200, },
    ],
  }
  let visit : @lib.Visit = {
    id: "week-4",
    date: "2026-02-01",
    technique_id: "ct-5mm",
    measurements: [{ lesion_id: "T1", observation: Measured(250), }],
  }
  match @lib.replay_track(study, [visit]) {
    Ok(trajectory) => println(@lib.render_audit_markdown(trajectory))
    Err(issues) => println("Input issues: \{issues.length()}")
  }
}
