///|
fn file_result(files : Array[(String, String)]) -> Json {
  {
    "files": files
    .map(pair => {
      let file : Json = { "name": pair.0, "content": pair.1 }
      file
    })
    .to_json(),
  }
}

///|
fn decode_bundle_files(
  fields : Map[String, Json],
) -> Array[(String, String)] raise RequestError {
  guard fields.get("files") is Some(Array(values)) && values.length() <= 4 else {
    raise RequestError(
      "request_schema", "$.files", "Expected up to four artifact files.",
    )
  }
  let files = []
  for value in values {
    guard value is Object(file) && file.length() == 2 else {
      raise RequestError(
        "request_schema", "$.files", "Expected name and content strings.",
      )
    }
    files.push((string_field(file, "name"), string_field(file, "content")))
  }
  files
}

///|
fn count_field(
  fields : Map[String, Json],
  key : String,
) -> Int raise RequestError {
  match fields.get(key) {
    Some(Number(value, ..)) if value >= 0.0 &&
      value <= 2147483647.0 &&
      value == value.to_int().to_double() => value.to_int()
    _ =>
      raise RequestError(
        "request_schema",
        "$.cases." + key,
        "Expected a nonnegative integer count.",
      )
  }
}

///|
fn decode_batch_results(
  fields : Map[String, Json],
) -> Array[@lib.BatchResult] raise RequestError {
  guard fields.get("cases") is Some(Array(values)) &&
    values.length() > 0 &&
    values.length() <= 20 else {
    raise RequestError(
      "request_schema", "$.cases", "Expected one to twenty case results.",
    )
  }
  let results : Array[@lib.BatchResult] = []
  let identifiers : Array[Json] = []
  for value in values {
    guard value is Object(row) && row.length() == 5 else {
      raise RequestError(
        "request_schema", "$.cases", "Expected id, status, message and two counts.",
      )
    }
    let id = string_field(row, "id")
    let status = string_field(row, "status")
    guard ["success", "input_error", "io_error"].contains(status) else {
      raise RequestError(
        "request_schema", "$.cases.status", "Unsupported case status.",
      )
    }
    identifiers.push({
      "id": id,
      "study": "study.json",
      "input": "followup.csv",
    })
    results.push({
      id,
      status,
      message: string_field(row, "message"),
      visit_count: count_field(row, "visit_count"),
      review_hint_count: count_field(row, "review_hint_count"),
      report_path: if status == "success" {
        Some(id + "/report.html")
      } else {
        None
      },
    })
  }
  // Reuse the CLI's portable, unique identifier validation without reading paths.
  let manifest : Json = { "schema_version": 1, "cases": identifiers.to_json() }
  guard @lib.parse_batch_json(manifest.stringify()) is Ok(_) else {
    raise RequestError(
      "request_schema", "$.cases.id", "Case identifiers must be portable and unique.",
    )
  }
  results
}

///|
fn dispatch_batch_index(request : Request) -> Json {
  envelope(
    "batch-index",
    true,
    Json::null(),
    [],
    Json::null(),
    file_result([
      ("index.json", @lib.render_batch_index_json(request.batch_results)),
      (
        "index.html",
        @lib.render_batch_index_html(
          request.batch_results,
          language=request.language,
        ),
      ),
    ]),
  )
}

///|
fn dispatch_bundle_check(request : Request) -> Json {
  let issues = @lib.verify_bundle(
    request.manifest,
    request.files.map(pair => (pair.0, @utf8.encode(pair.1))),
  )
  let content = @lib.render_validation_json(issues, [], 0)
  let validation : Json = @json.parse(content) catch {
    _ => abort("Invalid core validation JSON")
  }
  guard validation is { "diagnostics": details, .. } else {
    abort("Missing core diagnostics")
  }
  envelope(
    "verify-bundle",
    issues.is_empty(),
    if issues.is_empty() {
      Json::null()
    } else {
      "bundle"
    },
    details,
    Json::null(),
    if issues.is_empty() {
      report_result("json", content)
    } else {
      Json::null()
    },
  )
}
