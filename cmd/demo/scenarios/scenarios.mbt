///|
fn study(id : String, targets : Array[@lib.TargetLesion]) -> @lib.Study {
  {
    id,
    baseline_date: "2026-01-01",
    technique_id: "ct-venous-5mm",
    slice_thickness_tenths_mm: 50,
    targets,
  }
}

///|
fn one_visit(
  id : String,
  date : String,
  observations : Array[(@lib.TargetLesion, @lib.Observation)],
) -> @lib.Visit {
  {
    id,
    date,
    technique_id: "ct-venous-5mm",
    measurements: observations.map(pair => {
      lesion_id: pair.0.id,
      observation: pair.1,
    }),
  }
}

///|
/// Synthetic examples, never patient-derived observations.
pub fn build_scenario(
  name : String,
) -> Result[(@lib.Study, Array[@lib.Visit]), String] {
  let liver : @lib.TargetLesion = {
    id: "T1",
    organ: "liver",
    kind: NonNodal,
    baseline_tenths_mm: 1000,
  }
  let node : @lib.TargetLesion = {
    id: "N1",
    organ: "lymph_nodes",
    kind: LymphNode,
    baseline_tenths_mm: 200,
  }
  match name {
    "nadir-boundary" =>
      Ok(
        (
          study("synthetic-nadir-boundary", [liver]),
          [
            one_visit("shrink", "2026-01-15", [(liver, Measured(200))]),
            one_visit("plus-20pct-only", "2026-02-01", [(liver, Measured(240))]),
            one_visit("both-pd-thresholds", "2026-02-15", [
              (liver, Measured(250)),
            ]),
          ],
        ),
      )
    "node-resolution" =>
      Ok(
        (
          study("synthetic-node-resolution", [node]),
          [
            one_visit("node-10mm", "2026-01-15", [(node, Measured(100))]),
            one_visit("node-normalized", "2026-02-01", [(node, Measured(99))]),
            one_visit("context-needed", "2026-02-15", [(node, Measured(100))]),
          ],
        ),
      )
    "missing-visit" =>
      Ok(
        (
          study("synthetic-missing-visit", [liver]),
          [
            one_visit("pr-boundary", "2026-01-15", [(liver, Measured(700))]),
            one_visit("not-measured", "2026-02-01", [(liver, Missing)]),
            one_visit("complete-again", "2026-02-15", [(liver, Measured(650))]),
            one_visit("progression", "2026-03-01", [(liver, Measured(800))]),
          ],
        ),
      )
    _ =>
      Err(
        "Unknown scenario; choose nadir-boundary, node-resolution or missing-visit.",
      )
  }
}
