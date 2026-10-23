///|
priv suberror StudyDecodeError {
  StudyDecodeError(String, String)
}

///|
fn object(
  value : Json,
  path : String,
  keys : Array[String],
) -> Map[String, Json] raise StudyDecodeError {
  guard value is Object(fields) else {
    raise StudyDecodeError(path, "Expected an object.")
  }
  for key, _ in fields {
    if !keys.contains(key) {
      raise StudyDecodeError(path + "." + key, "Unknown field.")
    }
  }
  fields
}

///|
fn required(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Json raise StudyDecodeError {
  match fields.get(key) {
    Some(value) => value
    None =>
      raise StudyDecodeError(path + "." + key, "Required field is missing.")
  }
}

///|
fn string_field(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> String raise StudyDecodeError {
  match required(fields, key, path) {
    String(value) => value
    _ => raise StudyDecodeError(path + "." + key, "Expected a string.")
  }
}

///|
fn mm_field(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Int raise StudyDecodeError {
  let value = string_field(fields, key, path)
  match parse_diameter_mm(value) {
    Ok(mm) => mm
    Err(message) => raise StudyDecodeError(path + "." + key, message)
  }
}

///|
fn decode_study(value : Json) -> @lesion.Study raise StudyDecodeError {
  let fields = object(value, "$", [
    "schema_version", "study_id", "baseline_date", "technique_id", "slice_thickness_mm",
    "targets",
  ])
  match required(fields, "schema_version", "$") {
    Number(version, ..) if version == 1.0 => ()
    _ =>
      raise StudyDecodeError(
        "$.schema_version", "Only schema_version 1 is supported.",
      )
  }
  let targets_json = match required(fields, "targets", "$") {
    Array(values) => values
    _ => raise StudyDecodeError("$.targets", "Expected an array.")
  }
  let targets : Array[@lesion.TargetLesion] = []
  for i, target in targets_json {
    let path = "$.targets[\{i}]"
    let fields = object(target, path, ["id", "organ", "kind", "baseline_mm"])
    let kind : @lesion.LesionKind = match string_field(fields, "kind", path) {
      "non_nodal" => NonNodal
      "lymph_node" => LymphNode
      _ =>
        raise StudyDecodeError(path + ".kind", "Use non_nodal or lymph_node.")
    }
    targets.push({
      id: string_field(fields, "id", path),
      organ: string_field(fields, "organ", path),
      kind,
      baseline_tenths_mm: mm_field(fields, "baseline_mm", path),
    })
  }
  {
    id: string_field(fields, "study_id", "$"),
    baseline_date: string_field(fields, "baseline_date", "$"),
    technique_id: string_field(fields, "technique_id", "$"),
    slice_thickness_tenths_mm: mm_field(fields, "slice_thickness_mm", "$"),
    targets,
  }
}

///|
/// Decode a versioned study profile. Call validate_study for clinical-contract
/// validation after schema parsing. Numeric diameters must be decimal strings.
pub fn parse_study_json(
  text : String,
) -> Result[@lesion.Study, Array[Diagnostic]] {
  let value = @json.parse(text) catch {
    error => return Err([diagnostic("json_syntax", error.to_string())])
  }
  try decode_study(value) catch {
    StudyDecodeError(path, message) =>
      Err([diagnostic("study_schema", message, field=path)])
  } noraise {
    study => Ok(study)
  }
}
