///|
fn main {
  let study : @lib.Study = {
    id: "external-consumer",
    baseline_date: "2026-01-01",
    technique_id: "ct",
    slice_thickness_tenths_mm: 50,
    targets: [
      {
        id: "N1",
        organ: "lymph_nodes",
        kind: LymphNode,
        baseline_tenths_mm: 200,
      },
    ],
  }
  let visit : @lib.Visit = {
    id: "v",
    date: "2026-02-01",
    technique_id: "ct",
    measurements: [{ lesion_id: "N1", observation: Measured(99), }],
  }
  match @lib.replay_track(study, [visit]) {
    Ok(t) => {
      let a = t.assessments[0]
      if a.response.code() == "CR" &&
        a.sum_tenths_mm == Some(99) &&
        @lib.render_audit_json(t).contains("target_lesions_only") {
        println("Downstream consumer smoke passed: node CR retains 9.9 mm")
      } else {
        panic()
      }
    }
    Err(_) => panic()
  }
  let files = @lib.input_template_files("multi").unwrap()
  let mut study_json = ""
  let mut followup_csv = ""
  for (name, content) in files {
    if name == "study.json" {
      study_json = content
    } else if name == "followup.csv" {
      followup_csv = content
    }
  }
  let preflight = @lib.preflight_inputs(study_json, followup_csv)
  guard preflight.is_valid() else { panic() }
  let parsed_study = @lib.parse_study_json(study_json).unwrap()
  let visits = @lib.parse_followup_csv(followup_csv).unwrap()
  let trajectory = @lib.replay_track(parsed_study, visits).unwrap()
  guard trajectory.assessments.length() > 0 else { panic() }
  let languages : Array[@lib.ReportLanguage] = [English, SimplifiedChinese]
  for language in languages {
    let artifacts = @lib.review_artifacts(trajectory, language~)
    let manifest = @lib.render_bundle_manifest(trajectory, artifacts, language~)
    let bytes = artifacts.map(pair => (pair.0, @utf8.encode(pair.1)))
    guard @lib.verify_bundle(manifest, bytes).is_empty() else { panic() }
    let changed = artifacts.map(pair => {
      (pair.0, @utf8.encode(pair.1 + "changed"))
    })
    guard !@lib.verify_bundle(manifest, changed).is_empty() else { panic() }
  }
  let invalid = @lib.preflight_inputs(study_json, "invalid header\n")
  guard !invalid.is_valid() && !invalid.diagnostics.is_empty() else { panic() }
  let missing_csv = "visit_id,date,technique_id,lesion_id,state,diameter_mm,note\n" +
    "v1,2026-01-02,ct-venous-5mm,T1,not_evaluable,,Synthetic reader limitation\n" +
    "v1,2026-01-02,ct-venous-5mm,N1,missing,,\n"
  let missing = @lib.preflight_inputs(study_json, missing_csv)
  guard missing.is_valid() && !missing.review_hints.is_empty() else { panic() }
  let unavailable = @lib.replay_track(
    parsed_study,
    @lib.parse_followup_csv(missing_csv).unwrap(),
  ).unwrap()
  guard unavailable.assessments[0].response.code() == "NE" else { panic() }
  println(
    "Downstream integration passed: text input, preflight, target-only NE, bilingual bundles and tamper rejection",
  )
}
