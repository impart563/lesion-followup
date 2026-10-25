# Browser computation adapter

The `browser` package compiles the existing root facade to one JavaScript ES
module. It exports only `evaluate(request_json: string): string`, synchronously.
The adapter performs no file access, network requests, storage or DOM changes.
All clinical parsing, validation, replay and reporting come from the same
MoonBit implementation used by the native CLI. There is no JavaScript copy of
the clinical rules. Results cover **target lesions only**.

## Build and import

From the repository root, with the pinned MoonBit toolchain and Python 3.8+:

```sh
python scripts/build_browser.py
```

The output in `_build/browser/` contains `browser.js`, its TypeScript declaration,
a module-type `package.json`, the workbench `index.html` and its local assets,
and `smoke.html`, a synthetic smoke page. A source
map is copied if emitted by the compiler. The JavaScript module has no runtime
dependencies or external asset imports. Serve these local files over HTTP with
a static server; browsers generally restrict ES module loading from `file:` URLs.
No server-side computation is needed. Use the supplied loopback server on all
platforms; it sets explicit JavaScript MIME types for `.js` and `.mjs`:

```sh
python scripts/serve_browser.py --directory _build/browser --port 8765
```

To keep the repository-root URL instead, run:

```sh
python scripts/serve_browser.py --directory . --port 8765
```

Open `http://127.0.0.1:8765/_build/browser/` for the repository-root command, or
`http://127.0.0.1:8765/` when serving the output directory. Append `smoke.html`
for the five synthetic adapter checks. The [workbench guide](workbench.md)
describes import, editing, explicit drafts and current-report printing.

Import from your application, using text read by your own file picker:

```js
import { evaluate } from "./browser.js";

const response = JSON.parse(evaluate(JSON.stringify({
  schema_version: 1,
  action: "review",
  study_json: studyText,
  followup_csv: csvText,
  language: "zh-CN",
  format: "html"
})));

if (response.ok) {
  // response.result.content contains the existing self-contained report.
  console.log(response.result.media_type, response.result.content);
} else if (response.error_kind === "input") {
  console.log(response.preflight.diagnostics, response.preflight.input_issues);
} else {
  console.log(response.diagnostics);
}
```

The JavaScript argument must be a string. Pass original JSON/CSV text through
unchanged. Study diameters remain decimal strings such as `"9.9"`; do not
convert them to JavaScript numbers, round them, or parse CSV with string splitting.
The existing parser converts decimal input to exact integer tenths of a
millimetre. Threshold comparison and missing-observation semantics are unchanged.

## Request version 1

Every request is an object with numeric `schema_version: 1` and an `action`.
Unknown fields, wrong types, unsupported values and fields belonging to another
action are rejected. Optional fields must be omitted to use defaults; `null`
does not select a default. `language` defaults to `en` and accepts `en` or `zh-CN` on actions that support it.

| Action | Required text fields | Optional fields | Result |
| --- | --- | --- | --- |
| `review` | `study_json`, `followup_csv` | `language`, `format` = `json` | Existing audit/report text |
| `preflight` | `study_json`, `followup_csv` | `language`, `format` = `json` | Input checks without response categories |
| `template` | None | `language`, `template` = `multi` | Matched synthetic files |
| `editor` | `study_json`, `followup_csv` | `language` | Parsed study and editable CSV cells, with preflight |
| `bundle` | `study_json`, `followup_csv` | `language` | Five native report files |
| `verify-bundle` | `manifest`, plus `files` array | None | Core bundle validation |
| `batch-index` | `cases` array | `language` | Native index JSON and HTML |
| `compare` | `study_json`, `followup_csv`, `compare_study_json`, `compare_followup_csv` | `language`, `format` = `json` | Existing revision report text |

`compare` uses `compare_*` as the original version and unprefixed fields as the
current version. It accepts `json`, `markdown` or `html`. Its envelope retains
`schema_version: 1` and `scope: target_lesions_only`, with `preflight` containing
two independent existing reports under `before` and `after`. Invalid inputs
return `ok: false`, `error_kind: input`, empty top-level diagnostics and no result.
Incompatible baseline profiles return `error_kind: comparison` and the core's
`revision_baseline` diagnostic. Successful results use the existing format,
media type and content shape. All other actions retain their original contracts.

```js
const result = JSON.parse(evaluate(JSON.stringify({
  schema_version: 1, action: "compare", language: "zh-CN", format: "json",
  study_json: currentStudyText, followup_csv: currentCsvText,
  compare_study_json: originalStudyText, compare_followup_csv: originalCsvText
})));
```

The workbench's example catalogue is bundled at build time in `examples.mjs`;
it performs no runtime fetch. Portable two-version sessions are a separate
presentation/persistence contract documented in the [workbench guide](workbench.md).

`review` accepts `json`, `csv`, `markdown`, `svg` and `html`. `preflight` accepts
`json` and `markdown`. `template` accepts `single` or `multi` and returns
`study.json`, `followup.csv` and `README.md` as in-memory name/content pairs.
These are the same files returned by the existing template API; writing files
or initiating downloads is the caller's responsibility. The browser default is
the multi-target template, explicitly independent of the CLI's single default.

`editor` rejects a `format` field. It returns `{study, rows}` where `study` has
the existing study-JSON shape and `rows` is an ordered array of seven string
cells per observation, without the header. The CSV decoder is the MoonBit
`parse_followup_cells` facade, reusing the existing quoting and newline parser.
It checks the CSV shape rather than clinical state or precision. Structurally
invalid study values and invalid observation cells can therefore remain editable.
Study JSON syntax/schema failures or CSV quoting/header/column failures return
an input-error envelope with no table result. Source text is never repaired.

## Response version 1

Every response has the same top-level fields:

```json
{
  "schema_version": 1,
  "scope": "target_lesions_only",
  "action": "review",
  "ok": true,
  "error_kind": null,
  "diagnostics": [],
  "preflight": {},
  "result": {"format": "json", "media_type": "application/json", "content": "..."}
}
```

The `{}` above abbreviates the full existing preflight schema, not an empty
preflight response. The [TypeScript declarations](../browser/browser.d.ts)
describe the response variants.

| State | `action` | `ok` | `error_kind` | `preflight` | `result` |
| --- | --- | --- | --- | --- | --- |
| Invalid request | `null` | `false` | `request` | `null` | `null` |
| Invalid study/CSV input (review/preflight/editor/bundle) | Requested action | `false` | `input` | Full report | `null` |
| Valid review/preflight | Requested action | `true` | `null` | Full report | Format/media type/content |
| Valid bundle | `bundle` | `true` | `null` | Full report | `files: [{name, content}]` |
| Valid batch index | `batch-index` | `true` | `null` | `null` | `files: [{name, content}]` |
| Intact bundle | `verify-bundle` | `true` | `null` | `null` | JSON validation content |
| Bundle validation failure | `verify-bundle` | `false` | `bundle` | `null` | `null` |
| Valid template | `template` | `true` | `null` | `null` | `files: [{name, content}]` |
| Editable input shape | `editor` | `true` | `null` | Full report, possibly `valid: false` | `study`, `rows` |
| Comparison input failure | `compare` | `false` | `input` | `before` and `after` reports | `null` |
| Incompatible comparison profiles | `compare` | `false` | `comparison` | `before` and `after` reports | `null` |
| Valid comparison | `compare` | `true` | `null` | `before` and `after` reports | Format/media type/content |

For `editor`, `ok: true` means the table shape can be edited. It does not mean
the clinical inputs are valid or evaluable. The caller must gate review on the
existing preflight/review actions. The workbench blocks generation and printing
when preflight has errors, and retracts stale outputs immediately after any edit.

For request errors, `diagnostics` contains a `code`, JSON `field` path and
English `message`. Codes are `request_json`, `request_schema`, `request_version`,
`request_action`, `request_language`, `request_format` and `request_template`.
The adapter returns one request diagnostic. For recognized requests other than
incompatible-profile comparisons and bundle validation, `diagnostics` is empty: existing parse diagnostics and structural issues retain
their codes, messages and locations inside `preflight.diagnostics` and
`preflight.input_issues`. This avoids duplicating or relabeling source errors.

Review hints stay in the relevant preflight report's `review_hints`. A valid NE observation therefore
has `ok: true`; NE does not become a request or input error. Invalid input never
returns a partial clinical report. Each preflight report's `valid` concerns parse/structural
checks and does not establish clinical comparability or overall response.

Report `content` is byte-for-byte equal to the corresponding CLI stdout for
the same text inputs, format and language. JSON/CSV machine fields and messages
remain language independent. JSON result content is a string containing the
existing audit schema; parse it a second time when structured evidence is needed.
Media types omit a charset; all strings are Unicode and saved files use UTF-8.
Each call evaluates its complete supplied track and retains no previous track.
The browser adapter remains an in-memory boundary. File selection, ZIP transport,
progress display and downloads belong to the workbench, outside the MoonBit library.

## Report delivery actions

`bundle` rejects `format`. After the existing preflight and replay it returns
`report.html`, `audit.json`, `audit.csv`, `chart.svg` and `manifest.json`, using
`review_artifacts` and `render_bundle_manifest`. The manifest's `raw_bytes` inputs
are the UTF-8 encoding of the supplied strings. They match native raw-file hashes
when the supplied text represents the same valid UTF-8 bytes. A browser's initial
file decoding may strip a BOM or replace invalid bytes; this boundary does not
recover original disk bytes. CRLF retained in a supplied string is preserved.

`verify-bundle` requires a manifest string and `files: [{name, content}]`, with
at most four artifact entries, each containing exactly those two string fields.
It delegates UTF-8 bytes to `verify_bundle`. Missing, duplicated, unexpected or
changed artifacts retain core diagnostics in top-level `diagnostics`; failure
uses `error_kind: bundle`, null preflight and null result. Success returns the
native validation JSON in the usual format/content object. It checks bundle
consistency, not producer identity or clinical correctness; it does not rerun
all classifications or verify original source files that are not in the archive.

`batch-index` requires 1–20 `cases`. Each has exactly `id`, `status`, `message`,
`visit_count` and `review_hint_count`. Counts are integers from 0 to 2147483647;
status is `success`, `input_error` or `io_error`. IDs reuse the native portable,
case-insensitively unique identifier rules. Successful report paths are generated
as `id/report.html`; failures have no report path. The result contains
`index.json` and `index.html` from the existing core renderers. These are supplied
metadata, not independently evaluated clinical results. The workbench constructs
them from each session's actual bundle/preflight response.

The JavaScript archive layer supports bounded stored and DEFLATE ZIPs without
extracting files to disk. Its limits and supported layout are described in the
[workbench guide](workbench.md). ZIP structure follows the
[PKWARE APPNOTE 6.3.10](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT);
DEFLATE decoding uses the standard
[Compression Streams API](https://compression.spec.whatwg.org/).

## Human review note boundary

The workbench's manual checklist consumes the existing `editor` preflight's
`review_hints`. No browser action or clinical rule is added for annotations.
Viewing states and comments belong to the presentation layer, remain bound to
the raw source pair, and do not alter MoonBit findings or categories. Their
separate strict JSON and HTML/Markdown contracts are described in
[human review notes](review-notes.md). Existing report, bundle, draft and session
formats remain unchanged.

## Verification

```sh
python scripts/acceptance.py
```

Acceptance requires Node.js as well as the existing MoonBit/native build tools.
CI uses Node 22. It imports the release ES module through Node, checks its exact
export surface, tests strict request and error envelopes, and compares bilingual
five-format reports and preflights against the native CLI. Synthetic cases cover
PR/PD adjacent tenths, both PD conditions, node CR at 9.9/10.0 mm, revised nadirs,
post-PD NE, missing values, a technique change, exact precision rejection,
numeric JSON diameter rejection, physical multiline locations and Unicode notes.
The MoonBit adapter tests run on all four library targets as well.

On 2026-10-25 the packaged smoke page passed all five checks in the Codex in-app
browser, reporting Chromium 155.0.0.0 on Windows. It loaded the local compiled
module, produced PR→PR→PR→PD from the synthetic multi-target template, rejected
extra precision with the diameter field location, preserved successful NE with
three review hints, returned the request-error envelope, and repeated the original
review identically. These are software checks, not clinical validation.
