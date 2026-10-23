# Reproducible software acceptance

Run from the repository root:

```sh
moon update
python scripts/acceptance.py
```

To refresh the saved result **after** changing sources and reviewing generated
interfaces and previews:

```sh
moon fmt
moon info
moon -C examples/downstream-consumer info
moon run --target native cmd/demo -- --study examples/study.json --input examples/followup.csv --format html --output examples/review.html
moon run --target native cmd/demo -- --study examples/study.json --input examples/followup.csv --format html --lang zh-CN --output examples/review.zh-CN.html
python scripts/acceptance.py --record docs/acceptance-results.json
```

The script uses Python 3.8+ standard library. MoonBit is discovered on PATH or in
the standard `~/.moon/bin` installation. Build tools required by MoonBit's native
target must be installed. The library targets wasm, wasm-gc, JavaScript and
native; filesystem CLI tests run only on native.

The verified compiler release is `0.10.14+7d59c7ec9` (Moon CLI
`0.1.20260920`). CI pins both the compiler tools and matching core library to
this release through the official installer's `MOONBIT_INSTALL_VERSION`.
On Linux or macOS, install the same release with:

```sh
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash -s -- '0.10.14+7d59c7ec9'
```

When upgrading MoonBit, review formatter and public-interface changes and rerun
the complete acceptance script before updating the CI pin and saved result.
Fresh installations need `moon update` once before running checks so that the
registry can resolve `moonbitlang/async`; CI performs this step explicitly.

| Area | Evidence |
| --- | --- |
| Medical arithmetic | Assertion tests for inclusive PR/PD thresholds, PD's dual condition, baseline/nadir distinction, node short axis, incomplete data and context gates |
| Input contracts | Decimal and schema tests, physical CSV locations, CRLF/BOM/multiline parsing, metadata consistency, no partial parsing |
| Public API | Root-facade black-box test, compiled README, runnable quickstart and separate module consumer |
| Reports | Five formats for three synthetic scenarios and a JSON/CSV file fixture, evidence consistency and repeatability |
| Visualization | SVG XML parsing, exclusion of NE points, HTML IDs/links and script/resource checks |
| File workflow | Direct output, repeatable five-file bundles, manifest consistency, source input protection and failure exit codes |
| Distribution | Formatting, warning-free compilation/tests, native build, stable generated interfaces and Mooncakes package contents |
| Input preparation | Directly runnable single/multi templates, Unicode paths and rejection of existing destinations |
| Quality preflight | Review hints separated from errors, physical multiline CSV positions, JSON structural paths and unchanged input bytes |
| Language and target plots | Matching bilingual quantities and machine formats, individually checked observation values, NE markers and connecting-line gaps |

`docs/acceptance-results.json` is written only after every check passes. It
records the toolchain, actual per-target test counts, scenario outcomes, command
count, workflow groups and a SHA-256 fingerprint of source/configuration inputs.
Build/cache directories, generated HTML previews, images, archives and the
result record itself are excluded from that fingerprint; line endings are
normalized to LF. Source changes require a new record. Temporary test inputs
are created by the script and are removed on completion.

The separate consumer uses a local `moon.work` linking this checkout. This
verifies module boundaries before a registry release, not installation of an
already-published registry version. The current repository has no remote
publication requirement for running these checks. CI is configured to execute
the same script; a local pass does not imply an unexecuted remote CI pass.

The saved example HTML has also been inspected in a browser, including category
card navigation to the corresponding visit evidence. All numeric scenarios and
input fixtures are synthetic. This is software acceptance, not clinical,
regulatory, imaging-reader or diagnostic validation.

## Input and report usability preview

On 2026-10-24, the saved Chinese example was opened through localhost in the
Codex in-app browser. At a 1265 × 712 viewport, the Chinese headings, target-only
scope, category cards, sum chart and ledger were readable. Selecting the PD card
navigated to `#visit-3`, showing week-8's 25.0 mm sum evidence, with T1 at 15.0 mm
and N1 at 10.0 mm. Scrolling showed separate T1 longest-diameter and N1 short-axis
plots and the observation ledger, without clipped headings or overlapping plots.
This preview checks presentation and navigation. Marker values, missing-value
gaps, defaults and hollow NE markers are checked against audit JSON by the
acceptance script and the MoonBit observation-state tests.
