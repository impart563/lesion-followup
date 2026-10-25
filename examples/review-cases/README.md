# 完整复核示例

这里的四组记录均为合成输入，共用 [`../study.json`](../study.json) 中的基线：肝脏非淋巴结靶病灶 T1 为 30.0 mm，淋巴结 N1 短轴为 20.0 mm，总和 B = 50.0 mm。所有分类仅指靶病灶结果。

从仓库根目录运行：

```sh
python scripts/reproduce_examples.py --output _build/review-examples
```

输出包含每例的原始输入副本、五种报告、可导入工作区的 `draft.json`、修订对比、批量报告包及 `verification.json`。输出目录必须尚不存在；同一命令也进入完整验收。生成的草稿使用固定合成时间以保证可重现，不表示实际保存时间。

## 人工核对表

下表按输入顺序列出四次随访。N 是进入本次随访前可用于比较的历史最低值；S 是本次直径总和，均以 mm 表示。`expected.json` 是独立手算的期望值，脚本只读取并核对，不覆盖它。

| 输入 | S（week-2 / 4 / 6 / 8） | N（week-2 / 4 / 6 / 8） | 靶病灶结果 | 核对重点 |
| --- | --- | --- | --- | --- |
| 多靶 `../followup.csv` | 35 / 20 / 24 / 25 | 50 / 35 / 20 / 20 | PR / PR / PR / PD | 24 相对 20 增长 20%，但只增加 4 mm，未同时满足 PD；25 增加 5 mm，满足 PD |
| 缺测 `missing.csv` | 35 / 无完整总和 / 20 / 25 | 50 / 35 / 35 / 20 | PR / NE / PR / PD | week-4 的 T1 明确缺测，不能当作零；NE 不降低最低值 |
| 采集变化 `technique.csv` | 35 / 10 / 20 / 25 | 50 / 35 / 35 / 20 | PR / NE / PR / PD | week-4 虽有完整测量，总和 10 仍因采集标识变化为 NE；不能用它更新最低值 |
| 修订 `../followup.revised.csv` | 35 / 19 / 24 / 25 | 50 / 35 / 19 / 19 | PR / PR / PD / NE | 仅将 week-4 的 T1 从 10 改为 9；week-6 相对 19 增长超过 20% 且增加 5 mm，提前进入 PD；此后的随访由既有上下文门限保留为 NE |

PR 的数值条件为 S ≤ 0.7B = 35 mm，同时须通过完整性、可比性及上下文检查，且优先排除 CR、PD。PD 需同时满足 S ≥ 1.2N 和 S − N ≥ 5 mm。实现以 0.1 mm 整数作精确比较；此处手算不改变规则。

`batch.json` 将同样四例按清单相对路径组织。预期为 4 例成功、0 例输入或文件错误；其中 NE 是合法输入对应的靶病灶评价结果，不能算作批处理失败。

## 导入与追溯

在离线工作区“导入草稿”中选择生成的某例 `draft.json`，或分别选择该例的 `study.json`、`followup.csv`。修改后需重新校验并生成报告。`revision.json` / `revision.html` 展示原始 multi 与 revised 两版的下游影响，原输入保持不变。

规则来源、适用范围及限制见 [规则语义](../../docs/rule-semantics.md)，来源包括 [RECIST Working Group](https://recist.eortc.org/recist-1-1/) 和 [RECIST 1.1 原始论文](https://doi.org/10.1016/j.ejca.2008.10.026)。本例集复用已有规则，不新增医学判定。不含真实患者信息，不代表整体疗效、治疗建议或临床验证。
