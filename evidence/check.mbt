///|
/// Exact scaled-integer comparison for review. `active` distinguishes considered
/// criteria from criteria skipped by an earlier gate. Unavailable operands stay null.
pub(all) struct RuleCheck {
  code : String
  lesion_id : String?
  left : Int?
  operator : String
  right : Int
  passed : Bool?
  active : Bool
} derive(Debug, Eq)

///|
pub extend RuleCheck with @debug.Debug::{to_repr}

///|
pub extend RuleCheck with Eq::{equal, not_equal}
