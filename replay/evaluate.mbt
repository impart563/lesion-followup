///|
fn finding(
  code : String,
  message : String,
  lesion_id? : String,
) -> @evidence.Finding {
  { code, lesion_id, message, }
}

///|
fn change_basis_points(current : Int, reference : Int) -> Int? {
  if reference == 0 {
    None
  } else {
    Some((current - reference) * 10000 / reference)
  }
}

///|
/// Replay a fixed CT target set in supplied order. Thresholds use exact scaled
/// integer comparisons. Percentages are display values and never drive rules.
/// NE visits do not update the nadir. Later visits after target PD, or after
/// target-CR reappearance needing overall context, remain NE in this release.
pub fn replay_track(
  study : @lesion.Study,
  visits : Array[@visit.Visit],
) -> Result[@evidence.Trajectory, Array[@evidence.InputIssue]] {
  let study = { ..study, targets: study.targets.copy(), }
  let visits = visits.map(v => { ..v, measurements: v.measurements.copy(), })
  let issues = validate_track(study, visits)
  if !issues.is_empty() {
    return Err(issues)
  }
  let mut baseline_sum = 0
  for target in study.targets {
    baseline_sum += target.baseline_tenths_mm
  }
  let mut nadir = baseline_sum
  let mut nadir_id = "baseline"
  let mut had_cr = false
  let mut stop_reason : String? = None
  let assessments : Array[@evidence.VisitAssessment] = []
  for visit in visits {
    let measurements : Array[@evidence.ResolvedMeasurement] = []
    let findings = []
    let mut complete = true
    let mut sum = 0
    let mut all_resolved = true
    for target in study.targets {
      let mut observation : @visit.Observation = Missing
      for measurement in visit.measurements {
        if measurement.lesion_id == target.id {
          observation = measurement.observation
        }
      }
      let value = match observation {
        Measured(size) => Some(size)
        Absent => Some(0)
        TooSmallToMeasure => {
          findings.push(
            finding(
              "default_5mm",
              "Visible but too small to measure: explicit 5.0 mm guideline default.",
              lesion_id=target.id,
            ),
          )
          Some(50)
        }
        Missing => {
          findings.push(
            finding(
              "missing_measurement",
              "Target is missing; no diameter is imputed.",
              lesion_id=target.id,
            ),
          )
          None
        }
        NotEvaluable(reason) => {
          findings.push(
            finding("reader_not_evaluable", reason, lesion_id=target.id),
          )
          None
        }
      }
      measurements.push({
        lesion_id: target.id,
        kind: target.kind,
        baseline_tenths_mm: target.baseline_tenths_mm,
        observation,
        effective_tenths_mm: value,
      })
      match value {
        Some(size) => {
          sum += size
          let resolved = match target.kind {
            NonNodal => size == 0
            LymphNode => size < 100
          }
          if !resolved {
            all_resolved = false
          }
          if target.kind is LymphNode && size < 100 {
            findings.push(
              finding(
                "node_below_10mm",
                "Node short axis is below 10.0 mm; its actual diameter remains in the sum.",
                lesion_id=target.id,
              ),
            )
          }
        }
        None => {
          complete = false
          all_resolved = false
        }
      }
    }
    let compatible = visit.technique_id == study.technique_id
    if !compatible {
      findings.push(
        finding(
          "technique_mismatch", "Technique differs from baseline; comparability requires reader review.",
        ),
      )
    }
    let response : @evidence.TargetResponse = if stop_reason is Some(reason) {
      findings.push(finding("track_requires_review", reason))
      NE
    } else if !complete || !compatible {
      NE
    } else if had_cr && !all_resolved {
      let reason = "A target reappeared after target CR. Overall-response context is required; this library cannot resolve that context."
      findings.push(finding("reappearance_after_target_cr", reason))
      stop_reason = Some(reason)
      NE
    } else if all_resolved {
      findings.push(
        finding(
          "target_cr", "All non-nodal targets are absent and every target node is below 10.0 mm.",
        ),
      )
      CR
    } else if sum * 5 >= nadir * 6 && sum - nadir >= 50 {
      findings.push(
        finding(
          "target_pd", "Diameter sum increased at least 20% and at least 5.0 mm from the prior nadir.",
        ),
      )
      stop_reason = Some(
        "Target PD has occurred. Further on-treatment classifications are outside this release's scope.",
      )
      PD
    } else if sum * 10 <= baseline_sum * 7 {
      findings.push(
        finding(
          "target_pr", "Diameter sum decreased at least 30% from baseline; PD criteria do not apply.",
        ),
      )
      PR
    } else {
      findings.push(
        finding(
          "target_sd", "Target measurements meet neither CR, PR nor both PD thresholds.",
        ),
      )
      SD
    }
    let eligible = response != NE
    assessments.push({
      visit_id: visit.id,
      date: visit.date,
      response,
      sum_tenths_mm: if complete {
        Some(sum)
      } else {
        None
      },
      baseline_sum_tenths_mm: baseline_sum,
      nadir_sum_tenths_mm: nadir,
      nadir_visit_id: nadir_id,
      baseline_change_basis_points: if complete {
        change_basis_points(sum, baseline_sum)
      } else {
        None
      },
      nadir_change_basis_points: if complete {
        change_basis_points(sum, nadir)
      } else {
        None
      },
      measurements,
      findings,
    })
    if eligible && sum < nadir {
      nadir = sum
      nadir_id = visit.id
    }
    if response == CR {
      had_cr = true
    }
  }
  Ok({ study, visits, assessments, })
}
