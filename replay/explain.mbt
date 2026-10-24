///|
fn check(
  code : String,
  left : Int?,
  operator : String,
  right : Int,
  active : Bool,
  lesion_id? : String,
) -> @evidence.RuleCheck {
  let passed = left.map(value => {
    match operator {
      "==" => value == right
      "<" => value < right
      ">=" => value >= right
      _ => value <= right
    }
  })
  { code, lesion_id, left, operator, right, passed, active, }
}

///|
/// Explain an assessment produced by replay_track. This presentation of the
/// comparisons does not classify a second time or use rounded percentages.
pub fn explain_assessment(
  a : @evidence.VisitAssessment,
) -> Array[@evidence.RuleCheck] {
  let has = (code : String) => a.findings.any(f => f.code == code)
  let complete = a.sum_tenths_mm is Some(_)
  let compatible = !has("technique_mismatch")
  let context = !has("track_requires_review") &&
    !has("reappearance_after_target_cr")
  let ready = complete && compatible && context
  let out = [
    check(
      "complete_measurements",
      Some(if complete { 1 } else { 0 }),
      "==",
      1,
      true,
    ),
    check(
      "comparable_technique",
      Some(if compatible { 1 } else { 0 }),
      "==",
      1,
      true,
    ),
    check("context_open", Some(if context { 1 } else { 0 }), "==", 1, true),
  ]
  let mut resolved = true
  for m in a.measurements {
    let node = m.kind is LymphNode
    let item = check(
      if node {
        "node_cr_short_axis"
      } else {
        "non_nodal_cr"
      },
      m.effective_tenths_mm,
      if node {
        "<"
      } else {
        "=="
      },
      if node {
        100
      } else {
        0
      },
      ready,
      lesion_id=m.lesion_id,
    )
    if item.passed != Some(true) {
      resolved = false
    }
    out.push(item)
  }
  let pd_active = ready && !resolved
  let relative = check(
    "pd_relative_5S_ge_6N",
    a.sum_tenths_mm.map(s => 5 * s),
    ">=",
    6 * a.nadir_sum_tenths_mm,
    pd_active,
  )
  let absolute = check(
    "pd_absolute_S_minus_N_ge_50",
    a.sum_tenths_mm.map(s => s - a.nadir_sum_tenths_mm),
    ">=",
    50,
    pd_active,
  )
  out.push(relative)
  out.push(absolute)
  out.push(
    check(
      "pr_10S_le_7B",
      a.sum_tenths_mm.map(s => 10 * s),
      "<=",
      7 * a.baseline_sum_tenths_mm,
      pd_active &&
      !(relative.passed == Some(true) && absolute.passed == Some(true)),
    ),
  )
  out
}
