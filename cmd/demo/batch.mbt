///|
fn resolve_input(directory : String, path : String) -> String {
  if path.has_prefix("/") ||
    path.has_prefix("\\") ||
    (path.length() > 1 && path[1] == ':') {
    path
  } else {
    directory + "/" + path
  }
}

///|
async fn batch_case(
  case : @lib.BatchCase,
  base : String,
  destination : String,
  options : CliOptions,
) -> @lib.BatchResult {
  let loaded = load_inputs(
    resolve_input(base, case.study),
    resolve_input(base, case.input),
  )
  guard loaded_trajectory(loaded) is Some(trajectory) else {
    return {
      id: case.id,
      status: "input_error",
      message: @lib.render_preflight_json(loaded.preflight),
      report_path: None,
      visit_count: loaded.preflight.visit_count,
      review_hint_count: loaded.preflight.review_hints.length(),
    }
  }
  write_review_bundle(
    destination + "/" + case.id,
    trajectory,
    loaded.raw_inputs,
    options,
  )
  {
    id: case.id,
    status: "success",
    message: "target_lesions_only",
    report_path: Some(case.id + "/report.html"),
    visit_count: loaded.visits.length(),
    review_hint_count: loaded.preflight.review_hints.length(),
  }
}

///|
async fn run_batch(path : String, options : CliOptions) -> Unit {
  let text = @fs.read_file(path).text()
  let cases = match @lib.parse_batch_json(text) {
    Ok(cases) => cases
    Err(issues) => {
      @stdio.stderr.write(@lib.render_validation_json(issues, [], 0))
      process_exit(2)
      return
    }
  }
  guard options.bundle is Some(directory) else { return }
  if path_exists(directory) {
    die(
      ui(
        options.language,
        "Batch output requires a NEW directory.",
        "批量输出须使用新目录。",
      ),
      language=options.language,
    )
    return
  }
  let manifest = @fs.realpath(path)
  let parts = manifest
    .replace_all(old="\\", new="/")
    .split("/")
    .map(s => s.to_owned())
    .to_array()
  ignore(parts.pop())
  let base = parts.join("/")
  @fs.mkdir(directory)
  let results : Array[@lib.BatchResult] = []
  for case in cases {
    let result = batch_case(case, base, directory, options) catch {
      error =>
        {
          id: case.id,
          status: "io_error",
          message: error.to_string(),
          report_path: None,
          visit_count: 0,
          review_hint_count: 0,
        }
    }
    results.push(result)
  }
  @fs.write_file(
    directory + "/index.json",
    @lib.render_batch_index_json(results),
    create_mode=CreateNew,
  )
  @fs.write_file(
    directory + "/index.html",
    @lib.render_batch_index_html(results, language=options.language),
    create_mode=CreateNew,
  )
  @stdio.stdout.write(
    ui(options.language, "Batch index written to ", "批量索引已写入：") +
    directory +
    "/index.html\n",
  )
  if results.any(r => r.status != "success") {
    process_exit(3)
  }
}
