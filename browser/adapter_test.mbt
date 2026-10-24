///|
fn inputs() -> (String, String) {
  let files = @lib.input_template_files("multi").unwrap()
  (files[0].1, files[1].1)
}

///|
fn call(
  action : String,
  study : String,
  csv : String,
  format? : String = "json",
) -> Json raise {
  let request : Json = {
    "schema_version": 1,
    "action": action,
    "study_json": study,
    "followup_csv": csv,
    "format": format,
  }
  @json.parse(@browser.evaluate(request.stringify()))
}

///|
test "strict versioned request errors never contain partial results" {
  for
    (request, code, field) in [
      ("{", "request_json", "$"),
      ("[]", "request_schema", "$"),
      ("{}", "request_version", "$.schema_version"),
      ("{\"schema_version\":2}", "request_version", "$.schema_version"),
      ("{\"schema_version\":1,\"action\":false}", "request_schema", "$.action"),
      (
        "{\"schema_version\":1,\"action\":\"edit\"}", "request_action", "$.action",
      ),
      (
        "{\"schema_version\":1,\"action\":\"template\",\"language\":\"zh\"}", "request_language",
        "$.language",
      ),
      (
        "{\"schema_version\":1,\"action\":\"template\",\"template\":\"other\"}",
        "request_template", "$.template",
      ),
      (
        "{\"schema_version\":1,\"action\":\"template\",\"format\":\"json\"}", "request_schema",
        "$.format",
      ),
      (
        "{\"schema_version\":1,\"action\":\"preflight\",\"format\":\"html\"}", "request_format",
        "$.format",
      ),
      (
        "{\"schema_version\":1,\"action\":\"review\"}", "request_schema", "$.study_json",
      ),
    ] {
    let result = @json.parse(@browser.evaluate(request))
    assert_true(
      result
      is {
        "schema_version": Number(1.0, ..),
        "scope": String("target_lesions_only"),
        "ok": False,
        "error_kind": String("request"),
        "action": Null,
        "preflight": Null,
        "result": Null,
        ..
      },
    )
    guard result
      is {
        "diagnostics": Array(
          [{ "code": String(actual), "field": String(path), .. }]
        ),
        ..
      } else {
      fail("missing request diagnostic")
    }
    assert_eq(actual, code)
    assert_eq(path, field)
  }
}

///|
test "parse and structural input errors retain preflight locations" {
  let (study, csv) = inputs()
  for
    (profile, followup) in [
      ("{", "bad header\n"),
      (study, csv.replace(old="20.0,", new="20.01,")),
      (study.replace(old="30.0", new="9.9"), csv),
    ] {
    let quality = @json.parse(
      @lib.render_preflight_json(@lib.preflight_inputs(profile, followup)),
    )
    let response = call("review", profile, followup)
    assert_true(
      response
      is {
        "ok": False,
        "error_kind": String("input"),
        "result": Null,
        "diagnostics": Array([]),
        ..
      },
    )
    guard response is { "preflight": actual, .. } else {
      fail("missing preflight")
    }
    assert_eq(actual, quality)
  }
}

///|
test "valid review-required observations remain successful NE" {
  let (study, _) = inputs()
  let csv = "visit_id,date,technique_id,lesion_id,state,diameter_mm,note\n" +
    "v1,2026-01-02,changed,N1,too_small,,\n"
  let response = call("review", study, csv)
  assert_true(
    response
    is {
      "ok": True,
      "error_kind": Null,
      "preflight": { "valid": True, "review_hints": Array([_, _, _]), .. },
      ..
    },
  )
  guard response is { "result": { "content": String(content), .. }, .. } else {
    fail("missing audit")
  }
  assert_true(
    @json.parse(content)
    is {
      "assessments": Array(
        [{ "target_response": String("NE"), "sum_mm": Null, .. }]
      ),
      ..
    },
  )
}

///|
test "all report formats use the supported facade renderers" {
  let (study_text, csv) = inputs()
  let trajectory = @lib.replay_track(
    @lib.parse_study_json(study_text).unwrap(),
    @lib.parse_followup_csv(csv).unwrap(),
  ).unwrap()
  for
    (format, expected) in [
      ("json", @lib.render_audit_json(trajectory)),
      ("csv", @lib.render_audit_csv(trajectory)),
      ("markdown", @lib.render_audit_markdown(trajectory)),
      ("svg", @lib.render_trajectory_svg(trajectory)),
      ("html", @lib.render_audit_html(trajectory)),
    ] {
    let response = call("review", study_text, csv, format~)
    guard response
      is { "ok": True, "result": { "content": String(actual), .. }, .. } else {
      fail("missing report")
    }
    assert_eq(actual, expected)
  }
}

///|
test "template defaults round trip with Unicode instructions" {
  let request : Json = {
    "schema_version": 1,
    "action": "template",
    "language": "zh-CN",
  }
  let response = @json.parse(@browser.evaluate(request.stringify()))
  guard response
    is {
      "ok": True,
      "result": {
        "files": Array(
          [
            { "name": String("study.json"), "content": String(study), .. },
            { "name": String("followup.csv"), "content": String(csv), .. },
            { "name": String("README.md"), "content": String(instructions), .. },
          ]
        ),
        ..
      },
      ..
    } else {
    fail("missing template")
  }
  assert_true(instructions.contains("合成靶病灶"))
  assert_true(call("review", study, csv) is { "ok": True, .. })
}

///|
test "preflight does not produce categories and requests retain no state" {
  let (study, csv) = inputs()
  let response = call("preflight", study, csv)
  assert_true(
    response is { "ok": True, "result": { "format": String("json"), .. }, .. },
  )
  guard response is { "result": { "content": String(content), .. }, .. } else {
    fail("missing preflight text")
  }
  assert_eq(
    content,
    @lib.render_preflight_json(@lib.preflight_inputs(study, csv)),
  )
  let before = call("review", study, csv)
  ignore(call("review", study, "invalid\n"))
  assert_eq(call("review", study, csv), before)
}
