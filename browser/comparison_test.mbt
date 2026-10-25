///|
fn compare_request(
  study : String,
  before : String,
  after : String,
  format : String,
) -> Json {
  {
    "schema_version": 1,
    "action": "compare",
    "study_json": study,
    "followup_csv": after,
    "compare_study_json": study,
    "compare_followup_csv": before,
    "format": format,
  }
}

///|
test "browser comparison reuses the facade in all three formats" {
  let files = @lib.input_template_files("multi").unwrap()
  let study = files[0].1
  let before = files[1].1
  let after = before.replace(old="T1,measured,10.0,", new="T1,measured,9.0,")
  let profile = @lib.parse_study_json(study).unwrap()
  let revision = @lib.compare_tracks(
    @lib.replay_track(profile, @lib.parse_followup_csv(before).unwrap()).unwrap(),
    @lib.replay_track(profile, @lib.parse_followup_csv(after).unwrap()).unwrap(),
  ).unwrap()
  for
    (format, expected) in [
      ("json", @lib.render_revision_json(revision)),
      ("markdown", @lib.render_revision_markdown(revision)),
      ("html", @lib.render_revision_html(revision)),
    ] {
    let response = @json.parse(
      @browser.evaluate(
        compare_request(study, before, after, format).stringify(),
      ),
    )
    guard response
      is {
        "ok": True,
        "preflight": {
          "before": { "valid": True, .. },
          "after": { "valid": True, .. },
          ..
        },
        "result": { "content": String(actual), .. },
        ..
      } else {
      fail("comparison missing")
    }
    assert_eq(actual, expected)
  }
}

///|
test "both comparison sides keep independent located diagnostics" {
  let files = @lib.input_template_files("multi").unwrap()
  let request = compare_request(files[0].1, "bad header\n", files[1].1, "json")
  assert_true(
    @json.parse(@browser.evaluate(request.stringify()))
    is {
      "ok": False,
      "error_kind": String("input"),
      "result": Null,
      "preflight": {
        "before": { "valid": False, "diagnostics": Array([_, ..]), .. },
        "after": { "valid": True, .. },
        ..
      },
      ..
    },
  )
  let request = compare_request(files[0].1, files[1].1, "bad header\n", "json")
  assert_true(
    @json.parse(@browser.evaluate(request.stringify()))
    is {
      "ok": False,
      "preflight": {
        "before": { "valid": True, .. },
        "after": { "valid": False, .. },
        ..
      },
      "result": Null,
      ..
    },
  )
}

///|
test "different baselines cannot be compared and unknown fields are rejected" {
  let files = @lib.input_template_files("multi").unwrap()
  let request : Json = {
    "schema_version": 1,
    "action": "compare",
    "study_json": files[0].1,
    "followup_csv": files[1].1,
    "compare_study_json": files[0].1.replace(old="30.0", new="31.0"),
    "compare_followup_csv": files[1].1,
  }
  assert_true(
    @json.parse(@browser.evaluate(request.stringify()))
    is {
      "ok": False,
      "error_kind": String("comparison"),
      "result": Null,
      "diagnostics": Array([{ "code": String("revision_baseline"), .. }]),
      ..
    },
  )
  let invalid : Json = {
    "schema_version": 1,
    "action": "compare",
    "format": "svg",
  }
  assert_true(
    @json.parse(@browser.evaluate(invalid.stringify()))
    is { "error_kind": String("request"), .. },
  )
  let invalid : Json = {
    "schema_version": 1,
    "action": "review",
    "compare_study_json": "{}",
  }
  assert_true(
    @json.parse(@browser.evaluate(invalid.stringify()))
    is { "error_kind": String("request"), .. },
  )
}
