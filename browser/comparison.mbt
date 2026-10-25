///|
fn dispatch_comparison(request : Request) -> Json {
  let before = @lib.preflight_inputs(
    request.compare_study_json,
    request.compare_followup_csv,
  )
  let after = @lib.preflight_inputs(request.study_json, request.followup_csv)
  let before_quality : Json = @json.parse(@lib.render_preflight_json(before)) catch {
    _ => abort("Invalid core preflight JSON")
  }
  let after_quality : Json = @json.parse(@lib.render_preflight_json(after)) catch {
    _ => abort("Invalid core preflight JSON")
  }
  let quality : Json = { "before": before_quality, "after": after_quality }
  if !before.is_valid() || !after.is_valid() {
    return envelope("compare", false, "input", [], quality, Json::null())
  }
  let original = @lib.replay_track(
    @lib.parse_study_json(request.compare_study_json).unwrap(),
    @lib.parse_followup_csv(request.compare_followup_csv).unwrap(),
  ).unwrap()
  let current = @lib.replay_track(
    @lib.parse_study_json(request.study_json).unwrap(),
    @lib.parse_followup_csv(request.followup_csv).unwrap(),
  ).unwrap()
  let revision = match @lib.compare_tracks(original, current) {
    Ok(value) => value
    Err(diagnostics) => {
      let validation = @json.parse(
        @lib.render_validation_json(diagnostics, [], 0),
      ) catch {
        _ => abort("Invalid core diagnostic JSON")
      }
      guard validation is { "diagnostics": details, .. } else {
        abort("Missing core diagnostics")
      }
      return envelope(
        "compare",
        false,
        "comparison",
        details,
        quality,
        Json::null(),
      )
    }
  }
  let content = match request.format {
    "html" => @lib.render_revision_html(revision, language=request.language)
    "markdown" =>
      @lib.render_revision_markdown(revision, language=request.language)
    _ => @lib.render_revision_json(revision)
  }
  envelope(
    "compare",
    true,
    Json::null(),
    [],
    quality,
    report_result(request.format, content),
  )
}
