///|
extern "c" fn process_exit(code : Int) -> Unit = "exit"

///|
async fn die(
  message : String,
  code? : Int = 2,
  language? : @lib.ReportLanguage = English,
) -> Unit {
  @stdio.stderr.write(ui(language, "error: ", "错误：") + message + "\n") catch {
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
  for
    source in [
      options.study,
      options.input,
      options.compare_study,
      options.compare_input,
      options.batch,
    ] {
    if source is Some(source) {
      let original = @fs.realpath(source)
      if destination.to_lower() == original.to_lower() {
        die(
          ui(
            options.language,
            "Output must not overwrite a source study or CSV file.",
            "输出不能覆盖原始研究配置或 CSV 文件。",
          ),
          language=options.language,
        )
      }
    }
  }
}

///|
async fn initialize_inputs(options : CliOptions, directory : String) -> Unit {
  let exists = try {
    ignore(@fs.kind(directory, follow_symlink=false))
    true
  } catch {
    _ => false
  }
  if exists {
    die(
      ui(
        options.language,
        "Initialization requires a NEW directory; existing paths are never overwritten.",
        "初始化必须使用新目录；已有路径不会被覆盖。",
      ),
      language=options.language,
    )
    return
  }
  let files = match
    @lib.input_template_files(options.template, language=options.language) {
    Ok(files) => files
    Err(message) => {
      die(message, language=options.language)
      return
    }
  }
  @fs.mkdir(directory)
  for (name, content) in files {
    @fs.write_file(directory + "/" + name, content, create_mode=CreateNew)
  }
  @stdio.stdout.write(
    ui(
      options.language,
      "Synthetic inputs created in ",
      "配套合成输入已生成：",
    ) +
    directory +
    "\n",
  )
}

///|
async fn run_cli(options : CliOptions) -> Unit {
  if options.verify_bundle_path is Some(directory) {
    verify_directory(directory, options)
    return
  }
  if options.batch is Some(path) {
    run_batch(path, options)
    return
  }
  if options.init_example is Some(directory) {
    initialize_inputs(options, directory)
    return
  }
  let mut raw_inputs : Array[(String, Bytes)] = []
  let mut study : @lib.Study? = None
  let mut visits : Array[@lib.Visit] = []
  let preflight = match (options.study, options.input) {
    (Some(study_path), Some(input_path)) => {
      let loaded = load_inputs(study_path, input_path)
      study = loaded.study
      visits = loaded.visits
      raw_inputs = loaded.raw_inputs
      loaded.preflight
    }
    _ =>
      match
        @scenarios.build_scenario(options.scenario.unwrap_or("nadir-boundary")) {
        Ok((value, track)) => {
          study = Some(value)
          visits = track
          @lib.preflight_track(value, track)
        }
        Err(message) => {
          die(
            ui(
              options.language,
              message,
              "合成演示名称无效：" + message,
            ),
            language=options.language,
          )
          return
        }
      }
  }
  if options.output is Some(path) {
    protect_inputs(path, options)
  }
  let valid = preflight.is_valid()
  if options.check_input || !valid {
    let report = if options.format == "json" {
      @lib.render_preflight_json(preflight)
    } else {
      @lib.render_preflight_markdown(preflight, language=options.language)
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
    die(
      ui(
        options.language,
        "Study profile is unavailable.",
        "研究配置不可用。",
      ),
      language=options.language,
    )
    return
  }
  let trajectory = match @lib.replay_track(study, visits) {
    Ok(value) => value
    Err(_) => {
      die(
        ui(
          options.language,
          "Track validation failed.",
          "随访结构校验失败。",
        ),
        language=options.language,
      )
      return
    }
  }
  if options.compare_study is Some(old_study) &&
    options.compare_input is Some(old_input) {
    run_revision(old_study, old_input, trajectory, options)
    return
  }
  if options.bundle is Some(directory) {
    write_review_bundle(directory, trajectory, raw_inputs, options)
    @stdio.stdout.write(
      ui(
        options.language,
        "Review bundle written to ",
        "复核报告包已写入：",
      ) +
      directory +
      "\n",
    )
    return
  }
  let content = match options.format {
    "json" => @lib.render_audit_json(trajectory)
    "csv" => @lib.render_audit_csv(trajectory)
    "svg" => @lib.render_trajectory_svg_in(trajectory, options.language)
    "html" => @lib.render_audit_html_in(trajectory, options.language)
    _ => @lib.render_audit_markdown_in(trajectory, options.language)
  }
  write_output(content, options.output)
}

///|
async fn main {
  let argv = @env.args()
  let args = if argv.is_empty() { [] } else { argv[1:].to_owned() }
  if args.contains("--help") || args.contains("-h") {
    @stdio.stdout.write(command(requested_language(args)).render_help())
    return
  }
  if args == ["--version"] {
    @stdio.stdout.write("lesion-followup 0.1.0\n")
    return
  }
  let options = match parse_args(args) {
    Ok(value) => value
    Err(message) => {
      die(
        ui(
          requested_language(args),
          message,
          "命令行参数不正确：" + message,
        ),
        language=requested_language(args),
      )
      return
    }
  }
  run_cli(options) catch {
    error =>
      die(
        ui(
          options.language,
          "I/O operation failed: ",
          "文件读写操作失败：",
        ) +
        error.to_string(),
        code=1,
        language=options.language,
      )
  }
}
