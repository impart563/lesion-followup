///|
fn envelope(
  action : Json,
  ok : Bool,
  error_kind : Json,
  diagnostics : Json,
  preflight : Json,
  result : Json,
) -> Json {
  {
    "schema_version": 1,
    "scope": "target_lesions_only",
    "action": action,
    "ok": ok,
    "error_kind": error_kind,
    "diagnostics": diagnostics,
    "preflight": preflight,
    "result": result,
  }
}

///|
fn report_result(format : String, content : String) -> Json {
  let media_type = match format {
    "json" => "application/json"
    "csv" => "text/csv"
    "markdown" => "text/markdown"
    "svg" => "image/svg+xml"
    _ => "text/html"
  }
  { "format": format, "media_type": media_type, "content": content }
}

///|
fn dispatch(request : Request) -> Json {
  let action = Json::string(request.action)
  if request.action == "verify-bundle" {
    return dispatch_bundle_check(request)
  }
  if request.action == "batch-index" {
    return dispatch_batch_index(request)
  }
  if request.action == "compare" {
    return dispatch_comparison(request)
  }
  if request.action == "template" {
    // The name has already been checked at the request boundary.
    let files = @lib.input_template_files(
      request.template,
      language=request.language,
    ).unwrap()
    return envelope(action, true, Json::null(), [], Json::null(), {
      "files": files
      .map(pair => {
        let file : Json = { "name": pair.0, "content": pair.1 }
        file
      })
      .to_json(),
    })
  }
  let preflight = @lib.preflight_inputs(
    request.study_json,
    request.followup_csv,
  )
  let quality = @json.parse(@lib.render_preflight_json(preflight)) catch {
    _ => abort("Core preflight renderer returned invalid JSON")
  }
  if request.action == "editor" {
    // A table can retain invalid clinical observations for correction. It is
    // not a replay result; preflight.valid must still gate reports and printing.
    guard @lib.parse_study_json(request.study_json) is Ok(_) &&
      @lib.parse_followup_cells(request.followup_csv) is Ok(rows) else {
      return envelope(action, false, "input", [], quality, Json::null())
    }
    let study = @json.parse(request.study_json) catch {
      _ => abort("Validated study JSON could not be decoded")
    }
    return envelope(action, true, Json::null(), [], quality, {
      "study": study,
      "rows": rows.to_json(),
    })
  }
  if !preflight.is_valid() {
    return envelope(action, false, "input", [], quality, Json::null())
  }
  if request.action == "preflight" {
    let content = if request.format == "json" {
      @lib.render_preflight_json(preflight)
    } else {
      @lib.render_preflight_markdown(preflight, language=request.language)
    }
    return envelope(
      action,
      true,
      Json::null(),
      [],
      quality,
      report_result(request.format, content),
    )
  }
  // Preflight has checked both parsers and validate_track. Replay uses the same
  // in-memory values and core implementation as the native CLI.
  let study = @lib.parse_study_json(request.study_json).unwrap()
  let visits = @lib.parse_followup_csv(request.followup_csv).unwrap()
  let trajectory = @lib.replay_track(study, visits).unwrap()
  if request.action == "bundle" {
    let files = @lib.review_artifacts(trajectory, language=request.language)
    let manifest = @lib.render_bundle_manifest(
      trajectory,
      files,
      language=request.language,
      raw_inputs=[
        ("study", @utf8.encode(request.study_json)),
        ("followup", @utf8.encode(request.followup_csv)),
      ],
    )
    files.push(("manifest.json", manifest))
    return envelope(action, true, Json::null(), [], quality, file_result(files))
  }
  let content = match request.format {
    "json" => @lib.render_audit_json(trajectory)
    "csv" => @lib.render_audit_csv(trajectory)
    "markdown" => @lib.render_audit_markdown_in(trajectory, request.language)
    "svg" => @lib.render_trajectory_svg_in(trajectory, request.language)
    _ => @lib.render_audit_html_in(trajectory, request.language)
  }
  envelope(
    action,
    true,
    Json::null(),
    [],
    quality,
    report_result(request.format, content),
  )
}

///|
/// Pure, synchronous JSON-string boundary for JavaScript ES module consumers.
/// Request/input errors return an envelope; valid NE observations remain success.
/// Diameters stay decimal strings until the existing exact-integer parser runs.
pub fn evaluate(request_json : String) -> String {
  let response = try decode_request(request_json) catch {
    RequestError(code, field, message) =>
      envelope(
        Json::null(),
        false,
        "request",
        [{ "code": code, "field": field, "message": message }],
        Json::null(),
        Json::null(),
      )
  } noraise {
    request => dispatch(request)
  }
  response.stringify() + "\n"
}
