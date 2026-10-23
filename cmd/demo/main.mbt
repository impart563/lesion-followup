///|
extern "c" fn process_exit(code : Int) -> Unit = "exit"

///|
priv struct CliOptions {
  scenario : String?
  study : String?
  input : String?
  format : String
  output : String?
  bundle : String?
  check_input : Bool
}

///|
fn command() -> @argparse.Command {
  @argparse.Command(
    "lesion-followup",
    about="Review manually measured CT target lesions; target categories only.",
    flags=[
      @argparse.FlagArg(
        "check-input",
        action=SetTrue,
        about="validate schema and track structure without clinical categories",
      ),
    ],
    options=[
      @argparse.OptionArg(
        "scenario",
        about="synthetic demo: nadir-boundary, node-resolution, missing-visit",
      ),
      @argparse.OptionArg(
        "study",
        about="versioned study JSON profile; requires --input",
      ),
      @argparse.OptionArg(
        "input",
        about="long-form follow-up CSV; requires --study",
      ),
      @argparse.OptionArg(
        "format",
        about="markdown (default), json, csv, svg or html",
      ),
      @argparse.OptionArg(
        "output",
        about="write selected format to a file; parent must exist",
      ),
      @argparse.OptionArg(
        "bundle",
        about="write report.html, audit.json/csv, chart.svg and manifest.json",
      ),
    ],
  )
}

///|
fn parse_args(args : Array[String]) -> Result[CliOptions, String] {
  let matches = command().parse(argv=args, env=Map([])) catch {
    error => return Err(error.to_string())
  }
  let value = (key : String) => {
    match matches.values.get(key) {
      Some([one]) => Some(one)
      _ => None
    }
  }
  let study = value("study")
  let input = value("input")
  let scenario = value("scenario")
  let output = value("output")
  let bundle = value("bundle")
  let format = value("format").unwrap_or("markdown")
  let check_input = matches.flags.get("check-input").unwrap_or(false)
  if (study is Some(_)) != (input is Some(_)) {
    return Err("--study and --input must be supplied together.")
  }
  if input is Some(_) && scenario is Some(_) {
    return Err("Choose either --scenario or --study with --input.")
  }
  if !["markdown", "json", "csv", "svg", "html"].contains(format) {
    return Err("Unsupported --format.")
  }
  if bundle is Some(_) &&
    (output is Some(_) || value("format") is Some(_) || check_input) {
    return Err(
      "--bundle cannot be combined with --output, --format or --check-input.",
    )
  }
  if check_input && format != "json" && format != "markdown" {
    return Err("--check-input supports only markdown and json.")
  }
  Ok({ scenario, study, input, format, output, bundle, check_input, })
}

///|
async fn die(message : String, code? : Int = 2) -> Unit {
  @stdio.stderr.write("error: " + message + "\n") catch {
    _ => ()
  }
  process_exit(code)
}

///|
async fn write_output(content : String, path : String?) -> Unit {
  match path {
    Some(path) => @fs.write_file(path, content, create_mode=CreateOrTruncate)
    None => @stdio.stdout.write(content)
  }
}

///|
async fn protect_inputs(path : String, options : CliOptions) -> Unit {
  let destination = @fs.realpath(path) catch { _ => return }
  for source in [options.study, options.input] {
    if source is Some(source) {
      let original = @fs.realpath(source)
      if destination.to_lower() == original.to_lower() {
        die("Output must not overwrite a source study or CSV file.")
      }
    }
  }
}

///|
fn validation_text(
  diagnostics : Array[@lib.Diagnostic],
  issues : Array[@lib.InputIssue],
  count : Int,
) -> String {
  let out = StringBuilder()
  out.write_string(
    "Visits: \{count}; parse issues: \{diagnostics.length()}; structural issues: \{issues.length()}\n",
  )
  for d in diagnostics {
    let location = match (d.line, d.column) {
      (Some(line), Some(column)) => "line \{line}, column \{column}: "
      _ => ""
    }
    out.write_string(
      "- " +
      d.code +
      ": " +
      location +
      d.field.unwrap_or("") +
      " " +
      d.message +
      "\n",
    )
  }
  for i in issues {
    out.write_string(
      "- " +
      i.code.code() +
      ": " +
      i.visit_id.unwrap_or("") +
      " " +
      i.lesion_id.unwrap_or("") +
      " " +
      i.message +
      "\n",
    )
  }
  out.to_string()
}

///|
async fn run_cli(options : CliOptions) -> Unit {
  let diagnostics = []
  let mut study : @lib.Study? = None
  let mut visits : Array[@lib.Visit] = []
  match (options.study, options.input) {
    (Some(study_path), Some(input_path)) => {
      let profile = @fs.read_file(study_path).text()
      let csv = @fs.read_file(input_path).text()
      match @lib.parse_study_json(profile) {
        Ok(value) => study = Some(value)
        Err(errors) => diagnostics.append(errors)
      }
      match @lib.parse_followup_csv(csv) {
        Ok(value) => visits = value
        Err(errors) => diagnostics.append(errors)
      }
    }
    _ =>
      match
        @scenarios.build_scenario(options.scenario.unwrap_or("nadir-boundary")) {
        Ok((value, track)) => {
          study = Some(value)
          visits = track
        }
        Err(message) => {
          die(message)
          return
        }
      }
  }
  let issues = match study {
    Some(study) => @lib.validate_track(study, visits)
    None => []
  }
  if options.output is Some(path) {
    protect_inputs(path, options)
  }
  let valid = diagnostics.is_empty() && issues.is_empty()
  if options.check_input || !valid {
    let report = if options.format == "json" {
      @lib.render_validation_json(diagnostics, issues, visits.length())
    } else {
      validation_text(diagnostics, issues, visits.length())
    }
    if options.check_input || options.format == "json" {
      write_output(report, options.output)
    } else {
      @stdio.stderr.write(report)
    }
    if !valid {
      process_exit(2)
    }
    return
  }
  guard study is Some(study) else {
    die("Study profile is unavailable.")
    return
  }
  let trajectory = match @lib.replay_track(study, visits) {
    Ok(value) => value
    Err(_) => {
      die("Track validation failed.")
      return
    }
  }
  if options.bundle is Some(directory) {
    @fs.mkdir(directory, recursive=true) catch {
      error =>
        match @fs.kind(directory) {
          Directory => ()
          _ => raise error
        }
    }
    let artifacts = [
      ("report.html", @lib.render_audit_html(trajectory)),
      ("audit.json", @lib.render_audit_json(trajectory)),
      ("audit.csv", @lib.render_audit_csv(trajectory)),
      ("chart.svg", @lib.render_trajectory_svg(trajectory)),
      ("manifest.json", @lib.render_audit_manifest(trajectory)),
    ]
    for (name, _) in artifacts {
      protect_inputs(directory + "/" + name, options)
    }
    for (name, content) in artifacts {
      @fs.write_file(
        directory + "/" + name,
        content,
        create_mode=CreateOrTruncate,
      )
    }
    @stdio.stdout.write("Review bundle written to " + directory + "\n")
    return
  }
  let content = match options.format {
    "json" => @lib.render_audit_json(trajectory)
    "csv" => @lib.render_audit_csv(trajectory)
    "svg" => @lib.render_trajectory_svg(trajectory)
    "html" => @lib.render_audit_html(trajectory)
    _ => @lib.render_audit_markdown(trajectory)
  }
  write_output(content, options.output)
}

///|
async fn main {
  let argv = @env.args()
  let args = if argv.is_empty() { [] } else { argv[1:].to_owned() }
  if args.contains("--help") || args.contains("-h") {
    @stdio.stdout.write(command().render_help())
    return
  }
  if args == ["--version"] {
    @stdio.stdout.write("lesion-followup 0.1.0\n")
    return
  }
  let options = match parse_args(args) {
    Ok(value) => value
    Err(message) => {
      die(message)
      return
    }
  }
  run_cli(options) catch {
    error => die("I/O operation failed: " + error.to_string(), code=1)
  }
}
