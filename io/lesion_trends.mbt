///|
/// Individual observations remain visible even in an NE visit. NE visits and
/// missing observations break connecting lines; only measured/default values plot.
pub fn render_lesion_trends_svg(
  trajectory : @evidence.Trajectory,
  language? : ReportLanguage = English,
) -> String {
  let out = StringBuilder()
  let height = trajectory.study.targets.length() * 260
  out.write_string(
    "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1000 \{height}\" role=\"img\" aria-labelledby=\"lesion-trends-title\"><title id=\"lesion-trends-title\">" +
    tr(language, "Individual target observations", "单病灶观察趋势") +
    "</title>",
  )
  for index, target in trajectory.study.targets {
    let mut maximum = target.baseline_tenths_mm
    for a in trajectory.assessments {
      for m in a.measurements {
        if m.lesion_id == target.id &&
          m.effective_tenths_mm is Some(v) &&
          v > maximum {
          maximum = v
        }
      }
    }
    maximum = maximum * 5 / 4 + 1
    let top = index * 260
    let y = (value : Int) => top + 55 + (maximum - value) * 140 / maximum
    out.write_string(
      "<g data-lesion-id=\"" +
      html_escape(target.id) +
      "\"><text x=\"30\" y=\"\{top + 25}\" font-size=\"14\" fill=\"#263348\">" +
      html_escape(target.id) +
      " · " +
      axis_label(target.kind, language) +
      " / mm</text><line x1=\"70\" y1=\"\{top + 205}\" x2=\"930\" y2=\"\{top + 205}\" stroke=\"#d9dfe0\"/>",
    )
    out.write_string(
      "<text x=\"60\" y=\"\{top + 59}\" text-anchor=\"end\" font-size=\"11\" fill=\"#68717c\">" +
      format_diameter_mm(maximum) +
      "</text><text x=\"60\" y=\"\{top + 199}\" text-anchor=\"end\" font-size=\"11\" fill=\"#68717c\">0.0</text>",
    )
    out.write_string(
      "<circle data-state=\"baseline\" cx=\"70\" cy=\"\{y(target.baseline_tenths_mm)}\" r=\"5\" fill=\"#374357\"><title>" +
      tr(language, "Baseline", "基线") +
      ": " +
      format_diameter_mm(target.baseline_tenths_mm) +
      " mm</title></circle><text x=\"70\" y=\"\{top + 225}\" text-anchor=\"middle\" font-size=\"11\">" +
      tr(language, "Baseline", "基线") +
      "</text>",
    )
    let mut previous : (Int, Int)? = Some((70, y(target.baseline_tenths_mm)))
    for i, a in trajectory.assessments {
      let x = 70 + (i + 1) * 840 / (trajectory.assessments.length() + 1)
      for m in a.measurements {
        if m.lesion_id != target.id {
          continue
        }
        let attrs = " data-visit-id=\"" +
          html_escape(a.visit_id) +
          "\" data-state=\"" +
          state_name(m.observation) +
          "\" data-visit-response=\"" +
          a.response.code() +
          "\""
        let label = html_escape(a.visit_id) +
          " · " +
          observation_label(m.observation, language) +
          " · " +
          tr(language, "Visit target category", "随访靶病灶分类") +
          ": " +
          a.response.code()
        if m.effective_tenths_mm is Some(value) {
          let py = y(value)
          if a.response != NE && previous is Some((px, previous_y)) {
            out.write_string(
              "<line x1=\"\{px}\" y1=\"\{previous_y}\" x2=\"\{x}\" y2=\"\{py}\" stroke=\"#456778\" stroke-width=\"2\"/>",
            )
          }
          let color = response_color(a.response)
          let fill = if a.response == NE { "#fffdf9" } else { color }
          let title = "<title>" +
            label +
            ": " +
            format_diameter_mm(value) +
            " mm</title>"
          if m.observation is TooSmallToMeasure {
            out.write_string(
              "<rect" +
              attrs +
              " data-effective-mm=\"" +
              format_diameter_mm(value) +
              "\" x=\"\{x - 5}\" y=\"\{py - 5}\" width=\"10\" height=\"10\" fill=\"\{fill}\" stroke=\"\{color}\" stroke-width=\"2\">" +
              title +
              "</rect>",
            )
          } else {
            out.write_string(
              "<circle" +
              attrs +
              " data-effective-mm=\"" +
              format_diameter_mm(value) +
              "\" cx=\"\{x}\" cy=\"\{py}\" r=\"5\" fill=\"\{fill}\" stroke=\"\{color}\" stroke-width=\"2\">" +
              title +
              "</circle>",
            )
          }
          previous = if a.response == NE { None } else { Some((x, py)) }
        } else {
          out.write_string(
            "<path" +
            attrs +
            " d=\"M \{x - 5} \{top + 185} l 10 10 m -10 0 l 10 -10\" stroke=\"#787b83\" stroke-width=\"2\"><title>" +
            label +
            tr(language, "; no diameter", "；无直径数值") +
            "</title></path>",
          )
          previous = None
        }
      }
      out.write_string(
        "<text x=\"\{x}\" y=\"\{top + 225}\" text-anchor=\"middle\" font-size=\"11\">V\{i + 1}</text><text x=\"\{x}\" y=\"\{top + 242}\" text-anchor=\"middle\" font-size=\"10\">" +
        a.response.code() +
        "</text>",
      )
    }
    out.write_string("</g>")
  }
  out.write_string("</svg>\n")
  out.to_string()
}

///|
fn lesion_trends_note(language : ReportLanguage) -> String {
  tr(
    language, "Each target uses its own vertical scale. V1, V2 follow the visit ledger. Squares mark the explicit 5.0 mm default; crosses have no diameter. Hollow points retain an observation from an NE visit. Connecting lines stop at NE or missing visits. These points do not make an NE visit eligible for the total trend or nadir.",
    "各病灶使用独立纵轴比例，V1、V2 对应随访台账顺序。方点表示明确的 5.0 mm 默认值，叉号无直径数值，空心点保留 NE 随访中的观察。NE 或缺失处断线；保留观察不意味着该次随访可进入总和趋势或更新最低值。",
  )
}

///|
fn render_lesion_section_html(
  trajectory : @evidence.Trajectory,
  language : ReportLanguage,
) -> String {
  let out = StringBuilder()
  out.write_string(
    "<section class=\"panel chart\" id=\"lesion-trends\"><h2>" +
    tr(language, "Individual target trends", "单病灶趋势") +
    "</h2><p class=\"muted\">" +
    lesion_trends_note(language) +
    "</p>" +
    render_lesion_trends_svg(trajectory, language~),
  )
  out.write_string(
    "<div class=\"table-scroll\"><table><thead><tr>" +
    tr(
      language, "<th>Visit / date</th><th>Target / axis</th><th>Observation</th><th class=\"num\">Effective / mm</th><th>Visit target category</th>",
      "<th>随访 / 日期</th><th>病灶 / 测量轴</th><th>观察状态</th><th class=\"num\">采用直径 / mm</th><th>随访靶病灶分类</th>",
    ) +
    "</tr></thead><tbody>",
  )
  for target in trajectory.study.targets {
    out.write_string(
      "<tr><td>" +
      tr(language, "Baseline", "基线") +
      "<br>" +
      trajectory.study.baseline_date +
      "</td><td>" +
      html_escape(target.id) +
      " · " +
      axis_label(target.kind, language) +
      "</td><td>" +
      tr(language, "baseline measurement", "基线测量") +
      "</td><td class=\"num\">" +
      format_diameter_mm(target.baseline_tenths_mm) +
      "</td><td>—</td></tr>",
    )
  }
  for i, a in trajectory.assessments {
    for m in a.measurements {
      out.write_string(
        "<tr><td><a href=\"#visit-\{i}\">" +
        html_escape(a.visit_id) +
        "</a><br>" +
        a.date +
        "</td><td>" +
        html_escape(m.lesion_id) +
        " · " +
        axis_label(m.kind, language) +
        "</td><td>" +
        observation_label(m.observation, language) +
        "</td><td class=\"num\">" +
        mm_or_missing(m.effective_tenths_mm) +
        "</td><td>" +
        a.response.code() +
        "</td></tr>",
      )
    }
  }
  out.write_string("</tbody></table></div></section>")
  out.to_string()
}

///|
fn render_lesion_section_markdown(
  trajectory : @evidence.Trajectory,
  language : ReportLanguage,
) -> String {
  let out = StringBuilder()
  out.write_string(
    "\n## " +
    tr(language, "Individual target trends", "单病灶趋势") +
    "\n\n" +
    lesion_trends_note(language) +
    "\n\n",
  )
  out.write_string(
    tr(
      language, "| Visit / date | Target / axis | Observation | Effective / mm | Visit target category |\n",
      "| 随访 / 日期 | 病灶 / 测量轴 | 观察状态 | 采用直径 / mm | 随访靶病灶分类 |\n",
    ) +
    "|---|---|---|---:|---|\n",
  )
  for target in trajectory.study.targets {
    out.write_string(
      "| " +
      tr(language, "Baseline", "基线") +
      " / " +
      trajectory.study.baseline_date +
      " | " +
      markdown_escape(target.id) +
      " / " +
      axis_label(target.kind, language) +
      " | " +
      tr(language, "baseline measurement", "基线测量") +
      " | " +
      format_diameter_mm(target.baseline_tenths_mm) +
      " | — |\n",
    )
  }
  for a in trajectory.assessments {
    for m in a.measurements {
      out.write_string(
        "| " +
        markdown_escape(a.visit_id) +
        " / " +
        a.date +
        " | " +
        markdown_escape(m.lesion_id) +
        " / " +
        axis_label(m.kind, language) +
        " | " +
        observation_label(m.observation, language) +
        " | " +
        mm_or_missing(m.effective_tenths_mm) +
        " | " +
        a.response.code() +
        " |\n",
      )
    }
  }
  out.to_string()
}
