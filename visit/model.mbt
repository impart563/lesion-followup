///|
/// Missing is different from Absent. TooSmallToMeasure means the reader has
/// explicitly identified a visible target without a reproducible measurement.
pub(all) enum Observation {
  Measured(Int)
  Absent
  TooSmallToMeasure
  Missing
  NotEvaluable(String)
} derive(Debug, Eq)

///|
pub(all) struct Measurement {
  lesion_id : String
  observation : Observation
} derive(Debug, Eq)

///|
/// Visits must be in strictly increasing Gregorian YYYY-MM-DD order.
pub(all) struct Visit {
  id : String
  date : String
  technique_id : String
  measurements : Array[Measurement]
} derive(Debug, Eq)
