///|
test "editor preserves raw cells including invalid clinical states for correction" {
  let (study, _) = inputs()
  let csv = "visit_id,date,technique_id,lesion_id,state,diameter_mm,note\r\n" +
    "v1,2026-01-02,ct-venous-5mm,T1,measured,20.01,\r\n" +
    "v1,2026-01-02,ct-venous-5mm,N1,not_evaluable,,\"复核, \"\"引号\"\"\r\n第二行🙂\"\r\n"
  let request : Json = {
    "schema_version": 1,
    "action": "editor",
    "study_json": study,
    "followup_csv": csv,
  }
  let response = @json.parse(@browser.evaluate(request.stringify()))
  assert_true(
    response
    is {
      "ok": True,
      "error_kind": Null,
      "preflight": { "valid": False, .. },
      ..
    },
  )
  guard response
    is { "result": { "rows": Array([Array(row1), Array(row2)]), .. }, .. } else {
    fail("missing editable cells")
  }
  assert_eq(row1[5], Json::string("20.01"))
  assert_eq(row2[6], Json::string("复核, \"引号\"\r\n第二行🙂"))
  assert_true(call("review", study, csv) is { "ok": False, "result": Null, .. })
}

///|
test "editor rejects unsafe input shapes and keeps strict per-action fields" {
  let (study, _) = inputs()
  for
    csv in [
      "bad\n", "visit_id,date,technique_id,lesion_id,state,diameter_mm,note\nv1\n",
      "visit_id,date,technique_id,lesion_id,state,diameter_mm,note\n\"open",
    ] {
    let request : Json = {
      "schema_version": 1,
      "action": "editor",
      "study_json": study,
      "followup_csv": csv,
    }
    assert_true(
      @json.parse(@browser.evaluate(request.stringify()))
      is { "ok": False, "error_kind": String("input"), "result": Null, .. },
    )
  }
  let extra : Json = {
    "schema_version": 1,
    "action": "editor",
    "study_json": study,
    "followup_csv": "",
    "format": "json",
  }
  assert_true(
    @json.parse(@browser.evaluate(extra.stringify()))
    is { "ok": False, "error_kind": String("request"), .. },
  )
}

///|
test "editor retains structurally invalid study values without clinical results" {
  let (study, csv) = inputs()
  let request : Json = {
    "schema_version": 1,
    "action": "editor",
    "study_json": study.replace(old="30.0", new="9.9"),
    "followup_csv": csv,
  }
  let response = @json.parse(@browser.evaluate(request.stringify()))
  assert_true(
    response
    is {
      "ok": True,
      "preflight": { "valid": False, .. },
      "result": {
        "study": {
          "targets": Array([{ "baseline_mm": String("9.9"), .. }, _]),
          ..
        },
        ..
      },
      ..
    },
  )
}
