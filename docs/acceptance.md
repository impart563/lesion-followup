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
moon run --target native cmd/demo -- --study examples/study.json --input examples/followup.revised.csv --compare-study examples/study.json --compare-input examples/followup.csv --format html --lang zh-CN --output examples/revision.zh-CN.html
python scripts/acceptance.py --record docs/acceptance-results.json
```

The script uses Python 3.8+ standard library and Node.js for browser-module
acceptance (CI uses Node 22). MoonBit is discovered on PATH or in
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

On Windows, use the official PowerShell installer with the same pin:

```powershell
$env:MOONBIT_INSTALL_VERSION = '0.10.14+7d59c7ec9'
Invoke-RestMethod https://cli.moonbitlang.com/install/powershell.ps1 | Invoke-Expression
```

CI uses clean `windows-2022` and `ubuntu-24.04` runners, Python 3.12 and Node 22.
Both check out into a path containing spaces and Chinese characters, then run the
same script without restored build/dependency caches. The Windows image provides
Visual Studio native build tools. Each job uploads its actual platform record,
compiled browser entry and candidate module archive. The record includes runner
OS, commit and run ID; source fingerprints normalize CRLF to LF. HTTP entry checks
verify MIME types and exact runtime bytes through the included loopback server;
they do not claim GUI-browser tests. Windows system mappings may classify `.mjs`
as an ordinary file, so `scripts/serve_browser.py` explicitly supplies JavaScript
MIME types and avoids hostname-dependent startup. The compiled browser archive
includes the same standalone server.

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
| Calculation trace | Exact operands checked against audit values, inactive branches, missing operands and NE gate evidence |
| Revisions | Measurement alignment, same-input empty differences, visit additions/removals, baseline rejection and downstream nadir/category effects |
| Bundle provenance | Independent Python hashlib comparison, raw-file fingerprints, byte lengths, tampering/missing files/profile/version rejection and read-only verification |
| Batch workflow | Manifest-relative paths, partial input/I/O failure isolation, matching per-case results, portable IDs and rejection of existing output roots |
| Browser adapter | Release ES module export, strict versioned requests, templates, stateless calls and byte-identical bilingual CLI reports; exact clinical boundaries, NE gates, Unicode and located input failures |
| Workbench and drafts | Table/source round trips through the MoonBit CSV decoder, editable invalid values with replay gates, versioned unfinished drafts, exact source hashes and no remote runtime assets |
| Print preparation | Summary/full documents retain matching inputs and complete evidence links; synthetic 36-visit fixtures exercise long tables, Unicode notes and NE |
| Complete examples | Four hand-calculated tracks, twenty browser/native format comparisons, importable drafts, revision and matching batch outputs |
| Candidate consumption | A separate temporary consumer reads the extracted module archive, and runs on wasm, wasm-gc, js and native without linking the checkout library |
| Browser revisions and sessions | Twenty-four bilingual native format comparisons, independent preflight locations, baseline guards, fixed source fingerprints, strict session versions, independent SHA-256 checks, tamper rejection and restored evidence |

`docs/acceptance-results.json` is written only after every check passes. It
records the toolchain, actual per-target test counts, scenario outcomes, command
count, workflow groups and a SHA-256 fingerprint of source/configuration inputs.
Build/cache directories, generated example HTML previews, images, archives and the
result record itself are excluded from that fingerprint; line endings are
normalized to LF. Source changes require a new record. Temporary test inputs
are created by the script and are removed on completion.

The handwritten browser smoke HTML is included in the source fingerprint.
Browser acceptance records the Node version, request count and native parity
case count. The [browser adapter contract](browser-adapter.md) contains build,
import and smoke-page instructions, and the actual browser check record.

The separate consumer uses a local `moon.work` linking this checkout. This
verifies module boundaries before a registry release, not installation of an
already-published registry version. The current repository has no remote
publication requirement for running these checks. CI is configured to execute
the same script; a local pass does not imply an unexecuted remote CI pass.

The saved example HTML has also been inspected in a browser, including category
card navigation to the corresponding visit evidence. All numeric scenarios and
input fixtures are synthetic. This is software acceptance, not clinical,
regulatory, imaging-reader or diagnostic validation.

## Complete collection and candidate checks

The subsequent workbench review on 2026-10-25 covered all four catalogue options
and the single-target template through the actual selector. A paired revision
showed one changed observation and three affected visits. Downloaded comparison
JSON matched native CLI bytes. A downloaded review session passed an independent
SHA-256 check; importing and exporting again preserved both original CSV strings,
including CRLF. Editing withdrew the previous comparison; identical inputs gave
an empty diff. Corrupt sessions retained the existing result, incompatible
baselines returned no partial comparison, and unfinished text remained editable
while report generation stayed blocked. These are software workflow checks with
synthetic inputs, not clinical validation.

On 2026-10-25, the `missing/draft.json` produced by the unified collection script
was imported through the actual local workbench file chooser. The report showed
two PR, one PD and one NE; the latest eligible minimum was 20.0 mm from week-6.
The missing visit remained a gap and the page retained its manual-review state.
See [the actual page capture](review-examples.jpg). This is a desktop import and
report check; the twenty automated format comparisons cover all four tracks.

The module version is now 0.2.0. Saved report previews were regenerated for the
version footer; medical categories and numerical expectations were not changed.
See [candidate preparation and publication states](release.md) for the separate
archive, clean-directory consumption and registry-installation meanings.

## Input and report usability preview

On 2026-10-24, the saved Chinese example was opened through localhost in the
desktop Chromium browser. At a 1265 × 712 viewport, the Chinese headings, target-only
scope, category cards, sum chart and ledger were readable. Selecting the PD card
navigated to `#visit-3`, showing week-8's 25.0 mm sum evidence, with T1 at 15.0 mm
and N1 at 10.0 mm. Scrolling showed separate T1 longest-diameter and N1 short-axis
plots and the observation ledger, without clipped headings or overlapping plots.
This preview checks presentation and navigation. Marker values, missing-value
gaps, defaults and hollow NE markers are checked against audit JSON by the
acceptance script and the MoonBit observation-state tests.

On 2026-10-24 the Chinese revision example was also previewed in the same
browser. It displayed one changed observation, three affected visits, week-6
PR→PD and week-8 PD→NE, with readable before/after measurement and minimum
columns. Both revisions use synthetic inputs. Calculation-condition tables
retain the existing report's visit navigation and target-only scope.

## Offline workbench review

On 2026-10-25 the workbench was exercised in a desktop Chromium browser
(Chromium 155.0.0.0, Windows, default desktop viewport). Actual file chooser
imports loaded the saved study JSON and CSV. Editing week-4 T1 to 10.01 mm
located the precision error and disabled replay; correcting it to 9.0 mm produced
PR, PR, PD, NE. The generated CSV and JSON were downloaded and imported again;
the input fingerprint matched exactly. Navigation, collapsed
baseline details, editable observation table, Chinese diagnostics,
report distribution and core-generated sum chart were inspected visually.

Explicit draft save, refresh, manual restore, unsupported-version rejection
without changing the current report, and clear followed by refresh were checked.
A portable 36-visit/72-observation draft loaded successfully; filtering the last
visit showed two observations while the full report retained all 36 visits.
Both print layouts were previewed inside the page. Print content uses a scoped
Shadow DOM; local anchor navigation is handled within that same scope.

Pagination was checked independently using the official portable WeasyPrint 70.0 renderer,
downloaded from its GitHub release with SHA-256
`ab1151f210b4e6bb7aa7a79e91a67e8ddb760094c107bfda55241b6aaefe7d53`.
Small summary/full and long summary/full documents were rendered and visually
reviewed: 1, 7, 2 and 36 A4 pages respectively. All pages contained text and stayed within the checked page bounds;
Chinese notes, repeated headings, the final visit and both target plots were
retained. This rendering check is additional local QA, not a requirement to
install WeasyPrint for building or running the workbench. CI exercises the
document contracts and synthetic fixtures with Node, not this optional renderer.

The screenshot in the README shows the workbench with synthetic data. These
checks establish software behavior and layout only, not clinical validation.

## Browser batch and ZIP delivery

The unified acceptance script also runs `delivery_acceptance.py` and its Node
transport checks. Four independent native bundles cover both languages and
LF/Unicode-CRLF source strings; all 20 report/manifest files are compared byte
for byte. Python generates stored, DEFLATE and streamed/data-descriptor ZIPs
with UTF-8 directory names. Browser-generated single/batch ZIPs are opened with
Python `zipfile`, checked for CRC consistency and verified by the native CLI.

Mixed sessions cover valid revised input, corrupt containers, invalid clinical
input, file-read failure and valid NE. Cancellation, explicit resource limits,
unchanged source pairs, native index paths and partial batch results are checked.
Independent malformed ZIP fixtures cover unsafe paths, case and Unicode name
collisions, invalid UTF-8, symlinks, ZIP64 extras and underdeclared DEFLATE output.
Additional checks reject artifact changes, missing files/manifests, unsupported
profiles, unexpected files, truncated archives and inconsistent headers or CRCs.
These are software interoperability and integrity checks, not clinical validation.

On 2026-10-25, actual file-chooser selection in the Windows in-app browser
processed four synthetic sessions into two successful reports and two separately
identified failures. The downloaded batch ZIP was selected again and both report
directories passed integrity checks. Opening the revised session preserved its
reference version and reproduced one input change and three affected visits;
the current report also exported a separate ZIP. A changed HTML artifact returned
`bundle_mismatch` while editor sources remained unchanged. An independent Python
DEFLATE ZIP with data descriptors passed in the actual browser as well.

The workbench layout was visually checked at the existing 781 × 742 viewport.
No mobile viewport or native print dialog check is claimed for this batch. The
unified CI suite checks transports and data contracts without GUI automation.

## Human review record acceptance

The unified suite also runs `review_notes_acceptance.py`. Five native
preflights, including a synthetic three-hint NE record, are compared against the
manual checklist's original messages and locations. Independent Python and Node
SHA-256 checks verify the portable payload and exact source-pair binding. Note
edits are checked against unchanged core preflight and audit results. Strict
field/version/status/time validation, text/file/item limits, reordered JSON
keys, input mismatch, a recomputed digest with forged hints, zero-hint records
and backward device clocks are covered without changing clinical expectations.

Four bilingual HTML/Markdown exports retain pending items, original hints and
the input fingerprint. Untrusted HTML, link syntax, heading markers, Unicode
and code fences stay literal. In additional local QA, markdown-it-py 3.0.0 with
CommonMark and raw HTML enabled rendered both Markdown variants without active
user content or injected headings. This optional renderer is not a build or CI
dependency; CI checks document contracts and HTML with the standard library.

On 2026-10-25 the Windows in-app browser loaded the synthetic three-hint
session, recorded one viewed item plus multiline notes, and filtered the two
pending items. The core hint badge remained three and replay retained NE.
Explicit save, refresh, loading the original session and restoring local notes
retained viewing states and comments. Actual JSON export/reimport, corrupt and
wrong-input rejection, and local-copy clearing without losing in-memory notes
were exercised. Editing input made the old snapshot read-only and disabled
current HTML/Markdown export while keeping a byte-identical JSON backup;
restoring the exact source pair re-enabled the existing snapshot. The zero-hint
template displayed an empty checklist with an editable round summary.

The downloaded JSON payload was independently hashed with Python; its original
input fingerprint matched the saved session. Actual HTML and Markdown downloads
retained comments, all three hints and the one-viewed/two-pending counts. The
workbench was visually checked at 781 × 797, and the independent explanation
HTML at 1265 × 712. No mobile viewport or native print-dialog check is claimed.
These checks establish software workflow and transport behavior only.

## Complete handoff acceptance

The unified suite runs `handoff_acceptance.py`. Four bilingual handoffs retain
LF and Unicode/CRLF source strings; their 20 native report files match the
independently generated CLI files byte for byte. Python independently checks
the outer manifest and every leaf digest, writes DEFLATE and streamed ZIP
fixtures, and verifies four exported report directories with the native CLI.
Thirteen malformed archives cover missing, extra and changed files, unsupported
schemas, invalid manifests, nested session/note mismatches, and complete valid
reports from another input or language. Reordered JSON keys and ZIP entries
remain accepted. Receiver tests cover explicit apply, immutable snapshots,
concurrent inspection, source edits, file replacement and read failures.

On 2026-10-26 the Windows in-app browser exercised actual file-chooser reception,
preview without workspace replacement, explicit restoration of both source
versions, language and one viewed note, and comparison after restoration
(one measurement change and three affected visits). Actual exports with and
without notes were selected again. The no-note handoff cleared the in-memory
checklist and summary; restoring the older saved session and its local notes
confirmed that reception had not overwritten the local note copy. Editing a
note after inspection and selecting a replacement file withdrew the old load
action. Tampered and valid-but-unrelated reports were rejected without changing
the editor or notes. A Python DEFLATE ZIP with data descriptors passed in the
actual browser as well.

Python independently checked CRCs, manifest/leaf/session/note digests and exact
source-pair preservation in both actual downloaded ZIPs. Their five report files
were identical, and both extracted report directories passed native verification.
The existing desktop layout was visually reviewed. No mobile viewport or native
print-dialog check is claimed for this batch. CI covers transport and workflow
contracts with synthetic data; these checks are not clinical validation.

## Visit editing and input-history acceptance

The unified suite runs `visit_editing_acceptance.py`. One-to-five-target
creation produces exactly one blank `missing` row per baseline target without
copying prior measurements. Whole-visit updates retain every observation field
and Unicode/multiline CRLF reason; removal retains unaffected rows. Five
independent native preflights and 25 native report files match the browser
results, including removal of all visits and subsequent creation. Seventeen
invalid operations cover strict fields, duplicates, nonexistent visits,
invalid dates/order and malformed current input. Planner checks verify preview
isolation, explicit apply, failure withdrawal and revision invalidation.

History tests cover continuous-field grouping, exact original raw-text
restoration, independent snapshots, redo branching, reset, 40-step retention
and the UTF-8 byte budget. Clinical categories and expected rules are unchanged.

On 2026-10-26 the Windows in-app browser exercised duplicate-ID and date-order
rejection, preview without input replacement, form-edit withdrawal, explicit
creation, shared metadata updates, whole-visit removal and undo. Newly added
targets had empty measurements. Invalid precision blocked reports; undo restored
the prior valid input exactly. Continuous typing formed one undo step and a
new edit cleared redo. Editing retracted the old report and undo did not revive
it. Loading an external session reset history and preserved the older local
human-review copy. Input changes made those notes read-only; exact undo restored
their binding and export controls. Direct row-level renaming was also checked
against the manager's current visit selection.

Actual study JSON, CSV and audit JSON downloads were independently checked with
Python. The study text and original eight observations stayed identical; the
two added observations retained `missing` and empty diameters. The five-visit
audit JSON matched a fresh native CLI output byte for byte. The existing desktop
viewport and visit dialog were reviewed visually. No mobile or native printing
check is claimed. These are software checks using synthetic inputs.

## Observation entry and distribution acceptance

The unified suite runs `observation_acceptance.py`. Four independent native
preflights and 20 native report files match complete observation-form edits,
covering all five states, omitted targets and Unicode/multiline CRLF reasons.
Twenty invalid operations reject unknown/duplicate targets, incomplete fields,
precision overflow, incompatible values and missing reasons. The source study
text and other visits stay unchanged. Planner tests cover explicit apply,
isolated previews and withdrawal after edits or failure.

The extracted-candidate consumer now runs typed construction, template/text
parsing, preflight, valid NE, bilingual bundles and tamper rejection on all four
backends. It consumes the actual module archive without a checkout-library link;
this does not establish registry installation of this module.

`release_acceptance.py` builds local candidate-contract fixtures from actual
packaged sources and runtime files. It checks three archives, source commit and
fingerprint, module/source agreement, the complete browser runtime/import set,
four-backend consumer evidence and checksum entries. Eleven corrupt candidates
and nine invalid candidate IDs are rejected, including recomputed outer hashes
with mismatched content, unsafe paths, old manifest versions and missing files.
No publish command is part of acceptance or candidate preparation.

An additional disposable module copies the real `.moonignore` policy and places
ten root/nested archives, backups, caches and development-only files beside a
minimal public source. An actual `moon package --list` run retains the required
module files and excludes all ten local artifacts. The real module archive is
also checked for nested ZIPs, Git bundles and Python caches.

On 2026-10-26 the Windows in-app browser exercised per-target baseline context,
precision/reason rejection, state-dependent fields, change preview, explicit
save, exact one-step undo and redo. A saved NE observation retained its multiline
reason and removed its inapplicable diameter. Form edits and switching visits
withdrew prior apply actions. A measured revision changed week-4 T1 to 9.0 mm;
actual JSON/CSV input and audit downloads were independently inspected with
Python. Only that measurement changed, and the audit matched a fresh native
output byte for byte, retaining PR/PR/PD/NE and week-6 prior minimum 19.0 mm.
The desktop dialog is visually reviewed; no mobile or native-print check is
claimed. All inputs remain synthetic, and results concern target lesions only.
