///|
pub fn TargetResponse::code(self : TargetResponse) -> String {
  match self {
    CR => "CR"
    PR => "PR"
    SD => "SD"
    PD => "PD"
    NE => "NE"
  }
}

///|
pub fn IssueCode::code(self : IssueCode) -> String {
  match self {
    InvalidStudy => "invalid_study"
    InvalidDate => "invalid_date"
    InvalidTarget => "invalid_target"
    DuplicateId => "duplicate_id"
    TooManyTargets => "target_count"
    TooManyPerOrgan => "organ_target_count"
    InvalidMeasurement => "invalid_measurement"
    UnknownTarget => "unknown_target"
    InvalidVisitOrder => "visit_order"
  }
}
