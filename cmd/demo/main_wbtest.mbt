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
    ] {
    assert_true(parse_args(args) is Err(_))
  }
}
