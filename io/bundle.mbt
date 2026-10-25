///|
fn artifact_names() -> Array[String] {
  ["report.html", "audit.json", "audit.csv", "chart.svg"]
}

///|
/// Four deterministic artifacts. Manifest construction hashes their UTF-8 bytes.
pub fn review_artifacts(
  trajectory : @evidence.Trajectory,
  language? : ReportLanguage = English,
) -> Array[(String, String)] {
  [
    ("report.html", render_audit_html_in(trajectory, language)),
    ("audit.json", render_audit_json(trajectory)),
    ("audit.csv", render_audit_csv(trajectory)),
    ("chart.svg", render_trajectory_svg_in(trajectory, language)),
  ]
}

///|
/// V2 adds exact raw-file input digests when available and always includes
/// semantic input digests. No timestamps or local source paths affect determinism.
pub fn render_bundle_manifest(
  trajectory : @evidence.Trajectory,
  artifacts : Array[(String, String)],
  language? : ReportLanguage = English,
  raw_inputs? : Array[(String, Bytes)] = [],
) -> String {
  let visits : Array[Json] = trajectory.visits.map(visit_input_json)
  let inputs : Array[Json] = [
    {
      "name": "study",
      "representation": "canonical_json",
      "sha256": sha256_hex(
        @utf8.encode(study_json(trajectory.study).stringify()),
      ),
    },
    {
      "name": "followup",
      "representation": "canonical_json",
      "sha256": sha256_hex(@utf8.encode(visits.to_json().stringify())),
    },
  ]
  for (name, bytes) in raw_inputs {
    inputs.push({
      "name": name,
      "representation": "raw_bytes",
      "sha256": sha256_hex(bytes),
    })
  }
  let files : Array[Json] = artifacts.map(pair => {
    let bytes = @utf8.encode(pair.1)
    {
      "name": pair.0,
      "byte_length": bytes.length(),
      "sha256": sha256_hex(bytes),
    }
  })
  let document : Json = {
    "schema_version": 2,
    "software": "impart563/lesion-followup",
    "software_version": "0.2.0",
    "ruleset": "recist-1.1-target-subset-1",
    "scope": "target_lesions_only",
    "language": tr(language, "en", "zh-CN"),
    "inputs": inputs.to_json(),
    "artifacts": files.to_json(),
    "summary": summary_json(trajectory),
  }
  document.stringify(indent=2) + "\n"
}

///|
fn hash_field(
  fields : Map[String, Json],
  path : String,
) -> String raise StudyDecodeError {
  let hash = string_field(fields, "sha256", path)
  if hash.length() != 64 ||
    !hash.iter().all(c => (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) {
    raise StudyDecodeError(
      path + ".sha256",
      "Expected 64 lowercase hexadecimal digits.",
    )
  }
  hash
}

///|
fn verify_manifest(
  value : Json,
  artifacts : Array[(String, Bytes)],
) -> Array[Diagnostic] raise StudyDecodeError {
  let fields = object(value, "$", [
    "schema_version", "software", "software_version", "ruleset", "scope", "language",
    "inputs", "artifacts", "summary",
  ])
  guard required(fields, "schema_version", "$") is Number(2.0, ..) else {
    raise StudyDecodeError(
      "$.schema_version", "Only bundle schema version 2 is supported.",
    )
  }
  for
    (key, expected) in [
      ("software", "impart563/lesion-followup"),
      ("software_version", "0.2.0"),
      ("ruleset", "recist-1.1-target-subset-1"),
      ("scope", "target_lesions_only"),
    ] {
    if string_field(fields, key, "$") != expected {
      raise StudyDecodeError("$." + key, "Unsupported bundle profile.")
    }
  }
  if !["en", "zh-CN"].contains(string_field(fields, "language", "$")) {
    raise StudyDecodeError("$.language", "Unsupported language.")
  }
  ignore(required(fields, "summary", "$"))
  guard required(fields, "inputs", "$") is Array(inputs) else {
    raise StudyDecodeError("$.inputs", "Expected input fingerprints.")
  }
  let input_names : Map[String, Bool] = Map([])
  let input_hashes : Map[String, String] = Map([])
  for i, item in inputs {
    let path = "$.inputs[\{i}]"
    let item = object(item, path, ["name", "representation", "sha256"])
    let name = string_field(item, "name", path)
    let representation = string_field(item, "representation", path)
    if !["study", "followup"].contains(name) ||
      !["canonical_json", "raw_bytes"].contains(representation) ||
      input_names.contains(name + representation) {
      raise StudyDecodeError(path, "Unknown or duplicate input fingerprint.")
    }
    input_names[name + representation] = true
    input_hashes[name + representation] = hash_field(item, path)
  }
  if !input_names.contains("studycanonical_json") ||
    !input_names.contains("followupcanonical_json") {
    raise StudyDecodeError(
      "$.inputs", "Semantic input fingerprints are required.",
    )
  }
  guard required(fields, "artifacts", "$") is Array(files) else {
    raise StudyDecodeError("$.artifacts", "Expected an array.")
  }
  let expected_names = artifact_names()
  let seen : Map[String, Bool] = Map([])
  let supplied : Map[String, Bytes] = Map([])
  for (name, bytes) in artifacts {
    if !expected_names.contains(name) || supplied.contains(name) {
      raise StudyDecodeError(
        "$.artifacts", "Unknown or duplicate supplied artifact.",
      )
    }
    supplied[name] = bytes
  }
  let issues = []
  for i, item in files {
    let path = "$.artifacts[\{i}]"
    let item = object(item, path, ["name", "byte_length", "sha256"])
    let name = string_field(item, "name", path)
    if !expected_names.contains(name) || seen.contains(name) {
      raise StudyDecodeError(
        path + ".name",
        "Unknown or duplicate artifact name.",
      )
    }
    seen[name] = true
    let digest = hash_field(item, path)
    let length = match required(item, "byte_length", path) {
      Number(value, ..) if value >= 0.0 &&
        value <= 2147483647.0 &&
        value == value.to_int().to_double() => value.to_int()
      _ =>
        raise StudyDecodeError(
          path + ".byte_length",
          "Expected a nonnegative byte length.",
        )
    }
    match supplied.get(name) {
      None =>
        issues.push(
          diagnostic(
            "bundle_missing",
            "Missing regular file: " + name,
            field=path,
          ),
        )
      Some(bytes) =>
        if bytes.length() != length || sha256_hex(bytes) != digest {
          issues.push(
            diagnostic(
              "bundle_mismatch",
              "Length or SHA-256 mismatch: " + name,
              field=path,
            ),
          )
        }
    }
  }
  if seen.length() != 4 {
    raise StudyDecodeError(
      "$.artifacts", "Exactly four named artifacts are required.",
    )
  }
  if issues.is_empty() && supplied.get("audit.json") is Some(bytes) {
    let text = @utf8.decode(bytes) catch {
      _ =>
        raise StudyDecodeError("$.artifacts", "Audit JSON must be valid UTF-8.")
    }
    let audit = @json.parse(text) catch {
      _ => raise StudyDecodeError("$.artifacts", "Audit JSON is malformed.")
    }
    let audit = object(audit, "$.audit", [
      "schema_version", "ruleset", "scope", "study", "visits", "assessments", "summary",
    ])
    let study_value = required(audit, "study", "$.audit")
    let study = match parse_study_json(study_value.stringify()) {
      Ok(study) => study
      Err(_) =>
        raise StudyDecodeError(
          "$.audit.study", "Audit study profile is invalid.",
        )
    }
    let study_digest = sha256_hex(@utf8.encode(study_json(study).stringify()))
    let visit_digest = sha256_hex(
      @utf8.encode(required(audit, "visits", "$.audit").stringify()),
    )
    if input_hashes.get("studycanonical_json") != Some(study_digest) ||
      input_hashes.get("followupcanonical_json") != Some(visit_digest) ||
      required(audit, "summary", "$.audit") != required(fields, "summary", "$") ||
      string_field(audit, "scope", "$.audit") != "target_lesions_only" ||
      string_field(audit, "ruleset", "$.audit") != "recist-1.1-target-subset-1" {
      issues.push(
        diagnostic(
          "bundle_metadata", "Semantic input fingerprint, profile or summary differs from audit.json.",
        ),
      )
    }
  }
  issues
}

///|
/// Validate metadata and exact supplied artifact bytes. Fixed artifact names are
/// the only allowed names; callers must not resolve arbitrary manifest paths.
pub fn verify_bundle(
  manifest : String,
  artifacts : Array[(String, Bytes)],
) -> Array[Diagnostic] {
  let value = @json.parse(manifest) catch {
    error => return [diagnostic("bundle_schema", error.to_string())]
  }
  try verify_manifest(value, artifacts) catch {
    StudyDecodeError(path, message) =>
      [diagnostic("bundle_schema", message, field=path)]
  } noraise {
    issues => issues
  }
}
