///|
/// CSV locations are one-based physical line/column (Unicode code points).
/// JSON schema diagnostics use field paths and have no line/column location.
pub(all) struct Diagnostic {
  code : String
  message : String
  line : Int?
  column : Int?
  field : String?
} derive(Debug, Eq)

///|
pub extend Diagnostic with @debug.Debug::{to_repr}

///|
pub extend Diagnostic with Eq::{equal, not_equal}

///|
fn diagnostic(
  code : String,
  message : String,
  line? : Int,
  column? : Int,
  field? : String,
) -> Diagnostic {
  { code, message, line, column, field, }
}

///|
/// Parse an unsigned plain decimal exactly at 0.1 mm precision, without rounding.
/// The accepted software range is 0.0 through 1000.0 mm.
pub fn parse_diameter_mm(text : String) -> Result[Int, String] {
  if text.is_empty() {
    return Err("Diameter is empty.")
  }
  let mut whole = 0
  let mut fraction = 0
  let mut seen_dot = false
  let mut fraction_digits = 0
  let mut whole_digits = 0
  for character in text {
    if character == '.' && !seen_dot {
      if whole_digits == 0 {
        return Err("Diameter needs a digit before the decimal point.")
      }
      seen_dot = true
    } else {
      let digit = character.to_int() - 48
      if digit < 0 || digit > 9 {
        return Err(
          "Use an unsigned plain decimal without whitespace or exponent.",
        )
      }
      if seen_dot {
        fraction_digits += 1
        if fraction_digits > 1 {
          return Err(
            "At most one decimal place is accepted; values are never rounded.",
          )
        }
        fraction = digit
      } else {
        whole_digits += 1
        if whole_digits > 4 {
          return Err("Diameter exceeds the supported decimal width.")
        }
        whole = whole * 10 + digit
      }
    }
  }
  if seen_dot && fraction_digits == 0 {
    return Err("Decimal point must be followed by one digit.")
  }
  let value = whole * 10 + fraction
  if value > 10000 {
    Err("Diameter exceeds the 1000.0 mm software limit.")
  } else {
    Ok(value)
  }
}

///|
pub fn format_diameter_mm(tenths : Int) -> String {
  let sign = if tenths < 0 { "-" } else { "" }
  let value = if tenths < 0 { -tenths.to_int64() } else { tenths.to_int64() }
  "\{sign}\{value / 10}.\{value % 10}"
}
