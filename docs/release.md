# 0.2.0 发布准备与接入

0.2.0 汇总输入准备、复核追溯、离线工作区、人工核查、完整交接及观察录入。本仓库当前准备
`0.2.0-rc.2` 发布候选。模块内版本仍为 `0.2.0`，候选标识写入归档名称和发布清单。
早期 `rc.1` 保持其原始提交和附件；它不代表当前开发内容，不能直接替代新候选。

## 兼容范围

| 契约 | 0.2.0 状态 |
| --- | --- |
| MoonBit | 固定编译器 `0.10.14+7d59c7ec9`，Moon CLI `0.1.20260920`；四后端为 wasm、wasm-gc、js、native |
| 根包门面 | 保留原有导入路径 `impart563/lesion-followup`；新增接口可查生成的 `pkg.generated.mbti`；库不读写文件 |
| 原始输入 | 研究 JSON v1、随访 CSV 七列保持不变；尺寸用最多一位小数的字符串，内部单位为 0.1 mm，不舍入 |
| 审计 JSON / CSV | JSON schema v1，保留原字段并增加逐条件证据；应按字段名读取并允许已文档化的附加字段 |
| 报告包清单 | v2，含软件版本、规则版本及输入/产物摘要；校验器拒绝未知版本，旧清单需用原始输入重新生成 |
| 浏览器 / 草稿 | 请求 v1、草稿 v1；未知字段或版本按各自严格契约拒绝；原始 JSON/CSV 可跨入口使用 |
| 会话 / 核查 / 交接 | 可移植会话 v1、人工核查记录 v1、完整交接 v1；接收交接需从当前输入重算五份报告 |
| 发布候选清单 | 新候选使用 v2，记录源码摘要及文件数；独立核验工具拒绝旧 v1 清单，早期 rc.1 的原记录不改写 |
| 医学语义 | 沿用 `recist-1.1-target-subset-1`；NE、最低值和上下文门限保持已有语义；详见[规则及限制](rule-semantics.md) |

HTML、Markdown 与中文提示为展示层，不适合作为解析接口。机器字段及稳定诊断代码用于程序接入。此版本未宣称对未来工具链的兼容性。

## 从源码使用

```sh
moon update
python scripts/acceptance.py
python scripts/reproduce_examples.py --output _build/review-examples
python scripts/build_browser.py
python scripts/serve_browser.py --directory . --port 8765
```

打开 `http://127.0.0.1:8765/_build/browser/`，选择导入示例原始文件或生成的 `draft.json`。静态服务器仅提供本地资源，计算在浏览器内完成。CLI 命令、输入及退出码见 [README](../README.md)；浏览器请求见[适配契约](browser-adapter.md)；具体操作见[工作区说明](workbench.md)。

库使用者可先在 `moon.work` 中引用本地模块，参考独立模块 [`examples/downstream-consumer`](../examples/downstream-consumer/)。验收还会解压 `moon package` 的实际归档，在临时目录建立新的消费模块，四后端运行类型构造、文本解析、预检、合法 NE、双语报告包及篡改拒绝。该检查不链接原仓库库源码；它验证候选包的完整性。依赖 `moonbitlang/async@0.19.4` 仍按正常 registry 机制解析。发布后的安装步骤单列在[接入说明](integration.md)中。

## 生成候选包

先运行完整验收并提交源码和验收记录。脚本要求工作树干净，且验收指纹与源码一致：

```sh
python scripts/acceptance.py --record docs/acceptance-results.json
# Review and commit the accepted tree before the next command.
python scripts/build_release.py --candidate rc.2 --output _build/release-0.2.0-rc.2
python scripts/verify_release.py _build/release-0.2.0-rc.2
```

输出目录必须尚不存在。候选内容包括：

- `impart563-lesion-followup-0.2.0.zip`：Mooncakes 候选模块，已经解压消费验证。
- `lesion-followup-0.2.0-rc.2-source.zip`：对应 Git 提交的源码，可运行验收。
- `lesion-followup-0.2.0-rc.2-browser.zip`：可由普通静态服务器提供的完整工作区，无需重新编译。
- `release-manifest.json` 与 `SHA256SUMS`：提交、验收指纹、归档字节数与摘要，以及实际发布状态。
- `verification.json`：生成后实际运行独立核验的结果，含各归档文件数、展开字节数、运行文件数及四后端消费状态。

候选编号仅接受 `rc.N`（正整数，不带前导零），默认 `rc.2`。每次使用新的输出目录，避免覆盖
旧候选。核验工具不解压归档到磁盘，会检查文件路径、摘要、源码提交及指纹、模块与源码的一致性、
浏览器运行文件和本地导入是否完整，以及记录中的消费验证是否齐备。它核对本地候选的一致性，
不认证作者身份，也不查询 registry 的实际发布状态。重新打包不代表重新发布。

浏览器包解压后，在该目录运行 `python serve_browser.py --port 8765` 并打开 `http://127.0.0.1:8765/`。随包启动脚本固定 ES module 的 MIME 类型，兼容 Windows 的系统文件类型差异，并仅监听本机。需支持 ES modules、Web Crypto 和本地文件选择的现代浏览器；不能直接双击 `index.html` 代替 HTTP 入口。浏览器内导出和本地草稿的限制见工作区说明。

## 发布状态与正式发布步骤

候选包、GitHub Release、Mooncakes 发布和发布后 registry 安装是四个独立记录项。`build_release.py` 只构建候选，不推送标签、不发布 Release、不上传 registry。GitHub 的 draft Release 仅仓库有权限者可见，也不等于正式发布。

正式发布时，应先核对本次提交对应的 Windows / Linux CI 证据、`SHA256SUMS` 和候选说明。GitHub Release 需附上候选文件及对应提交；registry 发布须由拥有 `impart563` 命名空间的 Mooncakes 账号登录，再从该已验收版本运行 `moon publish`。GitHub 登录与 Mooncakes 登录分别核实，不能相互替代。

本项目适合作为早期 `0.2.0` 库版本发布到 Mooncakes，以便外部项目通过固定版本依赖和 API 文档接入。
完整浏览器体验、CLI 文件流程及合成示例继续通过 GitHub 源码和浏览器归档交付。发布前仍需确认
目标版本在命名空间中的可用性；若该版本已经存在，应按实际变更提升版本并重新验收，不能覆盖。
本批准备候选与接入证据，不自动登录或执行正式上传。模块版本规则及发布方式参考
[官方发布文档](https://docs.moonbitlang.com/en/stable/toolchain/moon/package-manage-tour.html#publish-your-module)。

只有 registry 返回成功且能从新目录解析 `impart563/lesion-followup@0.2.0`，再执行独立模块的编译及运行后，才记录“已发布、可安装”及实际地址。未完成前，本地 workspace 消费与候选包验证均不能称作 registry 安装成功。

全部演示输入为合成数据，仅供人工 CT 靶病灶的软件复核，不代表整体疗效、治疗建议或临床验证。

工具链及发布命令以[本机 `moon --help` 对应的官方手册](https://github.com/moonbitlang/moon/blob/main/docs/manual/src/commands.md)为参考；[官方安装入口](https://www.moonbitlang.com/download/)提供各平台安装方式。本项目验收以仓库记录的固定工具链为准。
