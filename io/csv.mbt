///|
priv struct CsvCell {
  text : String
  line : Int
  column : Int
}

///|
fn csv_rows(text : String) -> Result[Array[Array[CsvCell]], Array[Diagnostic]] {
  let chars = text.to_array()
  let rows = []
  let mut row = []
  let builder = StringBuilder()
  let mut i = if chars.length() > 0 && chars[0] == '\u{feff}' { 1 } else { 0 }
  let mut line = 1
  let mut column = 1
  let mut start_line = 1
  let mut start_column = 1
  let mut quoted = false
  let mut closed = false
  let mut active = false
  while i < chars.length() {
    let c = chars[i]
    if quoted {
      if c == '"' {
        if i + 1 < chars.length() && chars[i + 1] == '"' {
          builder.write_char('"')
          i += 2
          column += 2
          continue
        }
        quoted = false
        closed = true
      } else {
        builder.write_char(c)
        if c == '\r' {
          if i + 1 < chars.length() && chars[i + 1] == '\n' {
            builder.write_char('\n')
            i += 1
          }
          line += 1
          column = 0
        } else if c == '\n' {
          line += 1
          column = 0
        }
      }
    } else if c == ',' || c == '\n' || c == '\r' {
      row.push({
        text: builder.to_string(),
        line: start_line,
        column: start_column,
      })
      builder.reset()
      closed = false
      active = false
      if c != ',' {
        rows.push(row)
        row = []
        if c == '\r' && i + 1 < chars.length() && chars[i + 1] == '\n' {
          i += 1
        }
        line += 1
        column = 0
      }
      start_line = line
      start_column = column + 1
    } else if closed {
      return Err([
        diagnostic(
          "csv_quoting",
          "Only a delimiter or line ending may follow a closing quote.",
          line~,
          column~,
        ),
      ])
    } else if c == '"' {
      if active {
        return Err([
          diagnostic(
            "csv_quoting",
            "A quote may only open at the beginning of a field.",
            line~,
            column~,
          ),
        ])
      }
      quoted = true
      active = true
    } else {
      builder.write_char(c)
      active = true
    }
    i += 1
    column += 1
  }
  if quoted {
    return Err([
      diagnostic(
        "csv_quoting",
        "Unterminated quoted field.",
        line=start_line,
        column=start_column,
      ),
    ])
  }
  if active || closed || !row.is_empty() {
    row.push({
      text: builder.to_string(),
      line: start_line,
      column: start_column,
    })
    rows.push(row)
  }
  Ok(rows)
}

///|
fn cell_error(
  code : String,
  message : String,
  cell : CsvCell,
  field : String,
) -> Diagnostic {
  diagnostic(code, message, line=cell.line, column=cell.column, field~)
}

///|
/// Decode editable text cells using the clinical parser's quoting and locations.
/// Only CSV shape is checked here; clinical state/precision validation remains
/// in parse_followup_csv and preflight_inputs. The header is not returned.
pub fn parse_followup_cells(
  text : String,
) -> Result[Array[Array[String]], Array[Diagnostic]] {
  let rows = match csv_rows(text) {
    Ok(rows) => rows
    Err(errors) => return Err(errors)
  }
  let header = [
    "visit_id", "date", "technique_id", "lesion_id", "state", "diameter_mm", "note",
  ]
  if rows.is_empty() || rows[0].map(c => c.text) != header {
    return Err([
      diagnostic(
        "csv_header",
        "Expected header: " + header.join(","),
        line=1,
        column=1,
      ),
    ])
  }
  let cells = []
  for row in rows[1:] {
    if row.length() != header.length() {
      return Err([
        diagnostic(
          "csv_columns",
          "Expected seven fields.",
          line=row[0].line,
          column=1,
        ),
      ])
    }
    cells.push(row.map(c => c.text))
  }
  Ok(cells)
}

///|
/// Long-form CSV: one target observation per row. Visit rows must be contiguous;
/// the parser preserves order and rejects partial results on any parse error.
pub fn parse_followup_csv(
  text : String,
) -> Result[Array[@visit.Visit], Array[Diagnostic]] {
  let rows = match csv_rows(text) {
    Ok(rows) => rows
    Err(errors) => return Err(errors)
  }
  let header = [
    "visit_id", "date", "technique_id", "lesion_id", "state", "diameter_mm", "note",
  ]
  if rows.is_empty() {
    return Err([
      diagnostic(
        "csv_header",
        "CSV is empty; a header is required.",
        line=1,
        column=1,
      ),
    ])
  }
  if rows[0].length() != header.length() || rows[0].map(c => c.text) != header {
    return Err([
      diagnostic(
        "csv_header",
        "Expected header: " + header.join(","),
        line=1,
        column=1,
      ),
    ])
  }
  let visits : Array[@visit.Visit] = []
  let errors = []
  let closed_ids : Map[String, Bool] = Map([])
  for row_index in 1..<rows.length() {
    let row = rows[row_index]
    if row.length() != header.length() {
      errors.push(
        diagnostic(
          "csv_columns",
          "Expected seven fields.",
          line=row[0].line,
          column=1,
        ),
      )
      continue
    }
    let id = row[0].text
    let date = row[1].text
    let technique = row[2].text
    let lesion_id = row[3].text
    let state = row[4].text
    let diameter = row[5].text
    let note = row[6].text
    let observation : @visit.Observation = match state {
      "measured" => {
        if !note.is_empty() {
          errors.push(
            cell_error(
              "csv_state",
              "Measured rows must have an empty note.",
              row[6],
              "note",
            ),
          )
        }
        match parse_diameter_mm(diameter) {
          Ok(value) => Measured(value)
          Err(message) => {
            errors.push(
              cell_error("csv_diameter", message, row[5], "diameter_mm"),
            )
            Missing
          }
        }
      }
      "absent" | "too_small" | "missing" | "not_evaluable" => {
        if !diameter.is_empty() {
          errors.push(
            cell_error(
              "csv_state",
              "Only measured rows may contain diameter_mm.",
              row[5],
              "diameter_mm",
            ),
          )
        }
        if state == "not_evaluable" {
          if note.is_blank() {
            errors.push(
              cell_error(
                "csv_state",
                "not_evaluable requires a reason in note.",
                row[6],
                "note",
              ),
            )
          }
          NotEvaluable(note)
        } else {
          if !note.is_empty() {
            errors.push(
              cell_error(
                "csv_state",
                "Only not_evaluable rows may contain a note.",
                row[6],
                "note",
              ),
            )
          }
          match state {
            "absent" => Absent
            "too_small" => TooSmallToMeasure
            _ => Missing
          }
        }
      }
      _ => {
        errors.push(
          cell_error(
            "csv_state",
            "Use measured, absent, too_small, missing or not_evaluable.",
            row[4],
            "state",
          ),
        )
        Missing
      }
    }
    let measurement : @visit.Measurement = { lesion_id, observation, }
    let last_index = visits.length() - 1
    if last_index >= 0 && visits[last_index].id == id {
      let previous = visits[last_index]
      if previous.date != date || previous.technique_id != technique {
        errors.push(
          cell_error(
            "csv_metadata",
            "Rows of one visit must repeat identical date and technique_id.",
            row[0],
            "visit_id",
          ),
        )
      }
      previous.measurements.push(measurement)
    } else {
      if last_index >= 0 {
        closed_ids[visits[last_index].id] = true
      }
      if closed_ids.contains(id) {
        errors.push(
          cell_error(
            "csv_visit_order",
            "Rows for a completed visit must not reappear.",
            row[0],
            "visit_id",
          ),
        )
      }
      visits.push({
        id,
        date,
        technique_id: technique,
        measurements: [measurement],
      })
    }
  }
  if errors.is_empty() {
    Ok(visits)
  } else {
    Err(errors)
  }
}
