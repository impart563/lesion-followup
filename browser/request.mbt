///|
priv suberror RequestError {
  RequestError(String, String, String)
}

///|
priv struct Request {
  action : String
  language : @lib.ReportLanguage
  format : String
  study_json : String
  followup_csv : String
  template : String
  compare_study_json : String
  compare_followup_csv : String
  manifest : String
  files : Array[(String, String)]
  batch_results : Array[@lib.BatchResult]
}

///|
fn string_field(
  fields : Map[String, Json],
  key : String,
  default? : String,
) -> String raise RequestError {
  match fields.get(key) {
    Some(String(value)) => value
    None =>
      match default {
        Some(value) => value
        None =>
          raise RequestError(
            "request_schema",
            "$." + key,
            "Required string field is missing.",
          )
      }
    _ => raise RequestError("request_schema", "$." + key, "Expected a string.")
  }
}

///|
fn decode_request(text : String) -> Request raise RequestError {
  let value = @json.parse(text) catch {
    _ => raise RequestError("request_json", "$", "Request is not valid JSON.")
  }
  guard value is Object(fields) else {
    raise RequestError("request_schema", "$", "Expected an object.")
  }
  guard fields.get("schema_version") is Some(Number(1.0, ..)) else {
    raise RequestError(
      "request_version", "$.schema_version", "Only schema_version 1 is supported.",
    )
  }
  let action = string_field(fields, "action")
  guard [
    "review", "preflight", "template", "editor", "compare", "bundle", "verify-bundle",
    "batch-index",
  ].contains(action) else {
    raise RequestError(
      "request_action", "$.action", "Unsupported browser action.",
    )
  }
  let keys = if action == "verify-bundle" {
    ["schema_version", "action", "manifest", "files"]
  } else if action == "batch-index" {
    ["schema_version", "action", "language", "cases"]
  } else if action == "template" {
    ["schema_version", "action", "language", "template"]
  } else if action == "editor" || action == "bundle" {
    ["schema_version", "action", "language", "study_json", "followup_csv"]
  } else if action == "compare" {
    [
      "schema_version", "action", "language", "format", "study_json", "followup_csv",
      "compare_study_json", "compare_followup_csv",
    ]
  } else {
    [
      "schema_version", "action", "language", "format", "study_json", "followup_csv",
    ]
  }
  for key, _ in fields {
    if !keys.contains(key) {
      raise RequestError(
        "request_schema",
        "$." + key,
        "Unknown field for this action.",
      )
    }
  }
  let language : @lib.ReportLanguage = match
    string_field(fields, "language", default="en") {
    "en" => English
    "zh-CN" => SimplifiedChinese
    _ =>
      raise RequestError("request_language", "$.language", "Use en or zh-CN.")
  }
  let template = if action == "template" {
    let name = string_field(fields, "template", default="multi")
    guard ["single", "multi"].contains(name) else {
      raise RequestError(
        "request_template", "$.template", "Use single or multi.",
      )
    }
    name
  } else {
    ""
  }
  let format = if [
      "template", "editor", "bundle", "verify-bundle", "batch-index",
    ].contains(action) {
    ""
  } else {
    let format = string_field(fields, "format", default="json")
    let supported = if action == "compare" {
      ["json", "markdown", "html"]
    } else if action == "preflight" {
      ["json", "markdown"]
    } else {
      ["json", "csv", "markdown", "svg", "html"]
    }
    guard supported.contains(format) else {
      raise RequestError(
        "request_format", "$.format", "Unsupported format for this action.",
      )
    }
    format
  }
  {
    action,
    language,
    format,
    template,
    manifest: if action == "verify-bundle" {
      string_field(fields, "manifest")
    } else {
      ""
    },
    files: if action == "verify-bundle" {
      decode_bundle_files(fields)
    } else {
      []
    },
    batch_results: if action == "batch-index" {
      decode_batch_results(fields)
    } else {
      []
    },
    compare_study_json: if action == "compare" {
      string_field(fields, "compare_study_json")
    } else {
      ""
    },
    compare_followup_csv: if action == "compare" {
      string_field(fields, "compare_followup_csv")
    } else {
      ""
    },
    study_json: if ["template", "verify-bundle", "batch-index"].contains(action) {
      ""
    } else {
      string_field(fields, "study_json")
    },
    followup_csv: if ["template", "verify-bundle", "batch-index"].contains(
        action,
      ) {
      ""
    } else {
      string_field(fields, "followup_csv")
    },
  }
}
