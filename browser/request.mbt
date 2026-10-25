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
  guard ["review", "preflight", "template", "editor", "compare"].contains(
    action,
  ) else {
    raise RequestError(
      "request_action", "$.action", "Use review, preflight, template, editor or compare.",
    )
  }
  let keys = if action == "template" {
    ["schema_version", "action", "language", "template"]
  } else if action == "editor" {
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
  let format = if action == "template" || action == "editor" {
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
    study_json: if action == "template" {
      ""
    } else {
      string_field(fields, "study_json")
    },
    followup_csv: if action == "template" {
      ""
    } else {
      string_field(fields, "followup_csv")
    },
  }
}
