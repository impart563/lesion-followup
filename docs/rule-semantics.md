# Rule profile and implementation boundaries

Profile: `recist-1.1-target-subset-1`, report schema version 1.

This is a review calculation for a fixed, manually selected CT target set.
Outputs refer to that target group only. Clinical readers remain responsible
for target eligibility, anatomical matching, canonical organ groups and
acquisition comparability. New lesions, non-target disease and trial-specific
confirmation can change the overall result independently of the target sum.

## Exact arithmetic

Sizes use signed `Int` values at 0.1 mm precision. Validation requires each
diameter to lie between 0 and 10000 inclusive, with at most five targets. The
largest supported sum is 50000 tenths mm; all threshold cross-products and
basis-point numerators fit a 32-bit signed integer. Validation runs before
aggregation, including for values supplied directly through the public API.

Let `S` be the current complete sum, `B` the baseline sum, and `N` the smallest
sum from baseline or an earlier eligible visit. The current visit is compared
against the **prior** nadir and only then may establish a new nadir.

| Target outcome | Implemented comparison |
| --- | --- |
| CR | Every non-nodal target is absent/zero and each target node has short axis <100 tenths mm |
| PD | `5*S >= 6*N` **and** `S-N >= 50` tenths mm |
| PR | PD does not apply and `10*S <= 7*B` |
| SD | None of the above, and no history/context review gate applies |
| NE | Incomplete measurements, changed technique, or a documented context gate |

CR has priority when all targets meet resolution criteria; a still-visible
normal-size target node can therefore contribute a nonzero sum during target
CR. PD has priority over PR. The comparisons include equality where shown.
The PR comparison never changes its reference to the nadir.

Changes in basis points are `(current-reference)*10000/reference`, truncated
toward zero for display. A zero reference yields an unavailable percentage, not
infinity. Percentages never select a category. When nadirs tie, the earlier
reference is retained. Missing or NE visits never lower the nadir.

## Observations and track structure

An explicit `too_small` observation means the reader sees a target but cannot
measure it reproducibly; the effective size is 5.0 mm and a `default_5mm` finding
is retained. Actual measurements below 5.0 mm are used as supplied. `absent`
means disappeared and has effective size zero. `missing`, omitted targets and
reader-supplied `not_evaluable` observations have no effective diameter. Any such
gap makes this implementation conservatively return NE for the whole visit;
it does not infer a response from a partial target set even if a clinician could
justify doing so in a specific case.

The baseline set contains one to five eligible targets and at most two per
canonical organ group. All lymph nodes belong to `lymph_nodes`. Paired-organ
normalization is the caller's responsibility; free-text anatomical aliases
are not reconciled automatically. Baseline minima assume CT slices <=5.0 mm.
MRI, chest X-ray and thicker slices require a different implementation profile.

Dates must be valid Gregorian dates in 0001–9999 and strictly increase after
baseline; visits on the same date are unsupported. The library does not sort,
merge, deduplicate or interpolate visits. IDs must be nonblank, trimmed, at most
128 UTF-16 code units and contain no ASCII control characters. Duplicate visit
IDs, reused baseline ID, duplicate target measurements, unknown targets and
out-of-range measurements reject the entire input rather than emit a partial
review. Input arrays are copied before evaluating the trajectory.

## Conservative history gates

- **After target PD:** subsequent observations remain available but receive NE;
  response continuation after progression is outside this version.
- **After target CR:** a non-nodal target becoming visible, or a target node
  returning to >=10.0 mm, requires overall-response context. The current and
  remaining visits receive NE. Target-only CR does not establish overall CR.
- **After target PR:** if a later visit loses the baseline PR size threshold
  without meeting PD, the current and remaining visits receive NE. Confirmation
  and persistence rules require trial/overall-response context not represented
  in this input model. The library does not silently relabel a confirmed
  response SD.

If one target disappears and reappears while the target group has not reached
CR, it is retained under its original identity and contributes its diameter to
the sum. Target identities must not be replaced with new IDs mid-track.
Splitting/coalescence, local treatment, biopsy effects and ambiguous recurrence
need reader review; they are not automatically resolved by this engine.

An NE value means the configured subset could not produce a category, not that
progression or other clinically significant findings are absent. There is no
overall response, confirmed response, best overall response, iRECIST, treatment
decision, image segmentation, patient-data service or hospital integration.

## Primary sources and material ownership

Checked 2026-10-24:

- Eisenhauer et al., *New response evaluation criteria in solid tumours:
  Revised RECIST guideline (version 1.1)*, European Journal of Cancer 45 (2009),
  DOI [10.1016/j.ejca.2008.10.026](https://doi.org/10.1016/j.ejca.2008.10.026).
  Sections 3–4 and target-measurement notes inform the implemented numeric rules.
- [RECIST Working Group: RECIST 1.1 and clarifications](https://recist.eortc.org/recist-1-1/).
  The clarifications motivate separate baseline/nadir references and conservative
  handling of response history and incomplete assessments.
- [RECIST website ownership and reproduction terms](https://recist.eortc.org/privacy-policy/).

Code, tests, explanatory text, SVG and examples in this repository are original
implementations. Official documents, forms, logos and illustrations are linked
rather than copied. Naming this rule profile does not imply endorsement by EORTC
or the RECIST Working Group. Software checks are not independent clinical review.
