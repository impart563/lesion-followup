# Complete review handoff

A handoff ZIP combines a portable review session, a native-compatible current
report bundle and optional human review notes. It is a distinct format from the
existing five-file report ZIP and batch report archive. Clinical results cover
target lesions only. Synthetic examples do not establish clinical validation.

## Version 1 layout

```text
handoff.json
session.json
review-notes.json           optional
report/report.html
report/audit.json
report/audit.csv
report/chart.svg
report/manifest.json
```

Files must have these exact root-relative names. Additional files, missing
mandatory files, wrapper folders, duplicate paths and case collisions are
rejected. Empty ZIP directory records may be present and are ignored by the
existing archive reader; no files are extracted to disk.

`session.json` retains the existing version-1 session contract: both original
input strings in `current`, optional `before`, language and its canonical
SHA-256. Its `saved_at` equals the handoff's `created_at`. The reference version
may contain unfinished input, as existing sessions permit. It is preserved as
context; the packaged clinical reports and replay check concern `current`.
Reference comparison remains a separate action after loading.

Optional `review-notes.json` retains the existing version-1 note contract. Its
input fingerprint, context and every core hint must match `current`; a stale
note record cannot be bound to another input by editing the outer manifest.
Viewed/pending states and comments remain independent of clinical categories.
Unchecked note inclusion omits this file explicitly.

The five files under `report/` are returned by the existing MoonBit bundle
action for `current` and the session language. No report text is rewritten by
the handoff layer. The report subdirectory can be passed directly to the
native CLI after ordinary extraction:

```sh
moon run --target native cmd/demo -- --verify-bundle PATH/report --format json
```

## Outer manifest

`handoff.json` has exactly `schema_version`, `kind`, `scope`, `created_at`,
`files`, `sha256`. The first five form the canonical payload in that order:

- Numeric version `1`, kind `lesion-followup-handoff`, scope
  `target_lesions_only`, and canonical millisecond UTC timestamp `...sssZ`.
- Each file descriptor has exactly `name`, `byte_length`, `sha256`, in that order.
  Length is the nonnegative UTF-8 byte count; SHA-256 is lowercase hexadecimal.
- Descriptor order is `session.json`, optional `review-notes.json`, followed by
  `report/report.html`, `report/audit.json`, `report/audit.csv`, `report/chart.svg`,
  `report/manifest.json`. The outer manifest is not its own leaf descriptor.
- The outer digest hashes the UTF-8 compact JavaScript `JSON.stringify` of the
  canonical payload. Parsing reconstructs this order before checking the hash,
  so container key order or ZIP entry order need not be identical.

The file hashes cover every actual file except the outer manifest, whose
canonical fields are covered by its payload hash. These unkeyed digests check
consistency, not producer identity, consent or authenticity. Timestamps come
from the exporting device and are not trusted signing times.

## Receive and restore

Reception first applies the existing bounded UTF-8 ZIP reader, then checks the
strict outer schema, exact file set, lengths, leaf hashes and canonical digest.
It checks the nested session and original report manifest with the existing
MoonBit verifier. It then regenerates all five report files from `current` and
requires exact text equality, including the report manifest and raw-input
fingerprints. An internally consistent bundle from another track, changed
language or incompatible rendering version is rejected. This is a software
reproduction check, not a clinical-validity claim.

Optional notes are verified against the same current source strings and
regenerated core hints. Preview displays only derived metadata: study/baseline,
visit and hint counts, presence of reference/notes, note progress, language,
fingerprints and packing time. Imported HTML and SVG are not executed or shown
as active content. Current work is untouched until the explicit load action.

Loading uses the fully verified in-memory snapshot in one synchronous apply:
current and reference sources, language and optional notes. With no included
notes, the old in-memory note record and its editor contents are cleared.
Previously generated reports are retracted and can be regenerated normally.
No local-storage draft or saved note copy is automatically overwritten.

Every inspection captures a workspace revision and a file-selection token.
Source, reference, language or note edits invalidate the prior load operation;
another file selection or inspection also withdraws it. Failed, superseded or
interrupted reads never partially apply data. A preview is a copy of derived
metadata, while the receiver retains its own complete validated snapshot.

## Resource limits and compatibility

The handoff uses the existing ZIP limits: 64 MiB compressed/total expanded,
16 MiB per entry and 128 entries, stored or DEFLATE including data descriptors.
The session is limited to 2 MiB, optional notes to 4 MiB, and outer manifest to
32 KiB. Unsupported/encrypted/ZIP64/symlink archives and unsafe paths retain the
archive reader's existing rejection rules. These are software resource limits,
not medical thresholds. Export uses stored ZIP, fixed archive timestamps and
UTF-8 strings; a supplied fixed packing timestamp produces deterministic bytes.

Handoff data includes original measurement text and selected comments. ZIP
storage is not encryption; manage these files with the same access controls as
the underlying material. Existing session, note, report and batch formats stay
separate and compatible. Formal GitHub/Mooncakes publication is independent of
this development feature.

Run `python scripts/acceptance.py` for bilingual native-file parity, independent
Python manifest verification, stored/DEFLATE interchange, malformed and mixed
archives, complete report replay, and receiver revision/atomic-apply checks.
