///|
fn replay_files(profile : String, csv : String) -> @evidence.Trajectory raise {
  guard @io.parse_study_json(profile) is Ok(study) &&
    @io.parse_followup_csv(csv) is Ok(visits) &&
    @replay.replay_track(study, visits) is Ok(track) else {
    fail("fixture invalid")
  }
  track
}

///|
test "SHA-256 matches independent short, padding-boundary and binary vectors" {
  let binary : Bytes = [0, 255, 128, 13, 10]
  assert_eq(
    @io.sha256_hex(binary),
    "6171db06a1c89b1ff8ab77e479d5df976ccd88a7b63567b4b18f413649e12ff3",
  )
  assert_eq(
    @io.sha256_hex(b""),
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  )
  assert_eq(
    @io.sha256_hex(b"abc"),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
  assert_eq(
    @io.sha256_hex(b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
    "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
  )
}

///|
test "exact checks distinguish relative-only growth from dual PD boundary" {
  let (profile, csv) = template_pair("single")
  let t = replay_files(profile, csv)
  let relative_only = @replay.explain_assessment(t.assessments[2])
  let relative = relative_only.filter(c => c.code == "pd_relative_5S_ge_6N")[0]
  let absolute = relative_only.filter(c => {
      c.code == "pd_absolute_S_minus_N_ge_50"
    })[0]
  assert_eq(relative.left, Some(700))
  assert_eq(relative.right, 600)
  assert_eq(relative.passed, Some(true))
  assert_eq(absolute.left, Some(40))
  assert_eq(absolute.passed, Some(false))
  let exact = @replay.explain_assessment(t.assessments[3])
  assert_eq(
    exact.filter(c => c.code == "pd_absolute_S_minus_N_ge_50")[0].left,
    Some(50),
  )
  assert_true(!exact.filter(c => c.code == "pr_10S_le_7B")[0].active)
  let incomplete = example_trajectory().assessments[1]
  let checks = @replay.explain_assessment(incomplete)
  assert_true(!checks.filter(c => c.code == "pr_10S_le_7B")[0].active)
  assert_eq(checks.filter(c => c.code == "pd_relative_5S_ge_6N")[0].left, None)
}

///|
test "revision identifies one measurement and its downstream nadir and category effects" {
  let (profile, csv) = template_pair("single")
  let before = replay_files(profile, csv)
  let after = replay_files(
    profile,
    csv.replace(old="T1,measured,10.0", new="T1,measured,9.0"),
  )
  guard @io.compare_tracks(before, after) is Ok(diff) else {
    fail("comparison rejected")
  }
  assert_eq(diff.changes.length(), 1)
  assert_eq(diff.changes[0].visit_id, "week-4")
  assert_eq(diff.changes[0].lesion_id, Some("T1"))
  assert_eq(diff.impacts.length(), 3)
  assert_eq(diff.impacts[1].after.map(a => a.response), Some(PD))
  assert_eq(diff.impacts[1].before.map(a => a.response), Some(PR))
  assert_eq(diff.impacts[2].after.map(a => a.response), Some(NE))
  guard @io.compare_tracks(before, before) is Ok(empty) else {
    fail("same input")
  }
  assert_true(empty.changes.is_empty() && empty.impacts.is_empty())
  let incompatible = replay_files(profile.replace(old="30.0", new="31.0"), csv)
  assert_true(@io.compare_tracks(before, incompatible) is Err(_))
}

///|
test "revision additions and removals preserve identity rather than shift array positions" {
  let (profile, csv) = template_pair("single")
  let original = replay_files(profile, csv)
  guard @replay.replay_track(original.study, original.visits[1:].to_owned())
    is Ok(deleted) else {
    fail("deletion")
  }
  guard @io.compare_tracks(original, deleted) is Ok(diff) else { fail("diff") }
  assert_true(
    diff.changes.any(c => {
      c.visit_id == "week-2" && c.field == "visit" && c.after is None
    }),
  )
  guard @io.compare_tracks(deleted, original) is Ok(added) else { fail("diff") }
  assert_true(
    added.changes.any(c => c.visit_id == "week-2" && c.before is None),
  )
}

///|
test "bundle checks distinguish missing, modified and inconsistent metadata" {
  let t = example_trajectory()
  let artifacts = @io.review_artifacts(t)
  let manifest = @io.render_bundle_manifest(t, artifacts)
  let bytes = artifacts.map(p => (p.0, @utf8.encode(p.1)))
  assert_true(@io.verify_bundle(manifest, bytes).is_empty())
  let modified = bytes.copy()
  modified[0] = ("report.html", b"changed")
  assert_true(
    @io.verify_bundle(manifest, modified).any(d => d.code == "bundle_mismatch"),
  )
  assert_true(
    @io.verify_bundle(manifest, bytes[1:].to_owned()).any(d => {
      d.code == "bundle_missing"
    }),
  )
  assert_true(
    @io.verify_bundle(
      manifest.replace(old="\"schema_version\": 2", new="\"schema_version\": 9"),
      bytes,
    ).any(d => d.code == "bundle_schema"),
  )
  assert_true(
    @io.verify_bundle(
      manifest.replace(old="report.html", new="../report.html"),
      bytes,
    ).any(d => d.code == "bundle_schema"),
  )
}

///|
test "batch parser rejects colliding and nonportable output identifiers before writing" {
  let document = "{\"schema_version\":1,\"cases\":[{\"id\":\"case-01\",\"study\":\"s.json\",\"input\":\"i.csv\"}]}"
  assert_true(@io.parse_batch_json(document) is Ok([_]))
  for id in ["../outside", "CON", "case/01", "", "LPT1", "a.b"] {
    assert_true(
      @io.parse_batch_json(document.replace(old="case-01", new=id)) is Err(_),
    )
  }
  let duplicate = "{\"schema_version\":1,\"cases\":[{\"id\":\"CASE\",\"study\":\"s\",\"input\":\"i\"},{\"id\":\"case\",\"study\":\"s\",\"input\":\"i\"}]}"
  assert_true(@io.parse_batch_json(duplicate) is Err(_))
}

///|
test "revision renderers escape public change fields and raw text" {
  let revision : @evidence.TrackRevision = {
    study_id: "synthetic <script>",
    changes: [
      {
        visit_id: "v1",
        lesion_id: None,
        field: "<script>alert(1)</script>",
        before: Some("<img src=x>"),
        after: None,
      },
    ],
    impacts: [],
  }
  let html = @io.render_revision_html(revision, language=SimplifiedChinese)
  assert_true(!html.contains("<script>"))
  assert_true(!html.contains("<img"))
  assert_true(html.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
  assert_true(
    @io.render_revision_markdown(revision).contains("&lt;img src=x&gt;"),
  )
}

///|
test "node CR checks use short-axis strict inequality and history gates stay explicit" {
  let (profile, _) = template_pair("multi")
  guard @io.parse_study_json(profile) is Ok(study) else { fail("study") }
  let visits : Array[@visit.Visit] = [
    {
      id: "normalized",
      date: "2026-01-02",
      technique_id: study.technique_id,
      measurements: [
        { lesion_id: "T1", observation: Absent, },
        { lesion_id: "N1", observation: Measured(99), },
      ],
    },
    {
      id: "reappearance",
      date: "2026-01-03",
      technique_id: study.technique_id,
      measurements: [
        { lesion_id: "T1", observation: Absent, },
        { lesion_id: "N1", observation: Measured(100), },
      ],
    },
  ]
  guard @replay.replay_track(study, visits) is Ok(t) else { fail("track") }
  let cr = @replay.explain_assessment(t.assessments[0]).filter(c => {
      c.code == "node_cr_short_axis"
    })[0]
  assert_eq(cr.left, Some(99))
  assert_eq(cr.right, 100)
  assert_eq(cr.operator, "<")
  assert_eq(cr.passed, Some(true))
  let ne = @replay.explain_assessment(t.assessments[1])
  assert_eq(ne.filter(c => c.code == "context_open")[0].passed, Some(false))
  assert_true(!ne.filter(c => c.code == "pd_relative_5S_ge_6N")[0].active)
}
