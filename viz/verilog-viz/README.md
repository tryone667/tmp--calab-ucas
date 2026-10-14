# Verilog 可视化工具（VSCode 插件）

- 建立：2026-10-09（体系结构方向的 idea）
- 状态：想法登记，细节待补

## 想法记录（原话）

"我体系结构想做一个 vscode 插件里可视化可用手调整的 verilog 可视化工具"

## 关键词拆解

- 载体：VSCode 插件
- 输入：Verilog（RTL？网表？待定）
- 特征：可视化 + 可用手调整（图形化编辑？拖拽？与代码双向同步？——待澄清）

## 待明确

- [ ] "用手调整"的粒度：布局（仅视图）还是结构（反向生成 Verilog）？
- [ ] 可视化对象：模块层次图 / 数据通路 / FSM / 波形 / 时序？
- [ ] 与现有工具的关系：DigitalJS、netlistsvg、Yosys（JSON 后端）、Wavedrom、TerosHDL 等（待调研对比）
- [ ] 差异化卖点：现有工具大多"只读渲染"，可手调 + 双向同步是不是空白？

## 风险

- 图→代码反向生成的正确性与幂等（round-trip 问题）
- 大设计（>万门）渲染性能
- 解析前端成本：自写 parser vs 借力 tree-sitter / slang / yosys

## 日志

- 2026-10-09 建目录 + 想法登记

## 调研结果（2026-10-12，大鲸鱼代查）

### 0. "draw 这玩意"的两种可能

- **draw.io 系**：draw.io 本身不懂 Verilog，靠桥接工具双向转换——
  `verilog2drawio`（读 .v 生成 .drawio 图：端口分组 + 子模块连线，用 hdlparse 解析）；
  `drawio-hdl-builder`（反过来：在 draw.io 里画层级图，一键生成 VHDL/Verilog 骨架）。
  拖拽体验好，但与代码是文件级往返、不同步。
- **DigitalJS 系**：真正"能画、能点、能仿真"的电路可视化（见下）。

### 1. 可视化 Verilog 的三条技术路线

| 路线 | 代表 | 机制 | 特点 |
| --- | --- | --- | --- |
| A. 模块框图（RTL 级） | verilog2drawio / VerilogVisualization | 轻解析（模块/端口/例化）→ 画框连线 → SVG/drawio | 简单可行，信息浅 |
| B. 网表原理图（综合后） | netlistsvg（829★，MIT） | Yosys write_json → JSON 网表 → ELKjs 自动布局 → SVG | 静态、可读性好（TerosHDL 在用） |
| C. 交互式电路 | DigitalJS（783★，BSD-2） | Yosys → yosys2digitaljs → 电路 JSON → jointjs 渲染 + 实时仿真 | 可交互可仿真，教学定位（CSERC 2019 论文） |

### 2. 竞品/近亲扫描（2026-10-12）

| 项目 | 状态 | 与我们的关系 |
| --- | --- | --- |
| sv-pathfinder（63★，很活跃） | VSCode 插件：设计层级导航 + 原理图查看（可进层级、跳源码）+ 波形联动 | 最像"成品"，但偏只读导航 |
| DigitalJS-Schematic-Viewer（1★） | VSCode 插件：一键综合 + 交互仿真 + 波形面板；综合可走**本地 WASM（@yowasp/yosys）零安装** | 技术可行性最强证据 |
| OpenCircuitX（173★） | 开源 EDA 平台：编辑器 + 电路画布 + RTL 查看器 | 大而全，参考 |
| yuyichao.digitaljs | 市场老插件，捆绑旧版 DigitalJS | 已过时 |

### 3. 结论：能做；"手调 + 回写"是空位

积木与许可证（均已核实）：

- 综合/展开：Yosys（ISC）或 **@yowasp/yosys（ISC，WASM，免安装，Node Worker 里跑）**
- 转换：yosys2digitaljs（BSD-2）｜渲染/仿真：DigitalJS（BSD-2）｜静态图：netlistsvg（MIT）
- 布局：ELKjs（EPL-2.0 系，分发时再确认）｜解析（路线 A）：hdlparse / tree-sitter-verilog / slang

MVP 分层：

- **MVP-A（最小交付）**：RTL 模块框图——解析模块/例化 → ELK 自动布局 → VSCode Webview 展示；
  支持拖拽微调（布局存 layout.json）+ 点击跳源码。不依赖 Yosys。
- **MVP-B（进阶）**：接 Yosys（WASM）→ 网表 → DigitalJS 渲染 + 仿真（参考 DigitalJS-Schematic-Viewer）。
- **MVP-C（差异化/研究点）**：图↔代码双向——在图上做受控结构编辑（例化/连线）→ 回写对应代码段 →
  用 iverilog/Yosys 回编译验证。现存工具几乎没人做"编辑回写"，是空白也是难点。

### 4. 日志

- 2026-10-09 建目录 + 想法登记
- 2026-10-12 完成工具/技术/许可证调研；确认可做，路线与 MVP 分层如上
- 2026-10-12 端到端 demo 完成：diadatp/mips_cpu（MIT，32 位单周期 MIPS）只跑一条 add（仿真 PASS，$3=5+3=8）；
  yowasp-yosys（免安装 WASM）→ netlistsvg 静态原理图 + DigitalJS 交互式查看器（可切换模块、ALU 可直接输入驱动）。
  产物在 `demo-single-cycle/`；关键坑：top 无输出端口 → opt/memory 会把逻辑当死代码清空，可视化流程用 `proc; memory_collect` 直出。

## 用户与市场速记（2026-10-12，随手记）

- 用户四类：芯片设计/验证工程师（公司付钱，Verdi/VCS 几十万级）｜FPGA 工程师（Vivado）｜学生/教师（不付钱但人多）｜爱好者（Yosys/Verilator/GTKWave）。
- "有人做过吗"：有——
  - 商业标杆：Verdi（nTrace/nWave/nSchema 三方联动调试）；Vivado（schematic + simulation 联动）。
  - 教育标杆：Ripes（3445★，内置处理器模型可视化，计组课常用）；Logisim Evolution（画电路级）。
  - 开源边角料：TerosHDL(741★) / Vaporview(361★) / sv-pathfinder(63★) / DigitalJS-Schematic-Viewer(1★)。
- 为什么没有开源全家桶：①"任意 SystemVerilog"的 80→95 墙（前端/语义/宏）；②商业上早就有人做且卖得贵；
  ③"装配+修 UI"不产出论文，没人养胶水；④RTL↔网表↔波形↔源码之间没有标准映射层。
- 定位结论：走**教育向**。"自带任意 RTL 的可视化"是真空（Ripes 只认内置模型、Vivado 太重）；
  差异化 = BYO-RTL + 指令级可视化 + 真仿真值回标 + 中文 + VSCode 零安装。
- 用户量级预期（现实）：好插件一年几百~几千安装；被课程采用则年增几百学生；没有百万级故事——对课设/CHI/简历足够。
- 待办：竞品对比矩阵（Ripes / Verdi / Vivado / sv-pathfinder / 我们）。
- 2026-10-12 ref_sc（课程 LA32 单周期）全管线跑通：一条命令 tools/build.py --src ... --top mycpu_top --out ... 出网页（180 器件 / 337 连线 / 6 子模块）。
  步进验证通过：clk 翻转 8 次后 pc/valid/reset 三个寄存器全部更新（pc=0x1BFFFFFC，即源码里的复位技巧值）——"每拍"在真实课程代码上成立。
  截图：demo-la32-ref_sc/visual/shot_{top,alu,regfile}.png；在线版：http://127.0.0.1:8124/（本地服务 PID 21176）。
  待办：① 布局缩放/适配（顶层图偏宽）② 接外部 inst/data 存储器后才能"跑指令" ③ MIPS32 / RISC-V32 待跑（材料已从 2026spring 压缩包解到 staging/letusmakecpu）。
- 2026-10-12 UI 完善：左侧可折叠边栏（VSCode 风）、滚轮缩放（rAF 合并 + freeze/unfreeze 批提交）、按钮缩放、空白拖拽平移、自动适配。
  修复拖拽元件/连线"疯狂抽搐"：根因 = JointJS 拖拽时每次鼠标移动触发 render:done，而 DigitalJS 内置 fitToContent + 未加锁的自适应钩子每帧重置视图，与拖拽互相打架；
  解法 = 卸载内部钩子（circuit.stopListening）+ 自适应加 3 秒窗口（窗口内跟随渲染重适配、之后永久锁定）+ 鼠标按下期间禁止适配。实测拖拽 1:1 跟手、视图稳定。
  注：拖拽后按"适配"可一键回归全局视图；"固定布局"勾选可防止误拖。
- 2026-10-12 可读性优化：新增"紧凑布局"（默认开，位置整体缩至 62%，可开关）+ 连线变细变淡（#b6b6b6/1px）。
  效果：内容 5514x3710 -> 3487x2345，适配缩放 0.183 -> 0.29，元件显著变大。切换开关自动重适配。
- 2026-10-12 交互三件套：①悬停高亮（元件/线悬停 → 相连网络变粉红）②紧凑度滑杆（40-100% 实时，默认 62%）③子模块钻入（悬停模块盒出现🔍 → 点击进入；顶部面包屑返回；下拉框同步）。
  注：双击钻入在此 jointjs 版本无事件支持（实测 + 合成事件均不触发），统一用 🔍/下拉框；footer 提示文案已更新。
- 2026-10-12 exp7（SoC 集成实验）整机跑通：13 个子模块，顶层出图 = cpu / bridge_1x2 / inst_ram / data_ram / confreg 五块架构图；钻入验证：顶层 → mycpu_top（→ alu/regfile 可继续）。
  - 过程中修了课程文件两个问题：① sync_ram.v 的 `wdata` 方向笔误（声明 output、实为 input；iverilog 宽容、Yosys 判多驱动）② 字节使能多写口 RAM 写法转换器不支持 → 演示版简化为整字写。
  - build.py 新增 --chparam 支持（用于 soc_lite_top 的 SIMULATION 参数）。
  - 新发现待打磨：参数化模块名丑（$paramod\confreg\SIMULATION=...）；盒子重叠时🔍可能被遮挡；个别 SVG path 渲染警告（非致命）。
- 服务端口：8123=MIPS demo ｜ 8124=LA32 ref_sc ｜ 8125=LA32 exp7 整机。
- 2026-10-12 【自动debug · 里程碑1 完成】离线跑通 exp7 老师的完整 testbench：iverilog(WSL) 编译 + vvp 仿真 21 秒，**20/20 功能测试点全过、0 错误、----PASS!!!**。产物在 sim-exp7/（run.log 15KB / dump.vcd 250MB 全量波形 / sim.vvp）。
  - 运行方式：原文件不动做运行副本，仅修相对路径（mif 与 golden_trace）。注意：**iverilog 对 sync_ram 的 wdata 方向笔误完全宽容**（照跑照过），该笔误只卡 Yosys——两种工具链的容忍度差异实锤。
  - 日志格式已归档（L1 解析器目标）：`----[t] Number 8'dNN Functional Test Point PASS!!!`；错误分支 `[t] Error!!!` + `reference: PC/wnum/wdata` + `mycpu: ...`；结尾 `Test end!` + `----PASS!!!` 或 `Fail!!!Total N errors!`；另有每 10000ns 心跳 `Test is running, debug_wb_pc = 0x...`（可当 PC 时间线素材）。
  - 下一步：① L1 解析器（run.log → 结构化 JSON → 页面横幅）② 造一个 FAIL 样本验证错误分支解析 ③ L3 嫌疑锥高亮（从 debug_wb_* 出发反向遍历网表）。

## 状态快照（2026-10-12 暂停点，等需求梳理）

- 已完成：可视化管线（Yosys→DigitalJS，出交互框图 + 模块钻入 + 悬停高亮 + 紧凑度滑杆）
  ｜ 三套样例跑通：GitHub MIPS 教材核、课程 LA32 ref_sc、课程 LA32 exp7 整机 SoC
  ｜ 离线仿真里程碑1：exp7 老师 tb 在 iverilog 下 **20/20 PASS**（sim-exp7/run.log）
- 自动debug 待办：① L1 日志解析器（run.log→结构化 JSON→页面横幅） ② FAIL 样本验证错误分支 ③ L3 嫌疑锥高亮
- 等拍板的开放问题：
  1) 错误定位呈现形态：页面横幅 / 时间线 / 图上高亮，做到哪一级
  2) 支持范围：先只吃 exp7 这类 tb，还是要通用 tb（依赖文件、多时钟、X 语义）
  3) 与课程验收流程的接法：提交物 / 报告导出 / 演示流程
- 本地服务：8123=MIPS ｜ 8124=LA32 ref_sc ｜ 8125=LA32 exp7
- 2026-10-12 【自动debug · 里程碑2-4 完成】离线"失败复现器"全链路打通：
  - 失败样本：副本 alu.v 埋 or→and 的 bug → 仿真在 t=35617ns 报错（期望 r12←0x01000001，实际←0x00000000）。
  - debug-tools/analyze.py：run.log→结构化 JSON + 错误卡片；PC→inst_ram.mif 行号取指令（0x001569AC = or r13,r26→r12，三重一致性验证 ✓）；
    tb 副本注入打印探针（32 寄存器快照，VCD 探针被 Icarus 的 vmiMemory 限制否决）。
  - 自动校验神来之笔：r13|r26=期望值、r13&r26=实际值 —— 直接指纹出"or 被实现成 and"。
  - viewer 集成：页面左上角仿真卡片（PASS 绿 / FAIL 红），数据来自 sim_data.js。
  - 端口：8123 MIPS ｜ 8124 LA32 ref_sc ｜ 8125 LA32 exp7(PASS) ｜ 8126 LA32 exp7-buggy(FAIL 演示)。

## 在新机器上跑起来（跨机器指南，2026-10-13）

依赖：Python 3.10+、Node.js；仿真需要 WSL/Ubuntu + iverilog；综合需 `pip install yowasp-yosys`；`tools/` 首次使用先 `npm install`（yosys2digitaljs / digitaljs / puppeteer-core）。

1) **Verilog → 交互框图**（任意中小设计）：
   `python tools/build.py --src <源码目录> --top <顶层模块> --out <输出目录>`
   产物在 `<输出目录>/web/`，用静态服务打开 `viewer.html`（如 `python -m http.server`）。
   已有演示：`demo-single-cycle`（MIPS 教材核）、`demo-la32-ref_sc`（LA32 单周期）、`demo-la32-exp7`（整机 SoC + PASS 卡片）、`demo-la32-exp7-buggy`（FAIL 错误卡片演示）。

2) **离线跑课程 testbench**（以 exp7 为例）：
   `cd sim-exp7 && iverilog -o sim.vvp -s tb_top rtl/*.v tb/mycpu_tb.v && vvp sim.vvp > run.log`
   注：`sim-exp7*` 已含复跑所需的 `inst_ram.mif / data_ram.mif / golden_trace.txt`（课程包数据副本，仅本地仿真用，来自 func/obj 与 gettrace）。

3) **失败自动定位**（离线、零 AI、纯确定性）：
   `python debug-tools/analyze.py sim-exp7-buggy --emit-web demo-la32-exp7-buggy/visual/web`
   产出 `sim_result.json` + 错误卡片（报错指令 / 操作数 / 期望 vs 实际 / 自动校验），viewer 左上角显示。

仓库未收录：`node_modules/`、波形 `*.vcd`、编译产物 `*.vvp/*.out`、大数据中间产物 `visual/rtl.json / digitaljs.json`（均可再生成）。
