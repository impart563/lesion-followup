# Human review note files

Review notes preserve a person's viewing status, comments and a round-level
summary separately from the target-lesion clinical report. They do not resolve
core findings, alter categories, determine overall response or certify clinical
validity. All examples and acceptance fixtures are synthetic.

## Version 1 container

The workbench exports UTF-8 JSON with exactly these top-level fields, in this
canonical order before appending `sha256`:

| Field | Meaning |
| --- | --- |
| `schema_version` | Numeric `1` |
| `kind` | `lesion-followup-review-notes` |
| `created_at`, `updated_at` | Canonical UTC ISO strings with milliseconds, `...sssZ` |
| `context` | `source_sha256`, `study_id`, `baseline_date`, `visit_count` |
| `summary_note` | Free text for the review round |
| `items` | Ordered records for the core's complete `preflight.review_hints` |
| `sha256` | Lowercase SHA-256 of the canonical payload's UTF-8 bytes |

Each item has exactly `id`, `hint`, `status`, `note`, `updated_at`, in that order.
IDs are `hint-1`, `hint-2`, etc., reflecting the core's current order. `hint`
retains exactly `code`, `message`, `source`, `field`, `line`, `column`, `visit_id`,
`lesion_id` in that order. No clinical text is generated or reclassified by the
note layer. `status` is `pending` or `reviewed`; the interface presents the latter
as “已查看” / “Viewed”, with no implication that the issue is resolved.

The input fingerprint is the same one used by the workbench's report/print
view: SHA-256 over UTF-8 `JSON.stringify([study_json, followup_csv])`, preserving
the supplied raw strings. It is not the native bundle's individual raw-file hash.
Formatting-only changes also require a matching source pair. Notes do not embed
the source inputs; preserve those separately as paired files, a draft or a
portable review session.

For the payload hash, construct the fields in the order above, omit `sha256`,
and use compact JavaScript `JSON.stringify`. Nested context, item and hint key
order is as stated above. JSON indentation and object-key order in an imported
file do not affect validation: the reader first reconstructs the canonical
payload. Unknown fields, malformed timestamps, invalid statuses, missing fields,
reordered/missing items or changed hint contents are rejected.

After checking the hash, the reader checks the current raw-input fingerprint
and reruns the existing MoonBit editor/preflight boundary. Context and every
hint must exactly match that output before notes can be applied. A recomputed
unkeyed digest cannot make a changed core hint match the current input. The
digest still does not authenticate a reviewer or producer; anyone can edit
human comments and recompute a digest. Device timestamps are not trusted signing
times. Local edits clamp an earlier device time to the record's latest update.

## Limits and storage

The workbench permits up to 1000 hint records, 2000 UTF-16 code units per item
note, 6000 for the round summary, 100000 per hint text field, and 4 MiB per
encoded/imported JSON file. These are resource limits, not medical rules.
No hint is silently dropped when the limit is exceeded. Pending entries may
contain notes, and viewed entries may have empty notes.

“保存核查进度” explicitly writes one record to the dedicated local-storage key
`impart563.lesion-followup.review-notes.v1`. It does not save measurement inputs
or update the existing draft/session keys. Restore requires the matching inputs
to be loaded first. Clearing this local copy leaves the current in-memory record
and unrelated storage untouched. This storage is not encrypted, and is scoped
to the browser origin just like existing workbench drafts.

Input changes retain the old note snapshot in read-only form. It remains
available as a JSON backup, but cannot be edited, saved as the current local
record, or exported as a current HTML/Markdown explanation. Restoring the exact
original source pair re-enables that snapshot. Starting a new round explicitly
creates fresh pending items for the current input. No automatic carry-over of
viewed states between changed inputs occurs.

Imports and hash generation capture an operation revision; a newer input edit,
note edit or file selection prevents the older asynchronous operation from
applying its result. Failed loads preserve current notes and measurement inputs.

## Independent explanation documents

HTML and Markdown exports contain the study/baseline context, fingerprint,
viewed/pending counts, every original hint with source locations, comments,
round summary and device timestamps. They are separate human-review documents;
the clinical report, core audit JSON/CSV and five-file integrity bundle retain
their existing contracts and contents. Existing review sessions remain version 1
and do not silently embed these notes.

HTML escapes all untrusted text, uses a restrictive CSP, and includes a simple
print stylesheet. Markdown encodes punctuation as numeric character references
so user text stays literal under CommonMark, including raw HTML, links, heading
markers and code fences. The documents preserve pending work explicitly and
include target-only and human-viewing scope statements. Neither export is a
signature, clinical clearance or overall-response report.

Run `python scripts/acceptance.py` for native preflight parity, independent
Python/Node payload hashes, strict malformed-file rejection, unchanged clinical
evidence and bilingual document checks. Browser file-chooser, persistence and
staleness checks are recorded in [acceptance](acceptance.md).
