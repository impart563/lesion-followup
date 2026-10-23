///|
fn response_color(response : @evidence.TargetResponse) -> String {
  match response {
    CR => "#6f4fa0"
    PR => "#247b68"
    SD => "#34748a"
    PD => "#b5473e"
    NE => "#787b83"
  }
}

///|
/// Self-contained SVG: target sum, baseline and baseline-minus-30% guides.
/// NE visits break the line and are never plotted as a zero-diameter result.
pub fn render_trajectory_svg(trajectory : @evidence.Trajectory) -> String {
  render_trajectory_svg_in(trajectory, English)
}

///|
/// Localized presentation; input-derived text and machine codes are preserved.
pub fn render_trajectory_svg_in(
  trajectory : @evidence.Trajectory,
  language : ReportLanguage,
) -> String {
  let mut baseline = 0
  for target in trajectory.study.targets {
    baseline += target.baseline_tenths_mm
  }
  let mut maximum = baseline
  for a in trajectory.assessments {
    if a.sum_tenths_mm is Some(sum) && sum > maximum {
      maximum = sum
    }
  }
  maximum = maximum * 5 / 4 + 1
  let y = (value : Int) => 30 + (maximum - value) * 210 / maximum
  let out = StringBuilder()
  out.write_string(
    tr(
      language, "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1000 320\" role=\"img\" aria-labelledby=\"chart-title chart-desc\"><title id=\"chart-title\">Target diameter sums</title><desc id=\"chart-desc\">Baseline and ordered follow-up target sums. Not-evaluable visits break the line. The dashed lower guide is a 30 percent baseline reduction, not an overall-response threshold.</desc><rect width=\"1000\" height=\"320\" fill=\"#fffdf9\"/>",
      "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1000 320\" role=\"img\" aria-labelledby=\"chart-title chart-desc\"><title id=\"chart-title\">靶病灶直径总和</title><desc id=\"chart-desc\">基线与有序随访的靶病灶总和。NE 随访断线。下方虚线表示基线减少 30%，不代表整体疗效阈值。</desc><rect width=\"1000\" height=\"320\" fill=\"#fffdf9\"/>",
    ),
  )
  for
    (value, label, color) in [
      (baseline, tr(language, "Baseline", "基线"), "#7c8390"),
      (
        baseline * 7 / 10,
        tr(language, "Baseline -30%", "基线 -30%"),
        "#b1b7ba",
      ),
    ] {
    out.write_string(
      "<line x1=\"70\" y1=\"\{y(value)}\" x2=\"930\" y2=\"\{y(value)}\" stroke=\"\{color}\" stroke-dasharray=\"5 5\"/><text x=\"74\" y=\"\{y(value) - 8}\" fill=\"#68717c\" font-size=\"11\">\{label}: \{format_diameter_mm(value)} mm</text>",
    )
  }
  out.write_string(
    tr(
      language,
      "<line x1=\"70\" y1=\"260\" x2=\"930\" y2=\"260\" stroke=\"#d9dfe0\"/><text x=\"18\" y=\"25\" fill=\"#68717c\" font-size=\"12\">mm</text><circle cx=\"70\" cy=\"\{y(baseline)}\" r=\"5\" fill=\"#374357\"/><text x=\"70\" y=\"283\" text-anchor=\"middle\" font-size=\"11\" fill=\"#68717c\">Baseline</text>",
      "<line x1=\"70\" y1=\"260\" x2=\"930\" y2=\"260\" stroke=\"#d9dfe0\"/><text x=\"18\" y=\"25\" fill=\"#68717c\" font-size=\"12\">mm</text><circle cx=\"70\" cy=\"\{y(baseline)}\" r=\"5\" fill=\"#374357\"/><text x=\"70\" y=\"283\" text-anchor=\"middle\" font-size=\"11\" fill=\"#68717c\">基线</text>",
    ),
  )
  let mut previous : (Int, Int)? = Some((70, y(baseline)))
  for i, a in trajectory.assessments {
    let x = 70 + (i + 1) * 840 / (trajectory.assessments.length() + 1)
    let color = response_color(a.response)
    if a.response != NE && a.sum_tenths_mm is Some(sum) {
      let py = y(sum)
      if previous is Some((px, previous_y)) {
        out.write_string(
          "<line x1=\"\{px}\" y1=\"\{previous_y}\" x2=\"\{x}\" y2=\"\{py}\" stroke=\"#456778\" stroke-width=\"2.5\"/>",
        )
      }
      out.write_string(
        "<circle cx=\"\{x}\" cy=\"\{py}\" r=\"6\" fill=\"\{color}\" tabindex=\"0\"><title>" +
        html_escape(a.visit_id) +
        ": " +
        format_diameter_mm(sum) +
        " mm / " +
        a.response.code() +
        "</title></circle>",
      )
      previous = Some((x, py))
    } else {
      out.write_string(
        "<path d=\"M \{x - 5} 240 l 10 10 m -10 0 l 10 -10\" stroke=\"\{color}\" stroke-width=\"2\"><title>" +
        html_escape(a.visit_id) +
        tr(
          language, ": NE; excluded from trend line</title></path>", ": NE；不进入总和趋势线</title></path>",
        ),
      )
      previous = None
    }
    out.write_string(
      "<text x=\"\{x}\" y=\"283\" text-anchor=\"middle\" fill=\"#485366\" font-size=\"11\">V\{i + 1}</text><text x=\"\{x}\" y=\"300\" text-anchor=\"middle\" fill=\"\{color}\" font-size=\"11\">" +
      a.response.code() +
      "</text>",
    )
  }
  out.write_string("</svg>\n")
  out.to_string()
}
