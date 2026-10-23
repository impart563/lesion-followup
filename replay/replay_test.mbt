///|
fn study(size : Int, node? : Bool = false) -> @lesion.Study {
  {
    id: "synthetic",
    baseline_date: "2026-01-01",
    technique_id: "ct-venous",
    slice_thickness_tenths_mm: 50,
    targets: [
      {
        id: "T1",
        organ: if node {
          "lymph_nodes"
        } else {
          "liver"
        },
        kind: if node {
          LymphNode
        } else {
          NonNodal
        },
        baseline_tenths_mm: size,
      },
    ],
  }
}

///|
fn visit(
  id : String,
  day : String,
  observation : @visit.Observation,
) -> @visit.Visit {
  {
    id,
    date: "2026-01-" + day,
    technique_id: "ct-venous",
    measurements: [{ lesion_id: "T1", observation, }],
  }
}

///|
fn run(
  study : @lesion.Study,
  visits : Array[@visit.Visit],
) -> @evidence.Trajectory raise {
  match @replay.replay_track(study, visits) {
    Ok(result) => result
    Err(errors) => fail("Unexpected validation errors: \{errors.length()}")
  }
}

///|
test "PR is inclusive at minus 30 percent, never rounded into a response" {
  let s = study(1000)
  for (size, expected) in [(701, "SD"), (700, "PR"), (699, "PR")] {
    let t = run(s, [visit("v1", "02", Measured(size))])
    assert_eq(t.assessments[0].response.code(), expected)
  }
}

///|
test "PD requires both 20 percent and five millimetres, with inclusive boundaries" {
  for (size, expected) in [(239, "SD"), (240, "SD"), (249, "SD"), (250, "PD")] {
    let t = run(study(200), [visit("v1", "02", Measured(size))])
    assert_eq(t.assessments[0].response.code(), expected)
  }
  for (size, expected) in [(1199, "SD"), (1200, "PD")] {
    assert_eq(
      run(study(1000), [visit("v1", "02", Measured(size))]).assessments[0].response.code(),
      expected,
    )
  }
}

///|
test "PD has precedence over PR and uses a historical nadir rather than baseline" {
  let t = run(study(1000), [
    visit("shrink", "02", Measured(400)),
    visit("grow", "03", Measured(500)),
  ])
  assert_eq(t.assessments[0].response.code(), "PR")
  assert_eq(t.assessments[1].response.code(), "PD")
  assert_eq(t.assessments[1].nadir_visit_id, "shrink")
  assert_eq(t.assessments[1].baseline_change_basis_points, Some(-5000))
}

///|
test "node CR retains the actual short-axis diameter and ten mm is not CR" {
  for (size, expected) in [(99, "CR"), (100, "PR")] {
    let a = run(study(200, node=true), [visit("v1", "02", Measured(size))]).assessments[0]
    assert_eq(a.response.code(), expected)
    assert_eq(a.sum_tenths_mm, Some(size))
  }
}

///|
test "missing and absent are distinct, and missing never updates nadir" {
  let t = run(study(200), [
    visit("missing", "02", Missing),
    visit("grow", "03", Measured(240)),
  ])
  assert_eq(t.assessments[0].response.code(), "NE")
  assert_eq(t.assessments[0].sum_tenths_mm, None)
  assert_eq(t.assessments[1].nadir_visit_id, "baseline")
  assert_eq(t.assessments[1].response.code(), "SD")
  assert_eq(
    run(study(200), [visit("gone", "02", Absent)]).assessments[0].response.code(),
    "CR",
  )
}

///|
test "visible too-small target uses an explicit five mm default" {
  let a = run(study(200), [visit("faint", "02", TooSmallToMeasure)]).assessments[0]
  assert_eq(a.response.code(), "PR")
  assert_eq(a.sum_tenths_mm, Some(50))
  assert_true(a.findings.any(f => f.code == "default_5mm"))
}

///|
test "omitted measurements and reader non-evaluable visits retain evidence" {
  let v : @visit.Visit = {
    id: "empty",
    date: "2026-01-02",
    technique_id: "ct-venous",
    measurements: [],
  }
  let a = run(study(200), [v]).assessments[0]
  assert_eq(a.response.code(), "NE")
  assert_eq(a.measurements.length(), 1)
  assert_true(a.measurements[0].observation is Missing)
  let b = run(study(200), [visit("merged", "02", NotEvaluable("coalesced"))]).assessments[0]
  assert_eq(b.response.code(), "NE")
  assert_true(b.findings.any(f => f.message == "coalesced"))
}

///|
test "different technique cannot lower the reference" {
  let v = {
    ..visit("different", "02", Measured(10)),
    technique_id: "ct-other",
  }
  let t = run(study(200), [v, visit("usual", "03", Measured(240))])
  assert_eq(t.assessments[0].response.code(), "NE")
  assert_eq(t.assessments[1].nadir_visit_id, "baseline")
  assert_eq(t.assessments[1].response.code(), "SD")
}

///|
test "target reappearance after target CR requires overall context" {
  let t = run(study(200), [
    visit("gone", "02", Absent),
    visit("back", "03", Measured(10)),
    visit("later", "04", Measured(60)),
  ])
  assert_eq(t.assessments[0].response.code(), "CR")
  assert_eq(t.assessments[1].response.code(), "NE")
  assert_eq(t.assessments[1].nadir_change_basis_points, None)
  assert_true(
    t.assessments[1].findings.any(f => f.code == "reappearance_after_target_cr"),
  )
  assert_eq(t.assessments[2].response.code(), "NE")
}

///|
test "reappearing one target without target CR stays part of the sum" {
  let s = {
    ..study(200),
    targets: [
      study(200).targets[0],
      {
        id: "T2",
        organ: "lung",
        kind: @lesion.NonNodal,
        baseline_tenths_mm: 200,
      },
    ],
  }
  let v1 : @visit.Visit = {
    id: "v1",
    date: "2026-01-02",
    technique_id: "ct-venous",
    measurements: [
      { lesion_id: "T1", observation: Absent, },
      { lesion_id: "T2", observation: Measured(200), },
    ],
  }
  let v2 : @visit.Visit = {
    ..v1,
    id: "v2",
    date: "2026-01-03",
    measurements: [
      { lesion_id: "T1", observation: Measured(10), },
      { lesion_id: "T2", observation: Measured(200), },
    ],
  }
  assert_eq(run(s, [v1, v2]).assessments[1].response.code(), "PR")
}

///|
test "post-progression visits remain NE rather than implying resumed response" {
  let t = run(study(200), [
    visit("pd", "02", Measured(250)),
    visit("later", "03", Measured(100)),
  ])
  assert_eq(t.assessments[1].response.code(), "NE")
}

///|
test "invalid dates and unordered visits reject the whole track" {
  for date in ["2026-02-29", "2026-04-31", "0000-01-01", "2026-1-02"] {
    assert_true(
      !@replay.validate_study({ ..study(200), baseline_date: date, }).is_empty(),
    )
  }
  assert_true(
    @replay.validate_study({ ..study(200), baseline_date: "2024-02-29", }).is_empty(),
  )
  assert_true(
    @replay.replay_track(study(200), [
      visit("a", "03", Measured(200)),
      visit("b", "02", Measured(200)),
    ])
    is Err(_),
  )
}

///|
test "target selection validates node minima, slice thickness and per-organ limits" {
  assert_true(!@replay.validate_study(study(149, node=true)).is_empty())
  assert_true(!@replay.validate_study(study(99)).is_empty())
  assert_true(
    !@replay.validate_study({ ..study(200), slice_thickness_tenths_mm: 51, }).is_empty(),
  )
  let s = study(200)
  let targets = [ for i in 0..<3 => { ..s.targets[0], id: "T\{i}", } ]
  assert_true(
    @replay.validate_study({ ..s, targets, }).any(e => e.code is TooManyPerOrgan),
  )
}

///|
test "duplicate IDs unknown targets and negative diameters are structural errors" {
  let v = visit("v", "02", Measured(-1))
  assert_true(@replay.replay_track(study(200), [v]) is Err(_))
  assert_true(
    @replay.replay_track(study(200), [
      { ..v, measurements: [{ lesion_id: "unknown", observation: Absent, }], },
    ])
    is Err(_),
  )
  assert_true(
    @replay.replay_track(study(200), [
      { ..v, measurements: [v.measurements[0], v.measurements[0]], },
    ])
    is Err(_),
  )
  assert_true(
    @replay.replay_track(study(200), [
      visit("v", "02", Absent),
      visit("v", "03", Absent),
    ])
    is Err(_),
  )
}

///|
test "full software range is safe and replay is deterministic" {
  let s = {
    ..study(10000),
    targets: [
      for i in 0..<5 => {
        { ..study(10000).targets[0], id: "T\{i}", organ: "organ\{i}", }
      }
    ],
  }
  let v : @visit.Visit = {
    id: "v",
    date: "2026-01-02",
    technique_id: "ct-venous",
    measurements: [
      for i in 0..<5 => { lesion_id: "T\{i}", observation: @visit.Measured(0), }
    ],
  }
  let a = run(s, [v])
  assert_eq(a.assessments[0].sum_tenths_mm, Some(0))
  assert_eq(a.assessments[0].baseline_change_basis_points, Some(-10000))
  assert_eq(a, run(s, [v]))
}
