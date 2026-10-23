///|
test "CLI accepts input pair, default scenario and each report format" {
  assert_true(parse_args([]) is Ok(_))
  assert_true(parse_args(["--study", "s.json", "--input", "v.csv"]) is Ok(_))
  for format in ["json", "csv", "html", "svg", "markdown"] {
    assert_true(parse_args(["--format", format]) is Ok(_))
  }
}

///|
test "CLI rejects incompatible or incomplete modes" {
  for
    args in [
      ["--study", "s.json"],
      ["--input", "v.csv"],
      ["--study", "s.json", "--input", "v.csv", "--scenario", "nadir-boundary"],
      ["--bundle", "b", "--format", "html"],
      ["--bundle", "b", "--output", "r.html"],
      ["--bundle", "b", "--check-input"],
      ["--check-input", "--format", "svg"],
      ["--format", "unknown"],
      ["--unknown"],
      ["--output"],
      ["--lang", "invalid"],
      ["--template", "multi"],
      ["--init-example", "new", "--template", "invalid"],
      ["--init-example", "new", "--scenario", "missing-visit"],
      ["--init-example", "new", "--output", "report.html"],
      ["--init-example", "new", "--format", "markdown"],
      ["--init-example", "new", "--check-input"],
      ["--init-example", "new", "--bundle", "bundle"],
    ] {
    assert_true(parse_args(args) is Err(_))
  }
}

///|
test "CLI language and template modes are explicit and independent" {
  guard parse_args([
      "--init-example", "new", "--template", "multi", "--lang", "zh-CN",
    ])
    is Ok(options) else {
    fail("template mode rejected")
  }
  assert_eq(options.template, "multi")
  assert_true(options.language is SimplifiedChinese)
  assert_true(parse_args(["--lang", "en", "--format", "json"]) is Ok(_))
  assert_true(parse_args(["--lang", "zh-CN", "--check-input"]) is Ok(_))
  assert_true(requested_language(["--lang", "zh-CN"]) is SimplifiedChinese)
  assert_true(requested_language(["--lang=zh-CN"]) is SimplifiedChinese)
}
