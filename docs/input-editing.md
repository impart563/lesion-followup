# Visit editing and input history

The workbench performs whole-visit edits on the same in-memory input used by
the existing MoonBit preflight and replay. No medical rule, input schema or
public MoonBit API is added. Results still concern target lesions only.

## Whole-visit operations

The current input must pass structural preflight; review hints do not block an
operation. The editor prepares a separate candidate, runs native-equivalent
MoonBit preflight and displays a summary before explicit application.

- Append requires a unique visit ID, date and acquisition identifier. One row
  is added for each ordered baseline target with `missing`, empty diameter and
  empty note. Prior measurements, notes and response categories are not copied.
- Update applies the selected visit's ID, date and acquisition identifier to
  every observation belonging to that ID. Target IDs, states, diameters and
  reader notes stay identical. Other visits' cells stay identical.
- Remove deletes exactly the observations of the selected visit. Removing the
  last visit is allowed; the existing no-followup preflight then applies.

The core rejects invalid dates, duplicate IDs, inconsistent rows and dates
outside the existing order. The editor does not sort, repair or shift visits.
Editing an acquisition identifier does not establish clinical comparability;
the existing hints and NE rules still apply.

Applying an operation preserves the study JSON string exactly. The CSV is
serialized with the existing table writer, which uses the fixed header and LF
record separators. All retained cell contents, including quoted Unicode and
embedded CR/LF notes, are preserved. This is a deliberate edit, so its raw-input
fingerprint may change even when only CSV formatting differs.

Preview exposes only derived ID/date/observation and preflight counts. It keeps
its own candidate snapshot. Form changes, another preview or any workspace
revision withdraw the prior apply action; errors never partially change input.
An accepted edit retracts earlier reports, comparisons and handoff previews.
Input-bound human notes follow the existing stale-record behavior.

## Current-input undo and redo

History contains exact `study_json` and `followup_csv` strings. Both raw-file
and table edits participate, including incomplete or invalid text. Continuous
typing in the same focused field is one step; leaving that field settles the
group. Whole-visit edits and row/target additions or removals are separate steps.
Undo and redo reparse the restored strings and rerun preflight. They do not
restore old rendered reports; reports must be regenerated from current input.

Only current input is restored. The selected language, fixed comparison version
and independently managed human notes are not part of input history. Restoring
the exact original input can make its existing note snapshot current again.
Importing inputs, examples, drafts, sessions, batch records or complete handoffs
starts a new history, preventing undo into the previous externally loaded case.
Updating the table from edited raw text keeps the current case's history.

New edits after undo discard the redo branch. Returned snapshots cannot mutate
the retained history. Retention is bounded to 40 undo steps and an 8 MiB UTF-8
budget over JSON-encoded source pairs. The oldest snapshots are released first.
If the current input alone exceeds the budget it remains editable, but cannot
retain a prior snapshot within that budget; the UI reports released history.
No history is saved in local storage, drafts, sessions or handoff files. Closing
or refreshing the page loses it. Explicit file export and draft save remain the
ways to preserve work between sessions.

`python scripts/acceptance.py` checks one-to-five-target creation, complete
metadata updates, deletion, invalid/stale operation rejection, exact raw
history restoration and native preflight/five-format report equivalence.
