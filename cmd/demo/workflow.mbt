///|
priv struct LoadedInputs {
  study : @lib.Study?
  visits : Array[@lib.Visit]
  preflight : @lib.PreflightReport
  raw_inputs : Array[(String, Bytes)]
}

///|
async fn load_inputs(study_path : String, input_path : String) -> LoadedInputs {
  let profile = @fs.read_file(study_path)
  let csv = @fs.read_file(input_path)
  let study_text = profile.text()
  let csv_text = csv.text()
  {
    study: match @lib.parse_study_json(study_text) {
      Ok(s) => Some(s)
      Err(_) => None
    },
    visits: match @lib.parse_followup_csv(csv_text) {
      Ok(v) => v
      Err(_) => []
    },
    preflight: @lib.preflight_inputs(study_text, csv_text),
    raw_inputs: [("study", profile.binary()), ("followup", csv.binary())],
  }
}

///|
fn loaded_trajectory(loaded : LoadedInputs) -> @lib.Trajectory? {
  if !loaded.preflight.is_valid() {
    return None
  }
  if loaded.study is Some(study) &&
    @lib.replay_track(study, loaded.visits) is Ok(t) {
    Some(t)
  } else {
    None
  }
}

///|
async fn run_revision(
  study_path : String,
  input_path : String,
  revised : @lib.Trajectory,
  options : CliOptions,
) -> Unit {
  let loaded = load_inputs(study_path, input_path)
  guard loaded_trajectory(loaded) is Some(original) else {
    let text = if options.format == "json" {
      @lib.render_preflight_json(loaded.preflight)
    } else {
      @lib.render_preflight_markdown(
        loaded.preflight,
        language=options.language,
      )
    }
    @stdio.stderr.write(text)
    process_exit(2)
    return
  }
  let comparison = match @lib.compare_tracks(original, revised) {
    Ok(value) => value
    Err(diagnostics) => {
      let text = @lib.render_validation_json(diagnostics, [], 0)
      if options.format == "json" {
        @stdio.stdout.write(text)
      } else {
        @stdio.stderr.write(text)
      }
      process_exit(2)
      return
    }
  }
  let text = match options.format {
    "json" => @lib.render_revision_json(comparison)
    "html" => @lib.render_revision_html(comparison, language=options.language)
    _ => @lib.render_revision_markdown(comparison, language=options.language)
  }
  write_output(text, options.output)
}

///|
async fn path_exists(path : String) -> Bool {
  try {
    ignore(@fs.kind(path, follow_symlink=false))
    true
  } catch {
    _ => false
  }
}

///|
async fn write_review_bundle(
  directory : String,
  trajectory : @lib.Trajectory,
  raw_inputs : Array[(String, Bytes)],
  options : CliOptions,
) -> Unit {
  if path_exists(directory) {
    if @fs.kind(directory, follow_symlink=false) != Directory {
      die(
        ui(
          options.language,
          "Bundle destination must be a regular directory, not a link.",
          "报告包目标须为普通目录，不能为链接。",
        ),
        language=options.language,
      )
      return
    }
  } else {
    @fs.mkdir(directory, recursive=true)
  }
  let artifacts = @lib.review_artifacts(trajectory, language=options.language)
  let manifest = @lib.render_bundle_manifest(
    trajectory,
    artifacts,
    language=options.language,
    raw_inputs~,
  )
  let files = artifacts.copy()
  files.push(("manifest.json", manifest))
  for (name, _) in files {
    let path = directory + "/" + name
    protect_inputs(path, options)
    if path_exists(path) && @fs.kind(path, follow_symlink=false) != Regular {
      die(
        ui(
          options.language,
          "Bundle artifacts must be regular files, not links.",
          "报告包文件须为普通文件，不能为链接。",
        ),
        language=options.language,
      )
      return
    }
  }
  for (name, text) in files {
    @fs.write_file(directory + "/" + name, text, create_mode=CreateOrTruncate)
  }
}

///|
async fn verify_directory(directory : String, options : CliOptions) -> Unit {
  let manifest_path = directory + "/manifest.json"
  if !path_exists(manifest_path) ||
    @fs.kind(manifest_path, follow_symlink=false) != Regular {
    die(
      ui(
        options.language,
        "Missing regular manifest.json file.",
        "缺少普通文件 manifest.json。",
      ),
      language=options.language,
    )
    return
  }
  let manifest = @fs.read_file(manifest_path).text()
  let files : Array[(String, Bytes)] = []
  for name in ["report.html", "audit.json", "audit.csv", "chart.svg"] {
    let path = directory + "/" + name
    if path_exists(path) && @fs.kind(path, follow_symlink=false) == Regular {
      files.push((name, @fs.read_file(path).binary()))
    }
  }
  let issues = @lib.verify_bundle(manifest, files)
  if options.format == "json" {
    @stdio.stdout.write(@lib.render_validation_json(issues, [], 0))
  } else if issues.is_empty() {
    @stdio.stdout.write(
      ui(
        options.language,
        "Bundle integrity verified.\n",
        "报告包完整性校验通过。\n",
      ),
    )
  } else {
    @stdio.stderr.write(@lib.render_validation_json(issues, [], 0))
  }
  if !issues.is_empty() {
    process_exit(2)
  }
}
