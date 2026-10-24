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
  compare_study : String?
  compare_input : String?
  verify_bundle_path : String?
  batch : String?
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
        "compare-study",
        about=ui(
          language, "original study profile; use --study/--input for the revised track",
          "修订前配置；--study/--input 提供修订后记录",
        ),
      ),
      @argparse.OptionArg(
        "compare-input",
        about=ui(
          language, "original CSV; requires --compare-study", "修订前 CSV；须与 --compare-study 配合",
        ),
      ),
      @argparse.OptionArg(
        "verify-bundle",
        about=ui(
          language, "verify a version-2 report bundle without modifying it", "只读校验第 2 版报告包",
        ),
      ),
      @argparse.OptionArg(
        "batch",
        about=ui(
          language, "batch manifest; requires --bundle NEW_DIRECTORY", "批量清单；须配合 --bundle 新目录",
        ),
      ),
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
  for key, values in matches.values {
    if values.length() != 1 {
      return Err("Option must appear exactly once: --" + key)
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
  let compare_study = value("compare-study")
  let compare_input = value("compare-input")
  let verify_bundle_path = value("verify-bundle")
  let batch = value("batch")
  if (compare_study is Some(_)) != (compare_input is Some(_)) {
    return Err("--compare-study and --compare-input must be supplied together.")
  }
  if verify_bundle_path is Some(_) {
    if study is Some(_) ||
      input is Some(_) ||
      scenario is Some(_) ||
      bundle is Some(_) ||
      output is Some(_) ||
      check_input ||
      init_example is Some(_) ||
      value("template") is Some(_) ||
      compare_study is Some(_) ||
      batch is Some(_) ||
      !["json", "markdown"].contains(format) {
      return Err(
        "--verify-bundle only accepts --lang and --format json|markdown.",
      )
    }
  }
  if batch is Some(_) {
    if bundle is None ||
      study is Some(_) ||
      input is Some(_) ||
      scenario is Some(_) ||
      output is Some(_) ||
      check_input ||
      init_example is Some(_) ||
      value("template") is Some(_) ||
      compare_study is Some(_) ||
      value("format") is Some(_) {
      return Err(
        "--batch requires --bundle NEW_DIRECTORY and only accepts --lang.",
      )
    }
  }
  if compare_study is Some(_) &&
    (
      study is None ||
      input is None ||
      scenario is Some(_) ||
      bundle is Some(_) ||
      check_input ||
      init_example is Some(_) ||
      !["json", "markdown", "html"].contains(format)
    ) {
    return Err(
      "Revision comparison requires --study and --input and supports json, markdown or html.",
    )
  }
  let language : @lib.ReportLanguage = match value("lang").unwrap_or("en") {
    "en" => English
    "zh-CN" => SimplifiedChinese
    _ => return Err("--lang must be en or zh-CN.")
  }
  if init_example is Some(_) {
    if compare_study is Some(_) ||
      verify_bundle_path is Some(_) ||
      batch is Some(_) ||
      study is Some(_) ||
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
    compare_study,
    compare_input,
    verify_bundle_path,
    batch,
  })
}
