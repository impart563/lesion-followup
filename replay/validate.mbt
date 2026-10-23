///|
fn issue(
  code : @evidence.IssueCode,
  message : String,
  visit_id? : String,
  lesion_id? : String,
) -> @evidence.InputIssue {
  { code, message, visit_id, lesion_id, }
}

///|
fn valid_id(value : String) -> Bool {
  !value.is_blank() &&
  value == value.trim().to_owned() &&
  value.length() <= 128 &&
  value.iter().all(c => c.to_int() >= 32 && c.to_int() != 127)
}

///|
fn digits(text : String, start : Int, end : Int) -> Int? {
  let mut value = 0
  for i in start..<end {
    let digit = text[i].to_int() - 48
    if digit < 0 || digit > 9 {
      return None
    }
    value = value * 10 + digit
  }
  Some(value)
}

///|
fn valid_date(text : String) -> Bool {
  if text.length() != 10 || text[4] != '-' || text[7] != '-' {
    return false
  }
  guard digits(text, 0, 4) is Some(year) &&
    digits(text, 5, 7) is Some(month) &&
    digits(text, 8, 10) is Some(day) else {
    return false
  }
  if year < 1 || month < 1 || month > 12 || day < 1 {
    return false
  }
  let limit = match month {
    2 =>
      if year % 400 == 0 || (year % 4 == 0 && year % 100 != 0) {
        29
      } else {
        28
      }
    4 | 6 | 9 | 11 => 30
    _ => 31
  }
  day <= limit
}

///|
/// Validate the CT target-set contract before any comparisons are made.
/// The software diameter limit is 1000.0 mm per target, not a clinical threshold.
pub fn validate_study(study : @lesion.Study) -> Array[@evidence.InputIssue] {
  let issues = []
  if !valid_id(study.id) || !valid_id(study.technique_id) {
    issues.push(
      issue(
        InvalidStudy,
        "Study and technique IDs must be nonblank, trimmed and at most 128 characters.",
      ),
    )
  }
  if !valid_date(study.baseline_date) {
    issues.push(
      issue(
        InvalidDate,
        "Baseline date must be a valid Gregorian YYYY-MM-DD date.",
      ),
    )
  }
  if study.slice_thickness_tenths_mm < 1 || study.slice_thickness_tenths_mm > 50 {
    issues.push(
      issue(
        InvalidStudy,
        "This version supports CT slices from 0.1 through 5.0 mm.",
      ),
    )
  }
  if study.targets.is_empty() || study.targets.length() > 5 {
    issues.push(
      issue(TooManyTargets, "Select between one and five target lesions."),
    )
  }
  let ids : Map[String, Bool] = Map([])
  let organs : Map[String, Int] = Map([])
  for target in study.targets {
    if !valid_id(target.id) || !valid_id(target.organ) {
      issues.push(
        issue(
          InvalidTarget,
          "Target and canonical organ IDs must be nonblank and trimmed.",
          lesion_id=target.id,
        ),
      )
    }
    if ids.contains(target.id) {
      issues.push(
        issue(
          DuplicateId,
          "Target ID occurs more than once.",
          lesion_id=target.id,
        ),
      )
    }
    ids[target.id] = true
    let count = organs.get(target.organ).unwrap_or(0) + 1
    organs[target.organ] = count
    if count == 3 {
      issues.push(
        issue(
          TooManyPerOrgan,
          "At most two targets may belong to the same canonical organ group.",
          lesion_id=target.id,
        ),
      )
    }
    let minimum = match target.kind {
      NonNodal => 100
      LymphNode => 150
    }
    if target.baseline_tenths_mm < minimum || target.baseline_tenths_mm > 10000 {
      issues.push(
        issue(
          InvalidTarget,
          "Baseline diameter is below the target minimum or above the 1000.0 mm software limit.",
          lesion_id=target.id,
        ),
      )
    }
    if (target.kind is LymphNode) != (target.organ == "lymph_nodes") {
      issues.push(
        issue(
          InvalidTarget,
          "All lymph-node targets must use organ group lymph_nodes; other targets must not.",
          lesion_id=target.id,
        ),
      )
    }
  }
  issues
}

///|
/// Structural errors reject the whole trajectory. Omitted targets and explicit
/// missing observations are valid inputs that produce NE rather than errors.
pub fn validate_track(
  study : @lesion.Study,
  visits : Array[@visit.Visit],
) -> Array[@evidence.InputIssue] {
  let issues = validate_study(study)
  let targets : Map[String, Bool] = Map([])
  for target in study.targets {
    targets[target.id] = true
  }
  let ids : Map[String, Bool] = { "baseline": true }
  let mut previous = study.baseline_date
  for visit in visits {
    if !valid_id(visit.id) || !valid_id(visit.technique_id) {
      issues.push(
        issue(
          InvalidStudy,
          "Visit and technique IDs must be nonblank and trimmed.",
          visit_id=visit.id,
        ),
      )
    }
    if ids.contains(visit.id) {
      issues.push(
        issue(
          DuplicateId,
          "Visit ID is duplicated or uses reserved ID baseline.",
          visit_id=visit.id,
        ),
      )
    }
    ids[visit.id] = true
    if !valid_date(visit.date) {
      issues.push(
        issue(
          InvalidDate,
          "Visit date must be a valid Gregorian YYYY-MM-DD date.",
          visit_id=visit.id,
        ),
      )
    }
    if visit.date <= previous {
      issues.push(
        issue(
          InvalidVisitOrder,
          "Visit dates must strictly increase after baseline; input is never sorted.",
          visit_id=visit.id,
        ),
      )
    }
    previous = visit.date
    let seen : Map[String, Bool] = Map([])
    for measurement in visit.measurements {
      if !targets.contains(measurement.lesion_id) {
        issues.push(
          issue(
            UnknownTarget,
            "Measurement refers to a target outside the fixed baseline set.",
            visit_id=visit.id,
            lesion_id=measurement.lesion_id,
          ),
        )
      }
      if seen.contains(measurement.lesion_id) {
        issues.push(
          issue(
            DuplicateId,
            "Target has duplicate measurements in this visit.",
            visit_id=visit.id,
            lesion_id=measurement.lesion_id,
          ),
        )
      }
      seen[measurement.lesion_id] = true
      match measurement.observation {
        Measured(size) if size < 0 || size > 10000 =>
          issues.push(
            issue(
              InvalidMeasurement,
              "Diameter must be between 0.0 and 1000.0 mm.",
              visit_id=visit.id,
              lesion_id=measurement.lesion_id,
            ),
          )
        NotEvaluable(reason) if reason.is_blank() =>
          issues.push(
            issue(
              InvalidMeasurement,
              "A not-evaluable observation needs a reader-provided reason.",
              visit_id=visit.id,
              lesion_id=measurement.lesion_id,
            ),
          )
        _ => ()
      }
    }
  }
  issues
}
