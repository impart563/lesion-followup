///|
fn main {
  let study : @lib.Study = {
    id: "external-consumer",
    baseline_date: "2026-01-01",
    technique_id: "ct",
    slice_thickness_tenths_mm: 50,
    targets: [{ id: "N1", organ: "lymph_nodes", kind: LymphNode, baseline_tenths_mm: 200 }],
  }
  let visit : @lib.Visit = { id: "v", date: "2026-02-01", technique_id: "ct", measurements: [{ lesion_id: "N1", observation: Measured(99) }] }
  match @lib.replay_track(study, [visit]) {
    Ok(t) => {
      let a = t.assessments[0]
      if a.response.code() == "CR" && a.sum_tenths_mm == Some(99) && @lib.render_audit_json(t).contains("target_lesions_only") {
        println("Downstream consumer smoke passed: node CR retains 9.9 mm")
      } else { panic() }
    }
    Err(_) => panic()
  }
}
