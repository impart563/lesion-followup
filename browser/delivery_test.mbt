///|
fn bundle_request() -> Json {
  let files = @lib.input_template_files("multi").unwrap()
  {
    "schema_version": 1,
    "action": "bundle",
    "study_json": files[0].1,
    "followup_csv": files[1].1,
  }
}

///|
test "browser bundles roundtrip through the same core verifier" {
  let response = @json.parse(@browser.evaluate(bundle_request().stringify()))
  guard response is { "ok": True, "result": { "files": Array(files), .. }, .. } else {
    fail("bundle missing")
  }
  assert_eq(files.length(), 5)
  let artifacts : Array[Json] = []
  let mut manifest = ""
  for file in files {
    guard file is { "name": String(name), "content": String(content), .. } else {
      fail("file missing")
    }
    if name == "manifest.json" {
      manifest = content
    } else {
      artifacts.push(file)
    }
  }
  let request : Json = {
    "schema_version": 1,
    "action": "verify-bundle",
    "manifest": manifest,
    "files": artifacts.to_json(),
  }
  assert_true(
    @json.parse(@browser.evaluate(request.stringify()))
    is { "ok": True, "diagnostics": Array([]), .. },
  )
  artifacts[0] = { "name": "report.html", "content": "changed" }
  let tampered : Json = {
    "schema_version": 1,
    "action": "verify-bundle",
    "manifest": manifest,
    "files": artifacts.to_json(),
  }
  assert_true(
    @json.parse(@browser.evaluate(tampered.stringify()))
    is {
      "ok": False,
      "error_kind": String("bundle"),
      "result": Null,
      "diagnostics": Array([_, ..]),
      ..
    },
  )
}

///|
test "bundle actions reject inappropriate fields and invalid inputs" {
  for
    text in [
      "{\"schema_version\":1,\"action\":\"bundle\",\"format\":\"json\"}", "{\"schema_version\":1,\"action\":\"verify-bundle\",\"manifest\":\"{}\",\"files\":[{\"name\":\"audit.json\",\"content\":\"{}\",\"extra\":1}]}",
      "{\"schema_version\":1,\"action\":\"verify-bundle\",\"manifest\":\"{}\",\"files\":null}",
    ] {
    assert_true(
      @json.parse(@browser.evaluate(text))
      is { "ok": False, "error_kind": String("request"), .. },
    )
  }
  let request : Json = {
    "schema_version": 1,
    "action": "bundle",
    "study_json": "{}",
    "followup_csv": "",
  }
  assert_true(
    @json.parse(@browser.evaluate(request.stringify()))
    is { "ok": False, "error_kind": String("input"), "result": Null, .. },
  )
}

///|
test "batch index uses core escaping and portable unique identifiers" {
  let row : Json = {
    "id": "case-001",
    "status": "success",
    "message": "<script>",
    "visit_count": 2,
    "review_hint_count": 1,
  }
  let request : Json = {
    "schema_version": 1,
    "action": "batch-index",
    "cases": [row],
  }
  let expected : Array[@lib.BatchResult] = [
    {
      id: "case-001",
      status: "success",
      message: "<script>",
      visit_count: 2,
      review_hint_count: 1,
      report_path: Some("case-001/report.html"),
    },
  ]
  guard @json.parse(@browser.evaluate(request.stringify()))
    is {
      "ok": True,
      "result": {
        "files": Array(
          [{ "content": String(index), .. }, { "content": String(html), .. }]
        ),
        ..
      },
      ..
    } else {
    fail("index missing")
  }
  assert_eq(index, @lib.render_batch_index_json(expected))
  assert_eq(html, @lib.render_batch_index_html(expected))
  for
    cases in [
      [row, row],
      [
        {
          "id": "../bad",
          "status": "success",
          "message": "",
          "visit_count": 0,
          "review_hint_count": 0,
        },
      ],
      [
        {
          "id": "CON",
          "status": "success",
          "message": "",
          "visit_count": 0,
          "review_hint_count": 0,
        },
      ],
      [
        {
          "id": "case",
          "status": "pending",
          "message": "",
          "visit_count": 0,
          "review_hint_count": 0,
        },
      ],
      [
        {
          "id": "case",
          "status": "success",
          "message": "",
          "visit_count": 0.5,
          "review_hint_count": 0,
        },
      ],
      [
        {
          "id": "case",
          "status": "success",
          "message": "",
          "visit_count": -1,
          "review_hint_count": 0,
        },
      ],
      [],
    ] {
    let invalid : Json = {
      "schema_version": 1,
      "action": "batch-index",
      "cases": cases.to_json(),
    }
    assert_true(
      @json.parse(@browser.evaluate(invalid.stringify()))
      is { "ok": False, "error_kind": String("request"), .. },
    )
  }
}
