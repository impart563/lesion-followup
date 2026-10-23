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
  init_example : String?
  template : String
  language : @lib.ReportLanguage
}

///|
fn ui(
  language : @lib.ReportLanguage,
  english : String,
  chinese : String,
) -> String {
  if language == SimplifiedChinese {
    chinese
  } else {
    english
  }
}

///|
fn requested_language(args : Array[String]) -> @lib.ReportLanguage {
  for i, arg in args {
    if arg == "--lang=zh-CN" ||
      (arg == "--lang" && i + 1 < args.length() && args[i + 1] == "zh-CN") {
      return SimplifiedChinese
    }
  }
  English
}

///|
fn command(language : @lib.ReportLanguage) -> @argparse.Command {
  @argparse.Command(
    "lesion-followup",
    about=ui(
      language, "Review manually measured CT target lesions; target categories only.",
      "复核人工测量的 CT 靶病灶；仅提供靶病灶分类。",
    ),
    flags=[
      @argparse.FlagArg(
        "check-input",
        action=SetTrue,
        about=ui(
          language, "check input errors and review hints without response categories",
          "检查输入错误及人工复核提示，不输出疗效分类",
        ),
      ),
    ],
    options=[
      @argparse.OptionArg(
        "init-example",
        about=ui(
          language, "create matched synthetic inputs in a NEW directory", "在新目录生成配套合成输入，已有目录不会覆盖",
        ),
      ),
      @argparse.OptionArg(
        "template",
        about=ui(
          language, "single (default) or multi; requires --init-example", "single 单靶（默认）或 multi 多靶，须与 --init-example 配合",
        ),
      ),
      @argparse.OptionArg(
        "lang",
        about=ui(
          language, "en (default) or zh-CN; machine formats stay unchanged", "en（默认）或 zh-CN；机器格式保持不变",
        ),
      ),
      @argparse.OptionArg(
        "scenario",
        about=ui(
          language, "synthetic demo: nadir-boundary, node-resolution, missing-visit",
          "合成演示：nadir-boundary、node-resolution、missing-visit",
        ),
      ),
      @argparse.OptionArg(
        "study",
        about=ui(
          language, "versioned study JSON profile; requires --input", "研究配置 JSON，须与 --input 配合",
        ),
      ),
      @argparse.OptionArg(
        "input",
        about=ui(
          language, "long-form follow-up CSV; requires --study", "长表随访 CSV，须与 --study 配合",
        ),
      ),
      @argparse.OptionArg(
        "format",
        about=ui(
          language, "markdown (default), json, csv, svg or html", "markdown（默认）、json、csv、svg 或 html",
        ),
      ),
      @argparse.OptionArg(
        "output",
        about=ui(
          language, "write selected format to a file; parent must exist", "写入文件；父目录须已存在",
        ),
      ),
      @argparse.OptionArg(
        "bundle",
        about=ui(
          language, "write report.html, audit.json/csv, chart.svg and manifest.json",
          "生成 report.html、audit.json/csv、chart.svg 及 manifest.json",
        ),
      ),
    ],
  )
}

///|
fn parse_args(args : Array[String]) -> Result[CliOptions, String] {
  let matches = command(requested_language(args)).parse(argv=args, env=Map([])) catch {
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
  let init_example = value("init-example")
  let template = value("template").unwrap_or("single")
  let language : @lib.ReportLanguage = match value("lang").unwrap_or("en") {
    "en" => English
    "zh-CN" => SimplifiedChinese
    _ => return Err("--lang must be en or zh-CN.")
  }
  if init_example is Some(_) {
    if study is Some(_) ||
      input is Some(_) ||
      scenario is Some(_) ||
      output is Some(_) ||
      bundle is Some(_) ||
      check_input ||
      value("format") is Some(_) {
      return Err("--init-example only accepts --template and --lang.")
    }
    if template != "single" && template != "multi" {
      return Err("--template must be single or multi.")
    }
  } else if value("template") is Some(_) {
    return Err("--template requires --init-example.")
  }
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
  Ok({
    scenario,
    study,
    input,
    format,
    output,
    bundle,
    check_input,
    init_example,
    template,
    language,
  })
}

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
  for source in [options.study, options.input] {
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
  if options.init_example is Some(directory) {
    initialize_inputs(options, directory)
    return
  }
  let mut study : @lib.Study? = None
  let mut visits : Array[@lib.Visit] = []
  let preflight = match (options.study, options.input) {
    (Some(study_path), Some(input_path)) => {
      let profile = @fs.read_file(study_path).text()
      let csv = @fs.read_file(input_path).text()
      let report = @lib.preflight_inputs(profile, csv)
      if @lib.parse_study_json(profile) is Ok(value) {
        study = Some(value)
      }
      if @lib.parse_followup_csv(csv) is Ok(value) {
        visits = value
      }
      report
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
  if options.bundle is Some(directory) {
    @fs.mkdir(directory, recursive=true) catch {
      error =>
        match @fs.kind(directory) {
          Directory => ()
          _ => raise error
        }
    }
    let artifacts = [
      ("report.html", @lib.render_audit_html_in(trajectory, options.language)),
      ("audit.json", @lib.render_audit_json(trajectory)),
      ("audit.csv", @lib.render_audit_csv(trajectory)),
      ("chart.svg", @lib.render_trajectory_svg_in(trajectory, options.language)),
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
