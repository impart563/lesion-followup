///|
/// The measurement axis is longest diameter for non-nodal targets and short
/// axis for lymph nodes. Organ names are canonical groups supplied by the caller.
pub(all) enum LesionKind {
  NonNodal
  LymphNode
} derive(Debug, Eq)

///|
/// Diameters use tenths of a millimetre; 200 represents 20.0 mm.
pub(all) struct TargetLesion {
  id : String
  organ : String
  kind : LesionKind
  baseline_tenths_mm : Int
} derive(Debug, Eq)

///|
/// A fixed, caller-selected target set measured by CT with slices <= 5 mm.
/// This record does not certify target selection or assess non-target disease.
pub(all) struct Study {
  id : String
  baseline_date : String
  technique_id : String
  slice_thickness_tenths_mm : Int
  targets : Array[TargetLesion]
} derive(Debug, Eq)
