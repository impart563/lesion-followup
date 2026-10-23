///|
test "decimal input is exact, bounded and never silently rounded" {
  for (input, value) in [("0", 0), ("0.0", 0), ("19.9", 199), ("1000.0", 10000)] {
    assert_eq(@io.parse_diameter_mm(input), Ok(value))
  }
  for
    input in [
      "", "-1", "+1", " 1", "1 ", ".1", "1.", "1.01", "1e2", "1000.1", "999999999999999999999999",
      "NaN",
    ] {
    assert_true(@io.parse_diameter_mm(input) is Err(_))
  }
  assert_eq(@io.format_diameter_mm(199), "19.9")
  assert_eq(@io.format_diameter_mm(-199), "-19.9")
}

///|
fn profile() -> String {
  (
    #|{"schema_version":1,"study_id":"test","baseline_date":"2026-01-01","technique_id":"ct","slice_thickness_mm":"5.0","targets":[{"id":"T1","organ":"liver","kind":"non_nodal","baseline_mm":"20.0"}]}
  )
}

///|
test "study schema accepts exact decimal strings and rejects unknown fields" {
  guard @io.parse_study_json(profile()) is Ok(study) else {
    fail("valid profile rejected")
  }
  assert_eq(study.targets[0].baseline_tenths_mm, 200)
  for
    text in [
      profile().replace(old="\"20.0\"", new="20.0"),
      profile().replace(old="\"20.0\"", new="\"20.01\""),
      profile().replace(old="\"schema_version\":1", new="\"schema_version\":2"),
      profile().replace(old="\"organ\":", new="\"unknown\":"),
    ] {
    assert_true(@io.parse_study_json(text) is Err(_))
  }
  assert_true(@io.parse_study_json("{") is Err(_))
}

///|
fn header() -> String {
  "visit_id,date,technique_id,lesion_id,state,diameter_mm,note\n"
}

///|
test "CSV preserves decimals and contiguous visit order" {
  let text = header() +
    "v1,2026-01-02,ct,T1,measured,20.0,\nv1,2026-01-02,ct,T2,absent,,\nv2,2026-01-03,ct,T1,missing,,\n"
  guard @io.parse_followup_csv(text) is Ok(visits) else { fail("CSV rejected") }
  assert_eq(visits.length(), 2)
  assert_eq(visits[0].measurements.length(), 2)
  assert_true(visits[0].measurements[0].observation is Measured(200))
  assert_true(visits[0].measurements[1].observation is Absent)
  assert_true(visits[1].measurements[0].observation is Missing)
}

///|
test "quoted unicode multiline notes and CRLF preserve physical diagnostics" {
  let text = "\u{feff}" +
    header().replace(old="\n", new="\r\n") +
    "v1,2026-01-02,ct,T1,not_evaluable,,\"融合,需\"\"复核\"\"\r\n第二行\"\r\n" +
    "v2,2026-01-03,ct,T1,measured,2.01,\r\n"
  guard @io.parse_followup_csv(text) is Err(errors) else {
    fail("precision error accepted")
  }
  assert_eq(errors.length(), 1)
  assert_eq(errors[0].line, Some(4))
  assert_eq(errors[0].field, Some("diameter_mm"))
  assert_true(errors[0].column is Some(_))
  let valid = text.replace(old="2.01", new="2.0")
  guard @io.parse_followup_csv(valid) is Ok(visits) else {
    fail("quoted input rejected")
  }
  assert_true(
    visits[0].measurements[0].observation
    is NotEvaluable("融合,需\"复核\"\r\n第二行"),
  )
}

///|
test "CSV rejects malformed quoting, wrong header and wrong column counts" {
  for
    text in [
      "wrong\n",
      header() + "v1,2026-01-02,ct,T1,missing,\n",
      header() + "v1,2026-01-02,ct,T1,not_evaluable,,\"unclosed",
      header() + "v1,2026-01-02,ct,T1,not_evaluable,,\"closed\"tail\n",
      header() + "v\"1,2026-01-02,ct,T1,missing,,\n",
    ] {
    assert_true(@io.parse_followup_csv(text) is Err(_))
  }
}

///|
test "CSV state and metadata errors cannot yield a partial trajectory" {
  for
    row in [
      "v1,2026-01-02,ct,T1,absent,0,", "v1,2026-01-02,ct,T1,not_evaluable,,", "v1,2026-01-02,ct,T1,measured,20,note",
      "v1,2026-01-02,ct,T1,unknown,,",
    ] {
    assert_true(@io.parse_followup_csv(header() + row) is Err(_))
  }
  assert_true(
    @io.parse_followup_csv(
      header() + "v1,2026-01-02,ct,T1,absent,,\nv1,2026-01-03,ct,T2,absent,,",
    )
    is Err(_),
  )
  assert_true(
    @io.parse_followup_csv(
      header() +
      "v1,2026-01-02,ct,T1,absent,,\nv2,2026-01-03,ct,T1,absent,,\nv1,2026-01-02,ct,T2,absent,,",
    )
    is Err(_),
  )
}
