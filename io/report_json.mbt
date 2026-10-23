///|
fn kind_name(kind : @lesion.LesionKind) -> String {
  match kind {
    NonNodal => "non_nodal"
    LymphNode => "lymph_node"
  }
}

///|
fn state_name(observation : @visit.Observation) -> String {
  match observation {
    Measured(_) => "measured"
    Absent => "absent"
    TooSmallToMeasure => "too_small"
    Missing => "missing"
    NotEvaluable(_) => "not_evaluable"
  }
}

///|
fn optional_int(value : Int?) -> Json {
  match value {
    Some(value) => value.to_json()
    None => Json::null()
  }
}

///|
fn optional_string(value : String?) -> Json {
  match value {
    Some(value) => value.to_json()
    None => Json::null()
  }
}

///|
fn optional_mm(value : Int?) -> Json {
  match value {
    Some(value) => format_diameter_mm(value).to_json()
    None => Json::null()
  }
}

///|
fn observation_json(observation : @visit.Observation) -> Json {
  let mm = match observation {
    Measured(size) => Some(size)
    _ => None
  }
  let note = match observation {
    NotEvaluable(reason) => Some(reason)
    _ => None
  }
  {
    "state": state_name(observation),
    "diameter_mm": optional_mm(mm),
    "note": optional_string(note),
  }
}

///|
fn study_json(study : @lesion.Study) -> Json {
  let targets : Array[Json] = study.targets.map(target => {
    "id": target.id,
    "organ": target.organ,
    "kind": kind_name(target.kind),
    "baseline_mm": format_diameter_mm(target.baseline_tenths_mm),
  })
  {
    "schema_version": 1,
    "study_id": study.id,
    "baseline_date": study.baseline_date,
    "technique_id": study.technique_id,
    "slice_thickness_mm": format_diameter_mm(study.slice_thickness_tenths_mm),
    "targets": targets.to_json(),
  }
}

///|
fn summary_json(trajectory : @evidence.Trajectory) -> Json {
  let counts : Map[String, Int] = {
    "CR": 0,
    "PR": 0,
    "SD": 0,
    "PD": 0,
    "NE": 0,
  }
  let mut missing = 0
  let mut defaults = 0
  for assessment in trajectory.assessments {
    let key = assessment.response.code()
    counts[key] = counts[key] + 1
    for finding in assessment.findings {
      if finding.code == "missing_measurement" {
        missing += 1
      }
      if finding.code == "default_5mm" {
        defaults += 1
      }
    }
  }
  {
    "target_count": trajectory.study.targets.length(),
    "visit_count": trajectory.assessments.length(),
    "response_counts": counts.to_json(),
    "missing_measurements": missing,
    "defaulted_measurements": defaults,
  }
}

///|
/// Deterministic, versioned evidence envelope. It retains original observations,
/// resolved measurement values and the exact prior nadir for every visit.
pub fn render_audit_json(trajectory : @evidence.Trajectory) -> String {
  let visits : Array[Json] = trajectory.visits.map(visit => {
    let measurements : Array[Json] = visit.measurements.map(measurement => {
      "lesion_id": measurement.lesion_id,
      "observation": observation_json(measurement.observation),
    })
    {
      "id": visit.id,
      "date": visit.date,
      "technique_id": visit.technique_id,
      "measurements": measurements.to_json(),
    }
  })
  let assessments : Array[Json] = trajectory.assessments.map(assessment => {
    let measurements : Array[Json] = assessment.measurements.map(measurement => {
      "lesion_id": measurement.lesion_id,
      "kind": kind_name(measurement.kind),
      "baseline_mm": format_diameter_mm(measurement.baseline_tenths_mm),
      "observation": observation_json(measurement.observation),
      "effective_mm": optional_mm(measurement.effective_tenths_mm),
    })
    let findings : Array[Json] = assessment.findings.map(finding => {
      "code": finding.code,
      "lesion_id": optional_string(finding.lesion_id),
      "message": finding.message,
    })
    {
      "visit_id": assessment.visit_id,
      "date": assessment.date,
      "target_response": assessment.response.code(),
      "sum_mm": optional_mm(assessment.sum_tenths_mm),
      "baseline_sum_mm": format_diameter_mm(assessment.baseline_sum_tenths_mm),
      "prior_nadir_mm": format_diameter_mm(assessment.nadir_sum_tenths_mm),
      "prior_nadir_visit_id": assessment.nadir_visit_id,
      "baseline_change_basis_points": optional_int(
        assessment.baseline_change_basis_points,
      ),
      "nadir_change_basis_points": optional_int(
        assessment.nadir_change_basis_points,
      ),
      "measurements": measurements.to_json(),
      "findings": findings.to_json(),
    }
  })
  let document : Json = {
    "schema_version": 1,
    "ruleset": "recist-1.1-target-subset-1",
    "scope": "target_lesions_only",
    "study": study_json(trajectory.study),
    "visits": visits.to_json(),
    "assessments": assessments.to_json(),
    "summary": summary_json(trajectory),
  }
  document.stringify(indent=2) + "\n"
}

///|
pub fn render_validation_json(
  diagnostics : Array[Diagnostic],
  issues : Array[@evidence.InputIssue],
  visit_count : Int,
) -> String {
  let diagnostics : Array[Json] = diagnostics.map(d => {
    "code": d.code,
    "message": d.message,
    "line": optional_int(d.line),
    "column": optional_int(d.column),
    "field": optional_string(d.field),
  })
  let issues : Array[Json] = issues.map(i => {
    "code": i.code.code(),
    "message": i.message,
    "visit_id": optional_string(i.visit_id),
    "lesion_id": optional_string(i.lesion_id),
  })
  let result : Json = {
    "schema_version": 1,
    "valid": diagnostics.is_empty() && issues.is_empty(),
    "visit_count": visit_count,
    "diagnostics": diagnostics.to_json(),
    "input_issues": issues.to_json(),
  }
  result.stringify(indent=2) + "\n"
}
