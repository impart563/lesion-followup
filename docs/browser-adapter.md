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
No server-side computation is needed. For example, on Linux/macOS:

```sh
python -m http.server 8765 --bind 127.0.0.1 --directory _build/browser
```

On Windows, if Python's HTTPServer hostname lookup fails, run from the repository:

```sh
python -u -c "import http.server,socketserver; server=socketserver.TCPServer(('127.0.0.1',8765),http.server.SimpleHTTPRequestHandler); server.serve_forever()"
```

Open `http://127.0.0.1:8765/_build/browser/` for the Windows command, or
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
does not select a default. `language` defaults to `en` and accepts `en` or `zh-CN`.

| Action | Required text fields | Optional fields | Result |
| --- | --- | --- | --- |
| `review` | `study_json`, `followup_csv` | `language`, `format` = `json` | Existing audit/report text |
| `preflight` | `study_json`, `followup_csv` | `language`, `format` = `json` | Input checks without response categories |
| `template` | None | `language`, `template` = `multi` | Matched synthetic files |
| `editor` | `study_json`, `followup_csv` | `language` | Parsed study and editable CSV cells, with preflight |

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
| Invalid study/CSV input | Requested action | `false` | `input` | Full report | `null` |
| Valid review/preflight | Requested action | `true` | `null` | Full report | Format/media type/content |
| Valid template | `template` | `true` | `null` | `null` | `files: [{name, content}]` |
| Editable input shape | `editor` | `true` | `null` | Full report, possibly `valid: false` | `study`, `rows` |

For `editor`, `ok: true` means the table shape can be edited. It does not mean
the clinical inputs are valid or evaluable. The caller must gate review on the
existing preflight/review actions. The workbench blocks generation and printing
when preflight has errors, and retracts stale outputs immediately after any edit.

For request errors, `diagnostics` contains a `code`, JSON `field` path and
English `message`. Codes are `request_json`, `request_schema`, `request_version`,
`request_action`, `request_language`, `request_format` and `request_template`.
The adapter returns one request diagnostic. For recognized requests,
`diagnostics` is empty: existing parse diagnostics and structural issues retain
their codes, messages and locations inside `preflight.diagnostics` and
`preflight.input_issues`. This avoids duplicating or relabeling source errors.

Review hints stay in `preflight.review_hints`. A valid NE observation therefore
has `ok: true`; NE does not become a request or input error. Invalid input never
returns a partial clinical report. `preflight.valid` concerns parse/structural
checks and does not establish clinical comparability or overall response.

Report `content` is byte-for-byte equal to the corresponding CLI stdout for
the same text inputs, format and language. JSON/CSV machine fields and messages
remain language independent. JSON result content is a string containing the
existing audit schema; parse it a second time when structured evidence is needed.
Media types omit a charset; all strings are Unicode and saved files use UTF-8.
Each call evaluates its complete supplied track and retains no previous track.
The v1 adapter exposes review, preflight, templates and editor cells; revision and batch file
workflows continue through their existing APIs/CLI.

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
The six MoonBit adapter tests run on all four library targets as well.

On 2026-10-25 the packaged smoke page passed all five checks in the Codex in-app
browser, reporting Chromium 155.0.0.0 on Windows. It loaded the local compiled
module, produced PR→PR→PR→PD from the synthetic multi-target template, rejected
extra precision with the diameter field location, preserved successful NE with
three review hints, returned the request-error envelope, and repeated the original
review identically. These are software checks, not clinical validation.
