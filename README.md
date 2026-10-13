# loongarch-cpu-labs

LA32R 五级流水 CPU 实验工作仓库（计算机体系结构研讨课 · 实践任务 7~11），用于多台电脑协作。
只收录自己写的东西（RTL / 补丁 / 关键日志 / 文档）；课程发布包与构建产物不入库，见文末说明。

快照：2026-10-13（exp10/11 已于 2026-10-12 按课程发布包完成 xsim 复验）。

## 实验与状态

| 实验 | 内容 | 测试范围 | 仿真 | 提交/上板 | 目录 |
|---|---|---|---|---|---|
| exp7 | 五级流水骨架（不处理冒险，靠镜像插 nop） | n1~n20 | iverilog PASS，2058995 ns（09-15，三阶段版） | 已上板全 PASS（09-15） | `exp7/` |
| exp8 | cancel 解控制冒险 + 阻塞解数据冒险 | n1~n20 | xsim PASS，1349305 ns（09-29） | 已上板（09-15 / 09-29），提交包已交 | `exp8/` |
| exp9 | EX/MEM/WB 三路前递（只剩 load-use 停一拍） | n1~n20 | xsim PASS，639855 ns（09-29） | 已上板（09-29），提交包已交 | `exp9/` |
| exp10 | 用户态运算指令（mul/div 等） | n1~n36 | xsim PASS，1126075 ns（10-12 课程包复验） | bit 待按课程包重出 | `exp10/` |
| exp11 | 转移 + 字节/半字访存 | n1~n46 | xsim PASS，1419475 ns（10-12 课程包复验） | bit 待按课程包重出 | `exp11/` |

## 目录结构

    expN/myCPU/            该实验的 RTL 四文件（alu / mycpu_top / regfile / tools）
    expN/patch/            相对上一实验的 unified diff（用法见下）
    expN/logs/             关键仿真/上板日志（保留原始文件名）
    exp7/baseline_ref_sc/  exp6 修正版单周期基线（exp6_to_exp7.patch 的应用对象）
    exp8/reading/          阅读版 mycpu_top（行尾中文注释，标 【阻塞】【cancel】）
    docs/                  exp8 验收速查、数据通路 PNG、专题实验报告与插图
    tools/                 run_sim_cli.bat（xsim 一键脚本）；flash_board.sh/.tcl（上板）

## 补丁链

    exp6(修正版 ref_sc) --exp6_to_exp7--> exp7 --exp7_to_exp8--> exp8 --exp8_to_exp9--> exp9 --exp9_to_exp10--> exp10 --exp10_to_exp11--> exp11

- 用法：把上一版 `myCPU/` 拷到某目录，在含 `myCPU/` 的目录内执行
  `git -c core.autocrlf=false apply -p1 < patch`。
- exp6→7→8→9 三段与目标 RTL 逐字节一致（2026-09-29 闭环复验过）；`exp9→exp10→exp11` 两段于 2026-10-13 生成并闭环复验（逐字节一致）：9→10 为跨代码谱系两版的直接对比（+242/−149，alu.v / mycpu_top.v），10→11 为连续两版（+111/−48）。

## 在另一台电脑上跑（Windows + Vivado 2019.2）

1. 课程网站下载 expN.zip，解压到本地工作目录（例 `...\prj2\expN`）。
2. 用本仓库 `expN/myCPU/` 覆盖解压出的 `myCPU/`。
3. 把整棵树放到英文路径 `C:\vivado_prj\expN`，首次跑
   `soc_verify\soc_bram\run_vivado\build_all.tcl`（建工程 → 生成 IP → 综合实现出 bit）。
4. 仿真：`...\run_vivado\run_sim_cli.bat N`。
   前提：`C:\vivado_prj\expN` 里有 `gettrace\golden_trace.txt`；
   判据：`----PASS!!!` 与 `Number 8'd36/46 ... Functional Test Point PASS!!!`。
5. 上板：`bash tools/flash_board.sh`（成功判据见脚本内注释）。

`tools/run_sim_cli.bat` 是第 4 步脚本的副本，默认按 `C:\vivado_prj\expN` 路径工作。

## 说明

- 不入库：课程发布包（expN.zip）、func/obj 镜像、波形与 Vivado 临时产物；换来的是一个小仓库。
- `exp8/reading/mycpu_top.annotated.v` 与 `exp8/myCPU/mycpu_top.v`（提交版·干净）仅注释差异。
- 本仓库由本机工作区 `C:\course_files\2026_autumn\研讨-计算机体系结构` 整理，工作区主说明见该目录 README.md。
