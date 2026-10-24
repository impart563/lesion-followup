///|
pub(all) struct InputChange {
  visit_id : String
  lesion_id : String?
  field : String
  before : String?
  after : String?
} derive(Debug, Eq)

///|
pub(all) struct VisitImpact {
  visit_id : String
  before : VisitAssessment?
  after : VisitAssessment?
} derive(Debug, Eq)

///|
pub(all) struct TrackRevision {
  study_id : String
  changes : Array[InputChange]
  impacts : Array[VisitImpact]
} derive(Debug, Eq)

///|
pub extend InputChange with @debug.Debug::{to_repr}

///|
pub extend InputChange with Eq::{equal, not_equal}

///|
pub extend VisitImpact with @debug.Debug::{to_repr}

///|
pub extend VisitImpact with Eq::{equal, not_equal}

///|
pub extend TrackRevision with @debug.Debug::{to_repr}

///|
pub extend TrackRevision with Eq::{equal, not_equal}
