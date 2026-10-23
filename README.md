# lesion-followup

An offline MoonBit library for reviewing manually measured CT target lesions.
It keeps baseline and historical-minimum references explicit and returns each
target category together with the measurements and rules that support it.

**靶病灶随访复核：保留每次计算的基线、历史最低值和测量依据。**

This project implements a documented RECIST 1.1 **target-lesion subset** for
software review and education. It does not read images, choose targets, evaluate
non-target disease or new lesions, assign overall response, or recommend
treatment. All included cases are synthetic. A target CR/PR/SD/PD is not an
overall CR/PR/SD/PD.

## Run the demos

Install the [MoonBit toolchain](https://www.moonbitlang.com/download/), then run
from this checkout:

```sh
moon run --target native cmd/demo -- --scenario nadir-boundary
moon run --target native cmd/demo -- --scenario node-resolution --format json
moon run --target native cmd/demo -- --scenario missing-visit --format svg
moon run --target native cmd/demo -- --study examples/study.json --input examples/followup.csv --format html --output review.html
moon run --target native cmd/demo -- --study examples/study.json --input examples/followup.csv --check-input --format json
moon run --target native cmd/demo -- --scenario nadir-boundary --bundle review-bundle
```

Open [the saved example report](examples/review.html) locally for an immediate
preview. It contains inline CSS and SVG with no JavaScript or external assets.
Category cards and ledger rows link to the relevant visit evidence.

| Synthetic scenario | What it demonstrates | Ordered target categories |
| --- | --- | --- |
| `nadir-boundary` | Baseline 100.0 mm, then 20.0, 24.0, 25.0; PD needs both relative and absolute growth | PR, PR, PD |
| `node-resolution` | Node short axis 10.0 vs 9.9 mm; reappearance needs overall context | PR, CR, NE |
| `missing-visit` | An unmeasured visit cannot lower the nadir | PR, NE, PR, PD |

`--format` accepts `markdown`, `json`, `csv`, `svg`, or `html`. Without `--output`,
the report goes to standard output. Output parents must already exist. Existing
output files are replaced, except resolved source input paths are protected.
`--bundle` creates a directory containing `report.html`, `audit.json`, `audit.csv`,
`chart.svg`, and `manifest.json`; repeating the same input produces identical
artifact bytes. It replaces those named files in the selected directory.

CLI exit codes are `0` for valid input (including NE or PD observations), `2` for
arguments, parsing or structural validation errors, and `1` for I/O failures.
`--check-input` validates schema and track structure; it does not assess clinical
comparability or determine whether observations will be NE.

## Public API

Consumers import the root package as `lib`:

```text
import { "impart563/lesion-followup" @lib }
```

The following example is compiled and tested with the library:

```mbt check
///|
test "exact target PD boundary through the public facade" {
  let study : @lib.Study = {
    id: "synthetic-example",
    baseline_date: "2026-01-01",
    technique_id: "ct-5mm",
    slice_thickness_tenths_mm: 50,
    targets: [
      { id: "T1", organ: "liver", kind: NonNodal, baseline_tenths_mm: 200, },
    ],
  }
  let visit : @lib.Visit = {
    id: "week-4",
    date: "2026-02-01",
    technique_id: "ct-5mm",
    measurements: [{ lesion_id: "T1", observation: Measured(250), }],
  }
  guard @lib.replay_track(study, [visit]) is Ok(trajectory) else {
    fail("valid example was rejected")
  }
  assert_eq(trajectory.assessments[0].response.code(), "PD")
  assert_eq(trajectory.assessments[0].nadir_visit_id, "baseline")
}
```

The root exports `Study`, `TargetLesion`, `LesionKind`, `Visit`, `Measurement`,
`Observation`, `Trajectory`, `VisitAssessment`, findings, issues and diagnostics;
`validate_study`, `validate_track`, `replay_track`; study-JSON and follow-up-CSV
parsers; and all public report renderers. The library uses no file or network I/O.
The native CLI uses `moonbitlang/async@0.19.4` for file and stream access.

`replay_track` rejects structurally invalid tracks as a whole. Successful replay
snapshots the supplied arrays and preserves visit order. Missing or unsupported
observations are retained in NE assessments. Renderers expect a trajectory
returned by successful replay; callers should not mutate its arrays.

[The quickstart](examples/quickstart/main.mbt) exercises the facade directly.
[A separate consumer module](examples/downstream-consumer/main.mbt) verifies
external type construction, methods and reporting through a local workspace:

```sh
moon run --target native examples/quickstart
moon -C examples/downstream-consumer run --target native .
```

## Exact inputs and evidence

[Study JSON](examples/study.json) declares `schema_version: 1`, a baseline date,
a comparable technique ID, CT slice thickness, and a fixed one-to-five target
set. Non-nodal targets use longest diameter; nodes use short axis. All nodes use
the single organ group `lymph_nodes`. Callers supply canonical organ groups and
must combine paired organs consistently. Each group may have at most two targets.

Diameters are unsigned decimal **strings** with at most one decimal place in
JSON, and plain decimal fields in CSV. The API uses tenths of a millimetre.
No input values are rounded. CT slices must be 0.1–5.0 mm; baseline target minima
are 10.0 mm for non-nodal lesions and 15.0 mm for nodes. The software limit per
diameter is 1000.0 mm. MRI, thicker CT slices and other acquisition methods are
outside this version's input contract.

The [long-form CSV](examples/followup.csv) has this exact header:

```csv
visit_id,date,technique_id,lesion_id,state,diameter_mm,note
```

Rows for one visit must be contiguous and repeat identical date and technique.
Visits use unique IDs and strictly increasing Gregorian `YYYY-MM-DD` dates after
baseline; `baseline` is a reserved visit ID. The parser never sorts rows. It
supports quoted commas, escaped quotes, multiline fields, CRLF and a UTF-8 BOM.
Parse diagnostics carry one-based physical line, column and field positions.
Structural validation issues identify visits and targets but do not carry CSV
locations. JSON schema errors identify field paths; unknown fields are rejected.

| `state` | `diameter_mm` | `note` | Meaning |
| --- | --- | --- | --- |
| `measured` | Required decimal | Empty | Reader's actual diameter, including sub-5-mm measurements |
| `absent` | Empty | Empty | Explicitly disappeared; effective size 0.0 mm |
| `too_small` | Empty | Empty | Visible but not reproducibly measurable; explicit 5.0 mm default |
| `missing` | Empty | Empty | Unmeasured, never imputed as zero |
| `not_evaluable` | Empty | Required reason | Reader-supplied limitation, such as lesion coalescence |

Omitted baseline targets behave as `missing`. Unknown targets and duplicate
measurements are structural errors. An empty visit can be supplied through the
API; CSV needs at least one explicit `missing` row to represent that visit.

Audit JSON retains the study, original observations, resolved diameters, target
category, prior nadir visit, and findings. CSV uses `assessment`, `measurement`
and `finding` detail rows. Missing quantities use JSON `null` or blank CSV fields.
Percent changes use integer basis points in JSON and two decimal places in
display reports, truncated toward zero. Exact integer comparisons determine
categories independently of displayed percentages.

## Rule boundaries

PR uses baseline; PD uses the prior complete eligible minimum and requires both
growth conditions. Node CR retains actual node size below 10 mm in the sum.
NE visits do not change the reference. Technique changes require review.
After target PD, further classifications are outside this release. Reappearance
after target CR, or loss of a prior PR threshold without PD, requires response
context and produces NE rather than an inferred overall category. These review
gates persist for the remaining track.

See [rule semantics and sources](docs/rule-semantics.md) for exact comparisons,
conservative exclusions, and the difference between target and overall response.
This implementation does not establish clinical or regulatory validation.

## Checks

```sh
python scripts/acceptance.py
```

The acceptance script discovers `moon` on PATH or in `~/.moon/bin`, requires only
Python 3.8+ standard library, runs warning-free all-target checks/tests, native
build, README examples, public interfaces, a separate consumer module, five-format
consistency, deterministic bundles, CLI failures and escaping checks, and builds
the Mooncakes source package. [Acceptance details](docs/acceptance.md) and the
[recorded local result](docs/acceptance-results.json) identify verified commands
and the source fingerprint. The same script is configured in CI.

## License

Apache-2.0 for this project's code and original documentation. The RECIST name,
source publications and linked materials retain their respective ownership and
terms. Official PDFs, forms and images are not redistributed here.
