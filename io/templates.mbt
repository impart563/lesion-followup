///|
/// Matched synthetic inputs and instructions. Writing files belongs to the CLI.
pub fn input_template_files(
  name : String,
  language? : ReportLanguage = English,
) -> Result[Array[(String, String)], String] {
  if name != "single" && name != "multi" {
    return Err("Template must be single or multi.")
  }
  let targets : Array[Json] = [
    { "id": "T1", "organ": "liver", "kind": "non_nodal", "baseline_mm": "30.0" },
  ]
  if name == "multi" {
    targets.push({
      "id": "N1",
      "organ": "lymph_nodes",
      "kind": "lymph_node",
      "baseline_mm": "20.0",
    })
  }
  let study : Json = {
    "schema_version": 1,
    "study_id": "synthetic-" + name,
    "baseline_date": "2026-01-01",
    "technique_id": "ct-venous-5mm",
    "slice_thickness_mm": "5.0",
    "targets": targets.to_json(),
  }
  let csv = StringBuilder()
  csv.write_string(
    "visit_id,date,technique_id,lesion_id,state,diameter_mm,note\n",
  )
  for
    (id, date, liver, node) in [
      ("week-2", "2026-01-15", "20.0", "15.0"),
      ("week-4", "2026-02-01", "10.0", "10.0"),
      ("week-6", "2026-02-15", "14.0", "10.0"),
      ("week-8", "2026-03-01", "15.0", "10.0"),
    ] {
    csv.write_string("\{id},\{date},ct-venous-5mm,T1,measured,\{liver},\n")
    if name == "multi" {
      csv.write_string("\{id},\{date},ct-venous-5mm,N1,measured,\{node},\n")
    }
  }
  let instructions = tr(
      language, "# Synthetic target-lesion input template\n\nThese matched files are synthetic, not patient records. Results cover target lesions only.\n\n",
      "# 合成靶病灶输入模板\n\n配套文件均为合成数据。结果仅评价靶病灶。\n\n",
    ) +
    tr(
      language, "Edit study.json and followup.csv together. Keep target IDs fixed and visit rows contiguous, ordered by strictly increasing date. Sizes use millimetres with at most one decimal place; JSON sizes are strings. Non-nodal targets use longest diameter, nodes use short axis.\n\nStates: measured requires diameter_mm; absent, too_small and missing require blank diameter_mm and note; not_evaluable requires a reason in note and blank diameter_mm. Omitted targets are missing, never zero. too_small explicitly uses 5.0 mm. Keep organ groups canonical and review acquisition comparability.\n\n",
      "请配套编辑 study.json 与 followup.csv。靶病灶 ID 固定；同次随访的行须连续，随访日期严格递增。直径单位为 mm，最多一位小数；JSON 中直径用字符串。非淋巴结使用最长径，淋巴结使用短轴。\n\n状态约定：measured 必须填写 diameter_mm；absent、too_small、missing 的直径和 note 留空；not_evaluable 的直径留空，note 必须写明原因。漏掉的病灶视为 missing，不填零；too_small 明确使用 5.0 mm 默认值。器官组须规范，可比性需要人工核对。\n\n",
    ) +
    tr(
      language, "From the project root, replace DIRECTORY below with this generated folder:\n\n",
      "在项目根目录运行下列命令，将 DIRECTORY 替换为本模板所在目录：\n\n",
    ) +
    "```sh\nmoon run --target native cmd/demo -- --study 'DIRECTORY/study.json' --input 'DIRECTORY/followup.csv' --check-input --lang zh-CN\nmoon run --target native cmd/demo -- --study 'DIRECTORY/study.json' --input 'DIRECTORY/followup.csv' --format html --lang zh-CN --output 'DIRECTORY/review.html'\n```\n\n" +
    tr(
      language, "Create a new directory for each template; initialization never merges into an existing directory. Review reports do not establish overall response or recommend treatment.\n",
      "每份模板使用新目录，初始化不会合并或覆盖已有目录。复核报告不确定整体疗效，也不提供治疗建议。\n",
    )
  Ok([
    ("study.json", study.stringify(indent=2) + "\n"),
    ("followup.csv", csv.to_string()),
    ("README.md", instructions),
  ])
}
