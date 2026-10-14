# 计算机体系结构研讨课 —— 工作区说明（当前状态）

> 快照时间：2026-09-08（2026-10-12 增补 exp10/11 入库，见 §十二；2026-10-14 两轮结构整理：本目录=仓库根、prj1/prj2 平铺、viz/ 独立线、ref/ 收纳课程包与讲义，见 §十五）。本文件为工作区唯一顶层说明文件；历史操作记录见 §五/§六。
> 口径（2026-10-12）：课程作业/仿真/验收/提交一律以**课程网站发布包**为准（`课程发布包/`）；官方 gitee 包与超前实验 exp12~20（尚未发布）已归档至 `C:\course_files\2026_autumn\资料库\`，平时不参与课程工作流；exp10/11 课程包已发布并入库（见 §十二）。
> 实验推进约定：课程发布包 → 工作副本 `prj1/ prj2/`（下分 expN）→ 功能仿真（2026-09-15 起 Vivado xsim）→ Vivado 工程 `C:\vivado_prj\expNN`（英文路径，产出 bit）。

## 一、目录总览

```
C:\course_files\2026_autumn\
├── 研讨-计算机体系结构\        ← 课程工作区 = git 仓库工作树（本文件；2026-10-14 起）
│   ├── prj1/                  exp1（跑马灯）、exp6（单周期找错；exp6/ref_sc = 修正版基线）
│   ├── prj2/                  exp7~exp11（流水线系列，下分 exp：myCPU / patch / reading）
│   ├── viz/                   可视化线（verilog-viz + datapath-preview）
│   ├── 实验报告/              报告要求 + 模板 + 专题报告 md/PDF + figures（见 §九）
│   ├── tools/                 run_sim_cli.bat（xsim 一键脚本）
│   ├── ref/                   课程发布包 + 课程讲义（本地参考，不入库；见 ref/README.md）
│   ├── 提交物/                提交包存档（本地保留，不入库）
│   └── README.md              ← 本文件
└── 资料库/                    归档区：官方实验包、prj3~7 超前实验、tmpfig、zip 历史副本（见其 README）
```

> 注：`loongson/` 已于 2026-10-11 移出本工作区、迁至 `C:\course_files\loongson\`（与 ipdps27 同级），与本课程工作流无关。
> 注：本目录即 git 仓库工作树（远端 `tryone667/tmp--calab-ucas`）：`git pull` 直接铺平更新；新机器 `git clone` 到任意目录即得工作区骨架（`课程发布包/` 等本地件按需自备）。

`prj1/ prj2/` 内部：下分 `expNN/`；每个 exp 收录 `myCPU/`、`patch/`（部分带 `reading/`），日志集中在 `prjN/logs/`；实验里的课程包重内容（`func/ gettrace/ soc_verify/` 等）不入库，本地按课程发布包补齐。Vivado 工程与 bit 在 `C:\vivado_prj\expNN\`。

## 二、课程主线对照（课程网站口径）

| 发布包 | 实验 | 内容 | 测试目标 | 工作区 | 完成状态 |
|---|---|---|---|---|---|
| exp1.zip | exp1 | 跑马灯（Vivado/FPGA 入门） | — | prj1/exp1 | PASS + 已上板 |
| exp6.zip | exp6 | 单周期 20 指令找错 | n1~n20 | prj1/exp6_wt_answer | PASS + 已上板 |
| exp7.zip | exp7 | 五级流水：不考虑冒险（镜像插 nop） | n1~n20 | prj2/exp7 | 三阶段版 PASS（2058995 ns）；bit 2026-09-15 重出；提交包是否重制见 §十一 |
| exp8.zip | exp8 | cancel 解 control hazard + 阻塞解 data hazard | n1~n20 | prj2/exp8 | 三阶段版 PASS（1349305 ns）；bit 2026-09-15 重出；提交包 `提交物/prj2_exp8_3_2024K8009929018.zip`（2026-09-15 上板复验全 PASS） |
| exp9.zip | exp9 | forward 优化 | n1~n20 | prj2/exp9 | 三阶段版 PASS（639855 ns）；bit 2026-09-15 重出；提交包 `提交物/prj2_exp9_3_2024K8009929018.zip` |
| exp10.zip | exp10 | 用户态运算指令 | n1~n36 | prj2/exp10 | ✅ 课程包 xsim 复验 n1~n36 PASS（2026-10-12，见 §十二）；超前版 bit 已出、未烧 |
| exp11.zip | exp11 | 转移+访存指令 | n1~n46 | prj2/exp11 | ✅ 课程包 xsim 复验 n1~n46 PASS（2026-10-12）；超前版 bit 已出、未烧 |

报告归属（课程 PPT 的 6 份报告清单，见 §九）：

| 实验 | 属于哪份报告 |
|---|---|
| exp1（跑马灯）、exp6（单周期 20 指令找错） | **不单独成报告**。课程进度表里它们不属于任何专题报告，定位是“实验器材及工具软件操练”阶段的前置任务；第 1 份要交的报告直接从实践任务 7 起算。 |
| exp7 / exp8 / exp9 | **同一份**报告：《流水线CPU设计专题实验报告》（第 1 个专题，个人独立完成，覆盖实践任务 7、8、9）。 |

> 注意区分：`exp6` 是**单周期**阶段的找错实验，只是流水化改造的起点（所以提交包里有 `exp6→exp7` 的 patch）；它本身不是这次报告的主题。

说明：
- 课程站包 = 按实验裁剪+修订版（myCPU 空起步、func 为课程修订测试集、gettrace 为课程参考核），与官方 gitee 同名 Lab 包**不完全相同**（验证框架共同文件逐字节一致，差异集中在 func/gettrace/myCPU）；验收/提交一律用课程站包。
- 课程站包解压即 prj1/prj2 内工作目录的原始版；prj1/prj2 现为**已开工完成版**（myCPU 已填；exp10/11 于 2026-10-12 按课程包复验通过）；勿用 zip 重新解压覆盖已完成代码。
- exp2~5 未在课程网站出现；官方 Lab01~04（官方版 exp1/6~9 等）原件在 `资料库\官方实验包\`。
- exp10/11 课程包已于 2026-10-12 发布并入库（`课程发布包/exp10.zip`、`exp11.zip`；工作副本 `prj2/exp10`、`prj2/exp11`）；**exp12~20 尚未发布**，其超前完成的工作副本仍归档 `资料库\prj3_7_超前实验_未发布\`。

## 三、课程主线完成状态（截至 2026-10-12）

| 实验 | 功能仿真 | Vivado bit（C:\vivado_prj\expN） | 上板 |
|---|---|---|---|
| exp1 跑马灯 | PASS（prj1/logs/exp1_run.log） | scroller.bit | ✅ 已上板（17:02，单灯移位） |
| exp6 单周期找错 | n1~n20 PASS（prj1/sim/sim_pass.log） | exp6_wt_answer/.../soc_lite_top.bit | ✅ 已上板（17:14，DDR3 SoC 全 PASS） |
| exp7 流水（不考虑冒险） | n1~n20 PASS，2058995 ns（prj2/logs/exp7_run.log） | 2026-09-15 09:31 重出（WNS 3.922） | ✅ 2026-09-15 上板全 PASS（0x14000014 + 双绿；日志 prj2/logs/exp7_program_20260915.log）；2026-09-08 版亦曾全 PASS |
| exp8 cancel+阻塞 | n1~n20 PASS，1349305 ns（prj2/logs/exp8_run.log） | 2026-09-15 09:25 重出（WNS 2.499） | ✅ 2026-09-15 13:15 上板全 PASS（0x14000014 + 双绿；日志 prj2/logs/exp8_program_20260915.log） |
| exp9 forward | n1~n20 PASS，639855 ns（prj2/logs/exp9_run.log；2026-09-29 xsim 复跑同 PASS） | 2026-09-15 09:35 重出（WNS 2.112） | ✅ 2026-09-29 上板 PROGRAM DONE（prj2/logs/exp9_program_20260929.log） |
| exp10 用户态运算 | ✅ **课程包复验** n1~n36 PASS（prj2/logs/exp10_xsim_run_20261012.log，2026-10-12；超前版 09-03 亦 PASS） | 超前版 bit 已出（C:\vivado_prj\exp10，WNS+0.925/WHS+0.077）；课程包口径 bit 待重出 | 未烧（板级未要求） |
| exp11 转移+访存 | ✅ **课程包复验** n1~n46 PASS（prj2/logs/exp11_xsim_run_20261012.log，2026-10-12；超前版 09-03 亦 PASS）；**2026-10-13 验收通过并按助教意见清理后复跑同 PASS（1419475 ns，逐拍等价，见 §十三）** | 超前版 bit 已出（WNS+0.448/WHS+0.084）；课程包口径 bit 待重出 | 未烧 |

- 仿真日志命名：2026-09-15 之前是 iverilog（`prj2/logs/expN_run.log`）；之后统一 Vivado xsim（`prj2/logs/expN_xsim_run.log`）。
- exp7 提交包：`提交物/prj2_exp7_3_2024K8009929018.zip`（myCPU 四文件 + patch/ + soc_lite_top.bit；2026-09-08 全新 iverilog 仿真 n1~n20 全 PASS，日志 `prj2/logs/exp7_acceptance_sim.log`）。
- 超前实验 exp10~20 的完成状态/时序/上板记录见 `资料库\研讨-计算机体系结构_README_20260904历史版.md`（09-04 全量快照）；exp10/11 课程包入库与复验计划见 §十二。
- **验收**：exp7~11 已全部通过验收（2026-10-13 课堂验收收尾；此前 exp7~9 随堂验收、exp10/11 于 2026-10-13 通过），exp11 附助教改进意见，见 §十三。

## 四、工作流程与工具速查

### 4.1 工具与环境（先用现成的，别重造）

| 用途 | 工具 / 路径 | 说明 |
|---|---|---|
| 指令级仿真 | **Vivado xsim**（`xvlog` / `xelab` / `xsim`，或 GUI 的 Run Simulation） | 2026-09-15 起**只在 Vivado 里做仿真**（原 WSL iverilog 流程停用，仅作应急备用）；命令、判据与两个坑见 §4.2 第 3 步 |
| 综合 / 实现 / 出 bit | `C:\Application\Xilinx\Vivado\2019.2`（器件 xc7a200tfbg676-1） | 工程放在 `C:\vivado_prj\expNN`（英文路径） |
| 上板（JTAG 烧 bit） | 脚本已删（2026-10-14），恢复/手动流程见 §八 | 用户不常用，按需恢复 |
| 课件文本抽取 | `C:\course_files\_tools\extract_slides.py` | **全工作区通用，禁止另写抽取脚本**；说明见 `C:\course_files\_tools\README.md` |
| 报告插图 | 手写 SVG（`实验报告/figures/`） | 浏览器 / Inkscape / draw.io 可直接编辑，不引入绘图框架 |
| Python | 3.10.11（已装 PyMuPDF / python-pptx / pdfplumber / pypdf） | 抽取与校验用 |

- 课程讲义是 PDF 原件，**直接打开读即可**；本课程不建 `01_extracted/`（研讨课不套理论课模板）。确需纯文本时用上表那个通用工具。

### 4.2 一个实验从取包到提交的完整流程（以 expN 为例）

1. **取包**：`课程发布包/expN.zip` 解压到 `prj1/`（exp1 / exp6）或 `prj2/`（exp7~11）。
   ⚠️ `prj1/`、`prj2/` 里是**已完成版**，重新解压会覆盖 `myCPU/`，动手前先备份或另存目录。
2. **改代码**：只动 `myCPU/` 下四个文件（`alu.v` / `regfile.v` / `tools.v` / `mycpu_top.v`）。
   `func/`（测试程序）、`gettrace/`（参考执行流）、`soc_verify/`（SoC 平台）都是只读的。
   ⚠️ `func/obj/*.mif` 是预编译好的指令/数据镜像，**本机没有 loongarch 工具链、重编不了**，别删别改。
3. **功能仿真（Vivado xsim —— 2026-09-15 起本课程唯一仿真流程，原 WSL iverilog 流程停用）**：
   一键跑（Windows 命令行，参数是实验号）：
   ```
   C:\vivado_prj\expN\soc_verify\soc_bram\run_vivado\run_sim_cli.bat N
   ```
   脚本依次做：`xvlog --incr --relax …` 编译 → `xelab … --snapshot tb_top_sim tb_top glbl` 精化 → `xsim tb_top_sim -R` 跑到底；
   日志在 `…\project\loongson.sim\sim_1\behav\xsim_cli\simulate.log`。
   GUI 入口：Vivado 打开 `C:\vivado_prj\expN\soc_verify\soc_bram\run_vivado\project\loongson.xpr` → Run Simulation；
   自动生成的 `tb_top.tcl` 只跑了 `run 1000ns`，要接着在 Tcl 控制台 `restart` 后 `run -all`
   （**必须 restart**：否则前 1000 ns 带着旧状态继续，结果不作数）。
   判据：`----[1349305 ns] Number 8'd20 Functional Test Point PASS!!!` + `----PASS!!!`（exp8 实测；与 iverilog 历史结果一致，xsim elapsed 13 s、峰值内存 241 MB）。
   日志另存 `prj2/logs/expN_xsim_run.log`；tb 里 `$dumpvars` 会写出约 200 MB 的 `dump.vcd`（不要波形可删）。
   ⚠️ 三个坑：① `xvlog` 默认比工程模式严—— `mycpu_top.v` 有一处前向引用（`if_req_allowin` 用到还没声明的 `if_req_valid`），
   必须带 `--relax`（工程模式自动带）；② 仿真前 `C:\vivado_prj\expN\` 必须有 `gettrace\golden_trace.txt`（及 `func\obj\*.mif`），
   **缺了 tb 打不开参考流会每周期刷 `$fscanf` 错**（2026-09-15 实测：20 秒写出 1.5 GB 日志）；exp8 的 `gettrace/` 已补进工程树。
   ③ **GUI 下 `$finish` 不收尾**：Vivado IDE 里 Run Simulation，测试全过、也打了 `$finish called at time : 1350285 ns`，
   但交互会话不退出，tb 的 `forever` 打印会一路刷 `Test is running`（实测刷到 46.5 ms 后卡死：日志最后一行是半截的 `debug_wb_p`、
   `xsimk` 进程 CPU 停住）。**看到 `----PASS!!!` 就是过了，按 ■ 手动停**；或直接用 `run_sim_cli.bat`（`-R` 跑完自动退出）。
   （旧流程参考：WSL 里 `cd testbench && make`，或 `prj2/exp7_refactor/sim.sh`。）
4. **同步进 Vivado 工程并出 bit**：
   ```bash
   # 1) 把 prj2/expN/myCPU 四个文件复制到 C:\vivado_prj\expN\myCPU\
   # 2) 构建
   cd C:\vivado_prj\expN\soc_verify\soc_bram\run_vivado
   C:\Application\Xilinx\Vivado\2019.2\bin\vivado.bat -mode batch -source build_all.tcl
   ```
   产物：`...\project\loongson.runs\impl_1\soc_lite_top.bit`。判据：日志中综合/实现 0 Error、时序 WNS > 0。
   ⚠️ Vivado 工程里的 `myCPU` 副本比工作区多一行 `` `timescale ``（纯仿真指令，综合时无影响），代码其余部分逐字节等价；**以工作区为准**，别反向覆盖。
5. **上板验证**（按需；脚本与手动流程见 §八）：日志出现 `=== PROGRAM DONE ===`；板卡数码管停在 `0x14000014`、双绿灯亮 = n1~n20 全 PASS。
6. **打包提交**（命名 `prjN_expM_箱子号_学号.zip`）：`myCPU/`（四文件）+ `patch/`（相对上一实验的 git 风格 unified diff，做法见 `课程讲义/A03_提交patch指导/`）+ `soc_lite_top.bit`。成品放 `提交物/`。
7. **写报告**：复制 `实验报告/报告模板.md` 为 `实验报告/NN_<专题>_实验报告.md`，插图放 `实验报告/figures/`（详见 §九）。

### 4.3 常用命令与善后

- 清理仿真产物：`dump.vcd` 常有几百 MB，在 `soc_verify/soc_bram/testbench/project/` 下，跑 `make clean` 即可删除（下次 `make` 会重建）。
- 看波形：`prj2/exp7_refactor/watch_wave.sh`（在 WSLg 里打开 GTKWave）。
- 上板：上板脚本已删（恢复说明见 §八）；需要时从 git 历史取回或走 Vivado GUI。

## 五、2026-09-08 重构归档记录

课程目录现只保留课程主线内容；以下各项整体**移动**（未删除任何文件，移回即恢复）：

| 原位置 | 现位置 | 说明 |
|---|---|---|
| 本目录根 exp1/6/7/8/9.zip | `课程发布包/`（课程目录内） | 课程网站原件，唯一正本，SHA256 见资料库整理记录 |
| prj2/exp7~9.zip | `资料库\prj2_zip历史副本_已核对/` | 与课程发布包逐文件 SHA256 一致 |
| 官方实验包/ | `资料库\官方实验包/` | Lab01~Lab09_exp20 全套（zip + _extracted + README，约 510 MB） |
| prj3~prj7/ | `资料库\prj3_7_超前实验_未发布/prj3~prj7/` | exp10~20 超前工作副本（含 myCPU/logs，勿删） |
| tmpfig/ | `资料库\tmpfig/` | 板卡照片与调试临时件归档 |

- 文档同步：本 README 已按课程口径重写；旧全量版（含官方包对照与 exp10~20 完成表）存于 `资料库\研讨-计算机体系结构_README_20260904历史版.md`；资料库索引见 `资料库\README.md`。
- 外部镜像未动：`C:\simw\expNN` 与 `C:\vivado_prj\expNN`（exp1~20）仍在原英文路径；课程主线仅 prj1/prj2 与之保持同步。

## 六、外部环境约定与历史记录

- Vivado：`C:\Application\Xilinx\Vivado\2019.2`（xc7a200tfbg676-1）；仿真镜像 `C:\simw\expNN`；Vivado 工程与 bit `C:\vivado_prj\expNN`。
- 2026-09-02：exp1/exp6~9 全部完成综合+实现+bit，均已上板全 PASS（n1~n20，数码管 14000014 = 第 20 点）。
- 2026-09-03~04：官方全套入库对照、exp10~20 超前完成（功能仿真全 PASS + bit），README 于 09-04 汇总重写（细节见历史版）。
- 2026-09-08：确立“课程网站包为准”口径；官方包与超前内容归档 资料库；exp7 验收复跑 PASS（日志 `prj2/logs/exp7_acceptance_sim.log`）；验收专用副本目录已删除，提交包并入 `提交物/`（见 §七）。
- 2026-09-15：Smart App Control（约 09-10 由 Windows 自动开启）开始拦截 Vivado 未签名 DLL `librdi_tcltasks.dll`（CodeIntegrity 事件 3077），Vivado 完全无法启动，出 bit 与上板全被堵；当日关闭 SAC（`HKLM\SYSTEM\CurrentControlSet\Control\CI\Policy` 的 `VerifiedAndReputablePolicyState`，1→0）后恢复。**排查提示：若 Vivado 突然报 `couldn't load library librdi_tcltasks.dll: invalid argument`，先查这一条。**

## 七、2026-09-08 晚：提交包与验收副本合并

- 正式提交包：`提交物/prj2_exp7_3_2024K8009929018.zip`（作业命名 prj2_exp7_箱子号_学号：箱子号 3，学号 2024K8009929018）；同内容解包目录 `提交物/prj2_3_2024K8009929018/` 便于现场检查。
- 结构：`myCPU/`（alu/regfile/tools/mycpu_top）+ `patch/mycpu_exp7_pipeline_vs_exp6.patch`（exp6 完成版 `prj1/exp6_wt_answer/myCPU` → exp7，git 风格 unified diff，仅 alu.v/mycpu_top.v 有改动）+ `soc_lite_top.bit`。
- 核验：zip 内 myCPU 四文件与 bit 均与 2026-09-08 13:45 烧板全 PASS（0x14000014 + 双绿，`prj2/logs/exp7_program_20260908.log`）所用文件 SHA256 逐字节一致。
- 原 `C:\course_files\2026_autumn\exp7_acceptance\` 验收副本已删除（内容均为课程发布包/工作区派生件，无独有文件）；验收仿真日志转存 `prj2/logs/exp7_acceptance_sim.log`。

## 八、上板（脚本已删除，按需恢复）

本工作区自 2026-10-14 起**不再保留上板脚本**（用户不常用）。需要烧板时按下面恢复或手动执行：

- **取回历史脚本**（git 历史里还有）：`git show 6ed35e9:上板工具/flash_board.sh > flash_board.sh`、`git show 6ed35e9:上板工具/flash_board.tcl > flash_board.tcl`；放回任意目录后在 Git Bash / WSL 里 `bash flash_board.sh [bit路径]`（脚本自定位，默认烧 `C:\vivado_prj\exp7\soc_verify\soc_bram\run_vivado\project\loongson.runs\impl_1\soc_lite_top.bit`）。
- **手动等效（GUI）**：Vivado → Open Hardware Manager → Open target → Auto Connect → Program Device，选 `impl_1\soc_lite_top.bit`。
- **成功判据**：日志出现 `=== PROGRAM DONE ===`、`End of startup status: HIGH`；板卡数码管停在 `0x14000014`、双绿灯亮 = n1~n20 全 PASS。
- **常见坑**：板未供电 / JTAG 线未插 / 目标被占用（关掉 Vivado GUI 连接，或清掉残留 `hw_server`、`cs_server` 进程后重试）。
## 九、实验报告（2026-09-10 新建）

课程口径（`课程讲义/00_课程介绍ppt.pdf`）：**每个实验专题提交一份书面实验报告，全课程共 6 个专题；第 1 个专题个人独立完成，后 5 个专题分组完成**；实验任务主观分的判分依据包含实验报告撰写质量。体例要求见 `课程讲义/A01_实验报告撰写建议.pdf`：题目须标明是哪个实践专题、写明姓名学号、是文章不是幻灯片、**不放目录**、格式自定但全篇统一、图尽量用 visio / draw.io 等工具画。

报告区 `实验报告/`：

| 文件 | 说明 |
|---|---|
| `README.md` | 报告要求摘要（6 个专题 × 实践任务 × 周次对照表）+ 任务编号对照 + 本目录索引 |
| `报告模板.md` | 通用模板，写新专题报告时复制一份改名即可 |
| `01_流水线CPU设计专题_实验报告.md` | 第 1 个专题（实践 7/8/9）报告正文 |
| `01_流水线CPU设计专题_实验报告_林岳_2024K8009929018.pdf` | 报告打印版（8 页，2026-10-13 定稿） |
| `figures/fig1_datapath.svg` | 图 1 五级流水数据通路与三类冒险处理总览 |
| `figures/fig2_fetch_timing.svg` | 图 2 取指“请求—返回”配对与 load-use 停顿时序图 |
| `figures/fig3_branch_flush.svg` | 图 3 分支在 ID 判出的冲刷时序图 |

- 报告正文按真实 RTL（`prj2/exp7`、`exp8`、`exp9`，与 `提交物/` 里提交版功能等价）与仿真、上板日志写实；第五节「调试记录」已于 2026-10-13 补全（四个真实案例：三阶段重构与增量补丁为空、参考流缺失、`xvlog` 前向引用、GUI `$finish` 不退出），并已出 PDF：`01_流水线CPU设计专题_实验报告_林岳_2024K8009929018.pdf`（8 页，页脚+页码）。
- 插图是矢量 SVG，可用浏览器 / Inkscape / draw.io 直接查看与再编辑；导出 PNG 后可插入 Word 或 PDF。

## 十、2026-09-10 整理记录

清理与归位（均为移动，或删除可再生的构建产物；无内容丢失）：

| 项 | 处理 | 说明 |
|---|---|---|
| `.Xil`、`webtalk.jou/.log`、`xelab.log/.pb`、`xvlog.log/.pb`（根目录） | 删除 | Vivado / xsim 运行期自动生成的临时件，下次运行会重新生成 |
| 5 份 `dump.vcd`（各 exp 的 `testbench/project/` 下 + 同学参考） | 删除 | 仿真波形，合计约 1.02 GB；跑 `make` 可随时重新生成 |
| `prj1/sim/sim_pipe.vvp` | 删除 | iverilog 编译产物，可重新生成 |
| `prj2_exp7_3_2024K8009929018.zip`、`prj2_3_2024K8009929018/` | 移入 `提交物/` | 提交包与其解包核验副本成组存放 |
| `flash_board.sh` / `.tcl` / `.log` | 移入 `上板工具/` | 脚本自定位，移动后用法不变（见 §八） |
| `prj2/sim.log` | 移入 `prj2/logs/sim.log` | 与其余仿真日志同处 |
| `同学参考/exp7-2_myCPU/` | 删除 | 与 `同学参考/exp7-2/myCPU/` 四文件 + patch **逐字节一致**（SHA256 核对），纯重复 |
| `同学参考/*.log`（3 个）、3 个 `.DS_Store` | 移入 `logs/` / 删除 | 验证日志集中存放；`.DS_Store` 是 macOS 元数据垃圾 |
| — | 新建 `实验报告/` | 见 §九 |

根目录现只保留 `README.md` 与 8 个内容目录（课程发布包 / 课程讲义 / 实验报告 / prj1 / prj2 / 提交物 / 上板工具 / 同学参考）。

## 十一、2026-09-15 exp7/8/9 三阶段重构

背景：原先三个实验共用同一份“完整处理冒险”的 RTL，exp8 / exp9 相对上一实验的 patch 因而几乎为空，与课程“每次实验相对上一实验做增量、提交逐文件 patch”的口径不符。本次把 RTL 拆成三个**真实增量**的版本（课程口径：exp7 不考虑冒险 → exp8 cancel + 阻塞 → exp9 前递），并重出各自的 bit：

| 版本 | 相对上一版新增 | myCPU（`prj2/expN/myCPU`） | patch | 功能仿真 |
|---|---|---|---|---|
| exp7 | 五级流水骨架；不处理冒险（`id_stall=0`、无前递、无冲刷） | mycpu_top.v 15367 B | `patch/exp6_to_exp7.patch`（exp6 修正版 → exp7；554 行；仅 alu.v / mycpu_top.v） | PASS，2058995 ns |
| exp8 | `!br_taken` 冲刷解控制冒险 + 阻塞解数据冒险 | 16069 B | `patch/exp7_to_exp8.patch`（66 行；单文件） | PASS，1349305 ns |
| exp9 | EX / MEM / WB 三路前递，只剩 load-use 停一拍 | 16723 B | `patch/exp8_to_exp9.patch`（67 行；单文件） | PASS，639855 ns |

- patch 链逐条验证过：在基线版本上 `git apply` 后与目标版本**逐字节一致**。注意本机 `core.autocrlf=true` 会把产出写成 CRLF 造成假阴性，校验要加 `-c core.autocrlf=false`。
- 对照实验（证明三阶段不能合并）：`prj2/logs/exp7_on_exp8image_fail_20260915.log` —— exp7 的 RTL 放进 exp8 镜像，第 2077 ns 报 `Error!!!`。
- 仿真日志：`prj2/logs/exp{7,8,9}_run.log`（重构后重跑；旧版留档 `*_20260902_fullver.log`）；构建日志 `prj2/logs/exp{7,8,9}_vivado_20260915.log`。
- bit：三版均已重出（`C:\vivado_prj\exp{7,8,9}`，WNS 3.922 / 2.499 / 2.112 ns，时序全部收敛）；旧 bit 备份为 `soc_lite_top_20260908_backup.bit`（exp7）与 `soc_lite_top_20260902_backup.bit`（exp8 / exp9）。
- 提交包：`提交物/prj2_exp8_3_2024K8009929018.zip`、`提交物/prj2_exp9_3_2024K8009929018.zip` 已按新 RTL 打包（结构同 exp7 包：myCPU/ + patch/ + soc_lite_top.bit，zip 条目用正斜杠），并各留一份解包核验目录（哈希逐文件核对一致）；exp7 旧包（09-08 的旧版 RTL + 旧 patch，与新 patch 链基线不一致）暂保留，是否重制见下条复盘。 2026-09-15 交件前把 patch 里的 `100755` 归一为 `100644`（消除 `git apply` 模式告警）并重打包复验：patch 应用后与目标 RTL 逐字节一致、bit 与工程一致；exp8 包 md5 `e36733b817aa`、exp9 包 md5 `e651374f7e5b`，原包备份在 `提交物/backup_20260915/`。
- 工程同步：`C:\vivado_prj\exp{7,9}\myCPU` 已换为新 RTL，旧文件保留 `.bak_20260908` / `.bak_20260902` 后缀。
- 旧包复盘（2026-09-15）：09-08 旧 exp7 包 patch 共 1030 行（+515/−486），其中已有 **24 处 `fwd_` 前递标记**——exp7 一版就把 exp9 的前递写完，这是 exp8 / exp9 patch 几乎为空的根因。检测法：数 patch 里关键机制标记的出现次数（新链为 exp6→exp7 `fwd_`=0、exp7→exp8 `fwd_`=0 且 `_hit`=6、exp8→exp9 才 `fwd_`=12）。旧 patch 对 exp6 基线 `git apply --check` 退出码 0，基线无问题，属“增量一口气写到底”。exp7 旧包保留不删；是否按新链重制，待与老师确认口径后定。
- 仿真流程改口径（2026-09-15 晚，用户要求）：**以后仿真一律在 Vivado（xsim）里做**，WSL iverilog 流程停用（仅作应急）。改动：① 把 `gettrace/`（`golden_trace.txt`）补进 `C:\vivado_prj\exp8\`——工程树原来缺它，tb 打不开参考流会每周期刷 `$fscanf` 错（20 秒 1.5 GB 日志，已清）；② 新增 `run_sim_cli.bat`（`xvlog --incr --relax` → `xelab` → `xsim -R`，参数为实验号）。结果：xsim 全流程跑通 `----PASS!!!`（1349305 ns，与 iverilog 历史结果一致；elapsed 13 s，峰值内存 241 MB），日志 `prj2/logs/exp8_xsim_run.log`；GUI 入口为 Run Simulation（注意自动 tcl 只 `run 1000ns`，要 `restart` + `run -all`）。
- 验收准备（2026-09-15 晚）：`验收准备/exp8_典型指令数据通路与冒险例子.md` —— 先对齐 RTL 命名（rj / rd / rk 字段、rf_raddr/rdata、各级寄存器与 valid / allowin 握手），再给 R 型 / I 型 / 分支跳转的逐级 datapath，最后是两个逐拍冒险例子（数据：add.w 撞车停 3 拍；控制：beq taken 作废两条 + 改道）；同目录 `任务8_五级流水线数据通路.png` 为彩色总图。另：原先的 `任务8_五级流水线与改动_验收准备.md` 按用户要求删除（不看的文档不留）。
- GUI 仿真 `$finish` 不收尾（2026-09-15 晚实测）：Vivado IDE 里 Run Simulation（`xsim tb_top_behav -tclbatch tb_top.tcl`）跑到 1349305 ns 全 20 点 PASS，`$finish` 也在 1350285 ns 打印了，但交互会话不结束，tb 的 `Test is running` 一直刷到 46.5 ms 后**卡死**（日志末行是半截的 `debug_wb_p`，`xsimk` 进程 CPU 停在 267 s、日志 3 分钟不增长）。逐事件比对证明：GUI 这次与 `run_sim_cli.bat` 那次**逐字相同**，属 IDE 收尾问题、不是设计问题。处置：`Stop-Process -Id <xsimk>` 杀掉即可（不动 IDE）；以后一律用 `run_sim_cli.bat`，或在 GUI 里看到 `----PASS!!!` 就手动停。 另：死会话会占着 `xsim` 目录与工程状态，IDE 报“已有仿真在运行/`simulate.log` 被占用”时，先杀残留 `xsimk`；若启动仿真的那个 `vivado.exe` 已卡死（`Stop-Process` / `taskkill` 都杀不掉、仍占着 `simulate.log` 与 `*.wdb`），用 WMI `Invoke-CimMethod -InputObject (Get-CimInstance Win32_Process -Filter "ProcessId=NNNN") -MethodName Terminate` 杀掉（2026-09-15 实测，无需重启）；2026-09-15 20:39 清掉残留后 CLI 复跑一次 PASS（15 s，日志 `prj2/logs/exp8_xsim_run.log`）。GUI 那次还留下 `tb_top_behav.wdb` 1.48 GB（波形库，可删）。
- 板子重烧（2026-09-15 20:22）：板子接回后重烧 exp8 的 bit（`impl_1/soc_lite_top.bit`，md5 `5a4a6484…826b`，与提交包内逐字节一致），`xc7a200t_0`、`End of startup status: HIGH`、`=== PROGRAM DONE ===`；日志 `prj2/logs/exp8_program_20260915b.log`。首连报 `jsn1 may be locked by another hw_server`，清掉残留 `hw_server` / `cs_server` 进程后重试即过（与 §八 记录的现象一致）。
- exp8 阅读版注释（2026-09-15 晚，用户要求）：`prj2/exp8/myCPU/mycpu_top.v` 加了**行尾中文注释**（标 `【阻塞】` / `【cancel】` 两类冒险的处理点，503 → 509 行；剔除注释后代码逐行不变、xvlog 0 ERROR）。**注意**：该文件因此不再与提交包内同名文件逐字节一致（另外三个 `.v` 仍一致），也已与 `C:\vivado_prj\exp8\myCPU\` 分叉 —— 交付包 / 包内 patch / 仿真源一律未动，此文件仅供阅读；原件备份 `%TEMP%\mycpu_top.v.bak_pre_zh_20260915`。
- **exp7 包按新链重制 + 三链闭环复验（2026-09-29，用户要求）**：`提交物/prj2_exp7_3_2024K8009929018.zip` 重打包 = 新链 exp7 RTL（`myCPU/`，mycpu_top.v 15367 B）+ `patch/mycpu_exp7_pipeline_vs_exp6.patch`（新链 exp6→exp7，551 行；**基线 = exp6 修正版单周期 `prj1/sim/ref_sc`**）+ 2026-09-15 重出 bit（WNS 3.922 ns）；解包核验目录 `提交物/prj2_exp7_3_2024K8009929018/`；新包 md5 `0c5175ff…`，旧包（09-08 旧口径，md5 `b2602354…`）改名保留为 `提交物/prj2_exp7_3_2024K8009929018_old20260908.zip`。闭环复验（`git -c core.autocrlf=false apply`）：`ref_sc` + 包内 patch → exp7 包 myCPU；+ `prj2_exp8…zip` 包内 patch → exp8 包 myCPU；+ `prj2_exp9…zip` 包内 patch → exp9 包 myCPU，三段逐字节一致。
- exp6→exp7 patch 基线说明（2026-09-29 取证）：课程包 `课程发布包/exp6.zip` 内 `exp6_wt_answer/myCPU/mycpu_top.v` 为 8415 B **单周期**版；`prj1/sim/ref_sc/` 是其修正版（+2/−1 行），即本次 patch 的基线。`prj1/exp6_wt_answer/myCPU`（15588 B）是当年做旧链 exp7 时留下的**流水线工作稿**，勿与单周期修正版混淆。
- 同学材料（2026-09-29）：exp8/9 提交包 `给同学_exp8or9_提交包_20260929.zip` 放课程根目录（传用；副本与记录见 `同学参考/README.md`）。

## 十二、2026-10-12 exp10/11 课程包入库与超前版对照

- **来源与入库**：`C:\Users\17613\Downloads\download_from_edge_server\exp10.zip`（SHA256 1CB2A569…F0E）、`exp11.zip`（SHA256 C5DE1BF2…33A）已复制入 `课程发布包/`；解出工作副本 `prj2/exp10`（122 文件）、`prj2/exp11`（120 文件）并建 `prj2/logs/`；解包与源 zip 逐文件哈希核对 diff=0。
- **全量扫描：exp10/11 已跑过（超前版）**——`资料库\prj3_7_超前实验_未发布\prj3\` 内为超前完成版（myCPU 四文件已填）：exp10 n1~n36 全 PASS（`资料库\prj3_7_超前实验_未发布\prj3\logs\exp10_run.log`，2026-09-03）、exp11 n1~n46 全 PASS（`资料库\prj3_7_超前实验_未发布\prj3\logs\exp11_run.log`）；bit 已出（`C:\vivado_prj\exp10`、`C:\vivado_prj\exp11`，50 MHz：exp10 WNS+0.925/WHS+0.077、exp11 WNS+0.448/WHS+0.084，0 违规）；均未上板（当时板级未要求）。全量记录见 `资料库\研讨-计算机体系结构_README_20260904历史版.md`。
- **课程包 vs 超前版（官方包口径）对照**：新课程包与官方包 87 个文件不同（func 的 include / init.S / start.S / Makefile / 全部 n*.S / obj 镜像、gettrace 的 golden_trace.txt 与参考核 SimpleLACoreWrapRAM.v、sync_ram.v、create_project.tcl 等），且测试框架与课程 exp7~9 所用框架**逐字节同源**（asm.h、cpu_cde.h、test_config.h、n*.S 样例、sync_ram.v、mycpu_tb.v 均已哈希核对一致）——新课程包 = 课程修订框架 + 实验 10/11 镜像。`mycpu_tb.v` 与官方完全相同，**旧 myCPU 接口可直接复用**；但旧仿真与 bit 基于官方环境，对课程包**不直接生效，需按课程包复验**（测试范围不变：exp10 n1~n36、exp11 n1~n46；2026-10-12 复验通过，见下）。
- **复验结果（2026-10-12）**：超前版 myCPU 已拷入 `prj2/exp10`、`prj2/exp11`，课程包的 testbench / gettrace / inst_ram.mif 已同步进 `C:\vivado_prj\exp10`、`exp11` 工程树；用 `run_sim_cli.bat 10` / `11`（Windows Vivado 2019.2 xsim）复跑：**exp10 n1~n36 全 PASS（1126075 ns）**、**exp11 n1~n46 全 PASS（1419475 ns）**，耗时 16 / 21 s、峰值约 224 MB；日志 `prj2/logs/exp10_xsim_run_20261012.log`、`exp11_xsim_run_20261012.log`。
- **待办**：① 课程包口径重出 bit（工程树已课程化，可跑 `build_all.tcl`）；② 之后再定提交与报告安排。
- **代码仓库（2026-10-13 建立；2026-10-14 重构为「工作区=仓库根」）**：远端 GitHub 公开仓库 https://github.com/tryone667/tmp--calab-ucas （main 分支）。2026-10-14 起本目录整体即仓库工作树；结构、两条线与清理记录见 §十五。

## 十三、2026-10-13 验收记录（exp7~11 全部通过）与 exp11 改进意见

- **验收通过**：截至 2026-10-13，exp7、exp8、exp9、exp10、exp11 全部通过验收（exp10/11 于 2026-10-13 课堂验收通过）。
- **exp11 改进意见（助教，用户转述）**：主题为「接口、模块、实例化、定义重复、信号空置」，具体例子：
  - ① 乘法（的模块化）实现可以放进 ALU、不必都堆在一个 always 里（除法同理，宜做成独立单元）；
  - ② 除法相关信号定义很冗余；
  - ③ 存在定义后未使用的信号，如 `alu_op[18]` 等（div/mod 编码进了 ALU 的 one-hot，但 ALU 根本不使用）；
  - ④ 重复定义，如 `ex_alu_is_div` 与 ID 侧同义判断（`id_is_divmod`）看起来一模一样。
- **处理与复验（2026-10-13 完成）**：
  - ① 除法抽成独立模块：`mycpu_top.v` 内新增 `module divider`（接口 `clk / reset / start / unsign / mod / a / b / busy / result`），`mycpu_top` 内 `u_divider` 实例化；原 FSM 全部收进模块（不再都堆在一个 always 里）。
  - ② 乘法保持 ALU 内实现（`alu.v` 的 `alu_op[15:17]`），本轮补注释、明确与除法的分工。
  - ③ `alu_op` 从 22 位收窄到 **18 位 `[17:0]`**：删掉 ALU 内从不使用的 div/mod 四个 one-hot 位（助教所指 `alu[18]` 一类空置信号）；div/mod 改由单一判断 `id_alu_is_div` 表达。
  - ④ 去重复定义：删除 `id_is_divmod` 与 `ex_alu_is_div = |ex_alu_op[21:18]` 两处同义写法，改为单一定义 `id_alu_is_div` + 流水线寄存器 `ex_alu_is_div`；中途引入又未用的 `id_alu_is_mod` / `ex_alu_is_mod` 一并去除（mod 选择由 divider 内部完成）。
  - ⑤ 全量审计：对 `mycpu_top.v` / `alu.v` 做「定义了但未使用」扫描，无残留。
  - **复验**：Vivado xsim 复跑 exp11，**n1~n46 全 PASS**，`$finish` = **1419475 ns，与改动前完全一致**（逐拍等价）；日志 `prj2/logs/exp11_xsim_run_20261013_clean.log`。改动量：alu.v +4/−4、mycpu_top.v +122/−83（721 → 760 行，净增即 divider 模块）。
- **提交仓库**：exp11 清理后的 RTL、重制的 `exp10_to_exp11.patch` 与复验日志已同步推送（GitHub `tryone667/tmp--calab-ucas`；2026-10-14 起仓库即工作区根目录）。

## 十四、2026-10-13 助教反馈讨论记录（补充留档）

- **来源与话题**：用户就 exp11 乘法/除法/ALU 的信号组织（除法器现为 `mycpu_top.v` EX 段内联状态机；`alu_op[21:18]` 传入 ALU 但内部未使用；顶层另行拼接 div 结果）请助教评估，助教回复如下五个关键词。
- **助教意见（原话关键词，用户转述，逐字）**：接口、模块、实例化、定义重复、信号空置。
- **关联备注（整理时按讨论语境补充，供后续与助教核对）**：
  - **接口 / 模块 / 实例化**：除法器宜做成独立 module（`div_unit`，或将 mul 一并收进的 `mdu`）并显式例化——接口最小化、职责清晰；避免在顶层 EX 内联裸状态机（现 `mycpu_top.v` L489-557 一带）。
  - **信号空置**：`alu_op[21:18]`（div 家族四位独热）在 `alu.v` 内无人消费（其注释即 "handled in EX, not here"）；div 执行期间组合 ALU 的输出被 L606 的结果 mux 丢弃。
  - **定义重复**：同一信息多套表达——div 家族在 `alu_op` 独热与除法器 accept 时翻译出的内部状态位（unsigned / mod / q_neg / r_neg）各存一份；46 条 `inst_*` 与 22 位 `alu_op` 亦属两级重复编码（对应两级译码 / 字段化压缩方向）。
- **相关代码位置（exp11）**：`prj2/exp11/myCPU/mycpu_top.v` L466、L479、L586、L489-557、L597-607；`prj2/exp11/myCPU/alu.v` `alu_op[15..17]`（乘法）、`[21..18]`（未用）。
- **处理结果（2026-10-13 晚，见 §十三）**：div 已独立成 `divider` 模块并显式例化；`alu_op` 中 div/mod 四位直接删除（收窄到 18 位；因 ALU 内无消费者，比「收敛为两位」更彻底）；去重与空置信号清理完成，xsim 复验逐拍等价。`mul/div 共享 MDU`（`mdu` 命名）仍为长线方向，未做。


## 十五、2026-10-14 结构整理：工作区 = 仓库、两条线分离

- **工作区即仓库**：`C:\course_files\2026_autumn\研讨-计算机体系结构\` 自 2026-10-14 起就是 git 工作树（`.git` 在根目录）；以后各机器 **`git pull` 即直接铺平更新**，新机器 `git clone` 到任意目录即得工作区骨架（课程发布包等本地件按需自备）。远端不变：`tryone667/tmp--calab-ucas`。
- **prj 平铺**：`prj3/` 取消，exp10/exp11 并入 `prj2/`（流水线系列 exp7~11 统一下分 exp）；每 exp 收录 `myCPU/` + `patch/`（部分带 `reading/`）；仿真/上板日志集中 `prj2/logs/`；exp6 基线归位 `prj1/exp6/ref_sc`（exp6→exp7 patch 的应用对象，原 `exp7/baseline_ref_sc`）。
- **两条线**：`prj1/`、`prj2/` = 代码线；`viz/`（verilog-viz + datapath-preview）= 可视化线。viz 自包含，对代码只有单向、按需的低耦合（刷新预览时由 `datapath_gen.py` 重新生成），互不改写。
- **删除（用户确认不再需要）**：`同学参考/`、根目录 `给同学_exp8or9_提交包_20260929.zip`（2026-10-13）；`上板工具/`、`验收准备/`、`exp8_RTL设计说明.md`（2026-10-14 追加，说明/验收类文件不再保留；上板流程见 §八，文件可从 git 历史找回）。
- **本地保留但不入库**（见 `.gitignore`）：`ref/`（课程发布包 + 课程讲义，`ref/README.md` 除外）、`提交物/`、各 exp 的 `func/ gettrace/ soc_verify/ module_verify/`（课程包重内容）、历史遗留目录（`prj1/exp6_wt_answer/`、`prj1/sim/`、`prj1/sim_exp1/`、`prj2/exp7_refactor/`）。
- **对应关系**：2026-10-14 之前文档里的 `prj3/exp10`、`prj3/exp11` 即现 `prj2/exp10`、`prj2/exp11`；`prj3/logs` 即现 `prj2/logs`；原独立仓库目录 `loongarch-cpu-labs/` 已并入工作区根（即本目录）。
- **本次重构提交**：`6ed35e9`（远端 main）。