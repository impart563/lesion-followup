# 从外部项目接入

本模块提供人工 CT 靶病灶随访的计算与证据接口，支持类型化输入或 JSON/CSV 文本输入。
根包 `impart563/lesion-followup` 是受支持的消费入口。库在内存中工作，不读取影像、选择病灶、
评价非靶病灶或新病灶，不给出整体疗效与治疗建议。示例均为合成数据。

## 本地候选验证

`python scripts/acceptance.py` 会先运行独立消费示例，再解压实际 `moon package` 归档，
建立临时消费模块。它只从解压候选读取库源码，在 wasm、wasm-gc、js、native 四后端运行。
该过程验证候选内容完整，没有使用仓库库源码链接；依赖仍正常通过 registry 解析。
它不等于本模块已经发布到 Mooncakes。

消费入口见 [`main.mbt`](../examples/downstream-consumer/main.mbt)。验证覆盖：

- 从根包构造 `Study`、`Visit` 等公开类型并复核，保留淋巴结短轴 9.9 mm 的原始值。
- 从模板取得 JSON/CSV 字符串，执行 `preflight_inputs`、解析和 `replay_track`。
- 区分无效文本和合法但无法评价的 NE，保留人工核查提示。
- 生成中英文报告包，用 `verify_bundle` 验证，并拒绝字节被修改的文件。

根包签名由 `moon info` 生成，见 [`pkg.generated.mbti`](../pkg.generated.mbti)。库函数返回的
轨迹用于报告渲染，调用者不应修改其数组内容。尺寸内部使用 0.1 mm 整数，文本直径最多一位小数。

## 正式发布后的 registry 安装

以下步骤以 `impart563/lesion-followup@0.2.0` 已实际发布为前提。候选完成或 GitHub 推送
不满足这个前提；如果 registry 找不到该版本，应保留失败信息，不用本地工作区替代安装结果。

1. 在仓库外建立一个新目录，只复制消费示例的 `moon.mod`、`moon.pkg`、`main.mbt`。
   不复制示例的 `moon.work`，避免继续引用本地源码。
2. 在新目录禁止自动发现工作区，再从 registry 解析依赖并运行。

PowerShell：

```powershell
$env:MOON_WORK = 'off'
moon update
moon run --target native .
```

Bash：

```sh
export MOON_WORK=off
moon update
moon run --target native .
```

已有项目可在发布后用 `moon add impart563/lesion-followup@0.2.0` 添加依赖，再在对应
`moon.pkg` 中导入 `"impart563/lesion-followup" @lib`。若需要 UTF-8 字节编码，像消费示例一样
显式导入 `moonbitlang/core/encoding/utf8`。四后端消费的完整命令与实际结果保存在验收记录中。

## 分发位置

Mooncakes 适合库依赖安装和 API 文档，GitHub 保存源码、问题记录、CLI 示例及浏览器工作区归档。
浏览器工作区需要 HTTP 服务载入 ES 模块；在 Mooncakes 安装库不会自动启动网页。
候选和正式发布的独立状态见[发布说明](release.md)。上面的接口用法由独立消费模块实际编译验证，
registry 操作方式参考[官方模块管理文档](https://docs.moonbitlang.com/en/stable/toolchain/moon/package-manage-tour.html)。
