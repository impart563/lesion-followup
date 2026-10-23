///|
/// Target-lesion categories only; these are never overall response categories.
pub(all) enum TargetResponse {
  CR
  PR
  SD
  PD
  NE
} derive(Debug, Eq)

///|
pub(all) enum IssueCode {
  InvalidStudy
  InvalidDate
  InvalidTarget
  DuplicateId
  TooManyTargets
  TooManyPerOrgan
  InvalidMeasurement
  UnknownTarget
  InvalidVisitOrder
} derive(Debug, Eq)

///|
pub(all) struct InputIssue {
  code : IssueCode
  message : String
  visit_id : String?
  lesion_id : String?
} derive(Debug, Eq)

///|
pub(all) struct ResolvedMeasurement {
  lesion_id : String
  kind : @lesion.LesionKind
  baseline_tenths_mm : Int
  observation : @visit.Observation
  effective_tenths_mm : Int?
} derive(Debug, Eq)

///|
/// Codes are stable machine-readable reasons; messages describe the calculation.
pub(all) struct Finding {
  code : String
  lesion_id : String?
  message : String
} derive(Debug, Eq)

///|
/// The nadir fields refer to the complete eligible visit BEFORE this assessment.
/// Basis points are display-only truncated percentages: -3000 means -30.00%.
pub(all) struct VisitAssessment {
  visit_id : String
  date : String
  response : TargetResponse
  sum_tenths_mm : Int?
  baseline_sum_tenths_mm : Int
  nadir_sum_tenths_mm : Int
  nadir_visit_id : String
  baseline_change_basis_points : Int?
  nadir_change_basis_points : Int?
  measurements : Array[ResolvedMeasurement]
  findings : Array[Finding]
} derive(Debug, Eq)

///|
pub(all) struct Trajectory {
  study : @lesion.Study
  visits : Array[@visit.Visit]
  assessments : Array[VisitAssessment]
} derive(Debug, Eq)
