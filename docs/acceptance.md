# Reproducible software acceptance

Run from the repository root:

```sh
python scripts/acceptance.py
```

To refresh the saved result **after** changing sources and reviewing generated
interfaces and previews:

```sh
moon fmt
moon info
moon -C examples/downstream-consumer info
moon run --target native cmd/demo -- --study examples/study.json --input examples/followup.csv --format html --output examples/review.html
python scripts/acceptance.py --record docs/acceptance-results.json
```

The script uses Python 3.8+ standard library. MoonBit is discovered on PATH or in
the standard `~/.moon/bin` installation. Build tools required by MoonBit's native
target must be installed. The library targets wasm, wasm-gc, JavaScript and
native; filesystem CLI tests run only on native.

| Area | Evidence |
| --- | --- |
| Medical arithmetic | Assertion tests for inclusive PR/PD thresholds, PD's dual condition, baseline/nadir distinction, node short axis, incomplete data and context gates |
| Input contracts | Decimal and schema tests, physical CSV locations, CRLF/BOM/multiline parsing, metadata consistency, no partial parsing |
| Public API | Root-facade black-box test, compiled README, runnable quickstart and separate module consumer |
| Reports | Five formats for three synthetic scenarios and a JSON/CSV file fixture, evidence consistency and repeatability |
| Visualization | SVG XML parsing, exclusion of NE points, HTML IDs/links and script/resource checks |
| File workflow | Direct output, repeatable five-file bundles, manifest consistency, source input protection and failure exit codes |
| Distribution | Formatting, warning-free compilation/tests, native build, stable generated interfaces and Mooncakes package contents |

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
