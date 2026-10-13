# exp8：典型指令的数据通路 + 冒险例子

> 对照代码：`prj2/exp8/myCPU/mycpu_top.v`。**本文所有名字都是代码里的原名**；课件图上的旧叫法（RA1 / RD1 那套）只在第一节对照一次，后面不再混用。

## 一、先认名字：rj / rd / rk 到底是哪个

### 1.1 指令里的三个寄存器字段（位置固定，看位号）

| 字段 | 位置 | 代码 | 它是谁 |
|---|---|---|---|
| `rj` | `if_inst[9:5]` | `wire [4:0] rj` | **第一源**：基址（ld/st）、被比较的一方（beq/bne）、加数（3R） |
| `rk` | `if_inst[14:10]` | `wire [4:0] rk` | **第二源**，只在 3R 型出现；移位指令（slli.w 等）的移位量也用这个字段 |
| `rd` | `if_inst[4:0]` | `wire [4:0] rd` | 多数指令是**目标寄存器**；`st.w` / `beq` / `bne` 里它是**第二源**（要存的数据、第二个操作数） |

一句话防晕：**汇编写法是「指令 目标, 第一源, 第二源」**。
- `add.w r3, r1, r2` → r3 = r1 + r2（目标在最前）
- `ld.w  r3, r1, 8`  → r3 = mem[r1+8]
- `st.w  r3, r1, 8`  → mem[r1+8] = r3（r3 写在第一个位置，但它是**数据源**，不是目标）

代码里用两个开关说清楚"这条指令要查哪些源"：

- `id_uses_rj  = ~(inst_b | inst_bl | inst_lu12i_w)` —— 除了 b / bl / lu12i.w，其它都要读 `rj`；
- `id_uses_rkd = inst_add_w | inst_sub_w | inst_slt | inst_sltu | inst_and | inst_or | inst_nor | inst_xor | inst_beq | inst_bne | inst_st_w` —— 只有这些有"第二源"（3R 是 `rk`；beq / bne / st.w 是 `rd`）。

结论表（冒险检查就查这些）：

| 指令 | 查 `rj` | 查第二源 |
|---|---|---|
| add.w / sub.w / and / or / ...（3R） | ✅ | ✅（= `rk`） |
| addi.w / ld.w / jirl | ✅ | ❌（第二个操作数是立即数，不是寄存器） |
| st.w / beq / bne | ✅ | ✅（= `rd`） |
| lu12i.w / b / bl | ❌ | ❌ |

### 1.2 寄存器堆：两个读口 + 一个写口（课件 ↔ 代码对照）

| 课件图上 | 代码 | 说明 |
|---|---|---|
| RA1 | `rf_raddr1` = `rj` | 第一读口地址，**永远接 rj** |
| RA2 | `rf_raddr2` = `src_reg_is_rd ? rd : rk` | 第二读口地址；`src_reg_is_rd = inst_beq | inst_bne | inst_st_w`，其它指令取 `rk` |
| RD1 | `rf_rdata1`，代码里又名 `id_rj_value` | 第一读口数据 |
| RD2 | `rf_rdata2`，代码里又名 `id_rkd_value` | 第二读口数据（`rkd` = **rk 或 rd**，就是 RA2 那个口的输出） |
| WA / WD / WE | `rf_waddr = wb_dest`、`rf_wdata = wb_value`、`rf_we = wb_gr_we && wb_valid` | 唯一写口，在 WB 拍写 |

### 1.3 每一级叫什么、握手怎么看

| 级别 | 代码里的寄存器 | 干什么 |
|---|---|---|
| preIF | `pre_if_valid` / `pre_if_pc` | 发取指请求：`inst_sram_addr = pre_if_pc` |
| if_req | `if_req_valid` / `if_req_pc` | 等同步 RAM 的一拍（只存 PC，用来和数据对齐） |
| IF | `if_valid` / `if_pc` / `if_inst` | 指令进这一拍：`if_inst <= inst_sram_rdata` |
| ID | **无寄存器** | 组合逻辑，夹在 `if_*` 和 `ex_*` 之间：译码 + 读寄存器堆 + 判分支 |
| EX | `ex_valid` / `ex_alu_op` / `ex_alu_src1` / `ex_alu_src2` / `ex_rkd_value` / `ex_gr_we` / `ex_mem_we` / `ex_res_from_mem` / `ex_dest` | ALU + **发访存请求** |
| MEM | `mem_valid` / `mem_alu_result` / `mem_gr_we` / `mem_res_from_mem` / `mem_dest` | 访存数据这拍回来 → `mem_value` |
| WB | `wb_valid` / `wb_gr_we` / `wb_dest` / `wb_value` | 写寄存器堆 + 输出 `debug_wb_*` |

- 每级三件套：`valid`（里面有指令）、`allowin`（能收下一条）、`ready_go`（本级算完，本设计恒 1）。
- 冻结就是让下游的 allowin 一路把上游拉 0：`id_allowin → if_allowin → if_req_allowin → pre_if_allowin`。

## 二、R 型（3R）：`add.w rd, rj, rk`

字段：`op_31_26=0x00`、`op_25_22=0x0`、`op_21_20=0x1`、`op_19_15=0x0` → `inst_add_w=1`；`rk = if_inst[14:10]`、`rj = if_inst[9:5]`、`rd = if_inst[4:0]`。

| 级 | 做什么 | 用到的信号 |
|---|---|---|
| preIF | 发请求 | `inst_sram_en = pre_if_valid && pre_if_allowin`、`inst_sram_addr = pre_if_pc` |
| IF | 收指令 | `if_inst <= inst_sram_rdata`、`if_pc <= if_req_pc` |
| ID | 读两个源 + 出控制 | `rf_raddr1 = rj`、`rf_raddr2 = rk` → `id_rj_value` / `id_rkd_value`；控制：`alu_op[0]=1`(ADD)、`src1_is_pc=0`、`src2_is_imm=0`、`res_from_mem=0`、`gr_we=1`、`mem_we=0`、`dest=rd` |
| EX | 相加 | `ex_alu_src1 <= id_rj_value`、`ex_alu_src2 <= id_rkd_value` → `ex_alu_result`；`data_sram_en=0` |
| MEM | 直通 | `mem_value = mem_res_from_mem ? data_sram_rdata : mem_alu_result` = `mem_alu_result` |
| WB | 写回 | `rf_waddr = wb_dest = rd`、`rf_wdata = wb_value`、`rf_we = wb_gr_we && wb_valid = 1` |

## 三、I 型-1（2RI12，运算）：`addi.w rd, rj, si12`

字段：`op_31_26=0x00`、`op_25_22=0xa` → `inst_addi_w=1`、`need_si12=1` → `imm = sext(i12)`，其中 `i12 = if_inst[21:10]`。

和 `add.w` 只有两处不同：

- ID：`src2_is_imm=1` → 第二操作数走 `imm`，**不读第二个寄存器**（`id_uses_rkd=0`，`rf_raddr2` 读出来的东西不用）；
- EX：`ex_alu_src2 <= imm`。

其余相同（`alu_op` 也是 ADD、`gr_we=1`、`dest=rd`、WB 写 `rd`）。

## 四、I 型-2（2RI12，访存）：`ld.w` / `st.w`

字段：`ld.w` = `op_31_26=0x0a` + `op_25_22=0x2`；`st.w` = `op_31_26=0x0a` + `op_25_22=0x6`；偏移都是 `si12 = if_inst[21:10]`。
两条都是**请求在 EX 发、数据下一拍（MEM）回**（同步 RAM 的一拍延迟）。

**`ld.w rd, rj, si12`（内存 → 寄存器）**

| 级 | 做什么 |
|---|---|
| ID | `rf_raddr1 = rj`；`src2_is_imm=1`（偏移）、`res_from_mem=1`、`gr_we=1`、`dest=rd` |
| EX | `ex_alu_result = id_rj_value + imm`（= 地址）；**当拍发读请求**：`data_sram_en = ex_valid && (ex_mem_we || ex_res_from_mem) = 1`、`data_sram_we=0`、`data_sram_addr = ex_alu_result` |
| MEM | `mem_res_from_mem=1` → `mem_value = data_sram_rdata` |
| WB | 写 `rd = mem_value` |

**`st.w rd, rj, si12`（寄存器 → 内存）**

| 级 | 做什么 |
|---|---|
| ID | `rf_raddr1 = rj`、`rf_raddr2 = rd`（`src_reg_is_rd=1`）→ 基址 = `id_rj_value`，要存的数据 = `id_rkd_value`；`src2_is_imm=1`、`mem_we=1`、**`gr_we=0`** |
| EX | `ex_alu_result = 基址 + imm`（= 地址）；要存的数据随流水线进 `ex_rkd_value`；当拍发写请求：`data_sram_en=1`、`data_sram_we=4'hF`、`data_sram_addr = ex_alu_result`、`data_sram_wdata = ex_rkd_value` |
| MEM / WB | 不回写寄存器（`gr_we=0`） |

## 五、分支 / 跳转（都在 ID 拍判定）

| 指令 | 字段 | ID 拍算出什么 |
|---|---|---|
| `beq / bne rj, rd, offs16` | `op=0x16 / 0x17`，`offs16 = if_inst[25:10]` | `rf_raddr1=rj`、`rf_raddr2=rd` → `rj_eq_rd`；`br_target = if_pc + sext(offs16)<<2`（即 `br_offs`） |
| `b` | `op=0x14`，`i26 = {if_inst[9:0], if_inst[25:10]}` | 无条件 taken；`br_target = if_pc + sext(i26)<<2`；不读寄存器 |
| `bl` | `op=0x15`，同上 `i26` | 同 `b`；另外 `dest=r1`（`dst_is_r1=1`）、`src2_is_4=1` → `imm=4`、`src1_is_pc=1`，EX 算 `if_pc + 4` 当链接地址写 r1 |
| `jirl rd, rj, offs16` | `op=0x13`，`offs16 = if_inst[25:10]` | `br_target = id_rj_value + sext(offs16)<<2`（**用寄存器算**）；`gr_we=1`、`dest=rd`（汇编器把 rd 写成 r1） |

`br_taken` 一行（代码原样）：

```
br_taken = ((inst_beq && rj_eq_rd) || (inst_bne && !rj_eq_rd)
            || inst_jirl || inst_bl || inst_b) && if_valid && ~id_stall
```

注意最后那个 `~id_stall`：**源操作数没就绪就不许判**，否则会拿旧值误判分支（PPT 原话：仅当译码级分支指令源操作数就绪时才能取消）。

## 六、exp8 新增的代码清单（对照 `patch/exp7_to_exp8.patch`，66 行）

改动全部落在 `myCPU/mycpu_top.v` 一个文件里，净增约 14 行，分两件事：**控制冒险 cancel**（3 处，每处 1 行）和**数据冒险 block**（1 块，11 行）。exp7 的骨架、译码、ALU、访存、写回一行未动。本节行号均指 `prj2/exp8/myCPU/mycpu_top.v`。

### 6.1 控制冒险 cancel：把 `br_taken` 扇出到前端三个位置

| # | 位置 | exp7 原样 | exp8 改后 | 行号 |
|---|---|---|---|---|
| ① | 接收取指请求 | `if_req_valid <= pre_if_valid;` | `if_req_valid <= pre_if_valid && !br_taken;` | `:84` |
| ② | 更新 if_req 的 PC | `else if (if_req_allowin && pre_if_valid)` | `else if (if_req_allowin && pre_if_valid && !br_taken)` | `:92` |
| ③ | if_req → IF 放行 | `wire if_req_to_if_valid = if_req_valid;` | `wire if_req_to_if_valid = if_req_valid && !br_taken;` | `:105` |

三处是同一个 `br_taken` 扇出到三个不同位置，分工见第八节：① 拦正要发的请求，② 拦住 PC 更新，③ 作废已受理、待进 IF 的那条。

### 6.2 数据冒险 block：新增 11 行

改前 exp7 只有一行 `wire id_stall = 1'b0;`，exp8 换成：

```verilog
wire [4:0] id_src2_reg = src_reg_is_rd ? rd : rk;

wire id_ex_hit  = ex_valid  && ex_gr_we  && (ex_dest  != 5'b0)
               && ( (id_uses_rj && (ex_dest  == rj)) || (id_uses_rkd && (ex_dest  == id_src2_reg)) );
wire id_mem_hit = mem_valid && mem_gr_we && (mem_dest != 5'b0)
               && ( (id_uses_rj && (mem_dest == rj)) || (id_uses_rkd && (mem_dest == id_src2_reg)) );
wire id_wb_hit  = wb_valid  && wb_gr_we  && (wb_dest  != 5'b0)
               && ( (id_uses_rj && (wb_dest  == rj)) || (id_uses_rkd && (wb_dest  == id_src2_reg)) );

wire id_stall = if_valid && (id_ex_hit || id_mem_hit || id_wb_hit);
```

逐项读（`:334` ~ `:343`）：

- `id_src2_reg`：把第二源统一成寄存器号——3R（`add.w` 等）取 `rk`，`beq` / `bne` / `st.w` 取 `rd`，开关就是译码里现成的 `src_reg_is_rd`（`= inst_beq | inst_bne | inst_st_w`）。
- `id_*_hit`：在途生产者（EX / MEM / WB 三级）会写寄存器（`*_gr_we`）、目的寄存器号等于本条要读的源（`rj` 或 `id_src2_reg`）、且不是 r0（`!= 5'b0`，写 0 号无效，不能误触发停顿）。
- `id_stall`：三路命中任一即停，再串 `if_valid`——IF 里没指令时不瞎停。

### 6.3 没改、但被激活的一行

`br_taken` 末尾的 `&& ~id_stall`（`:328`）在 exp7 就有，当时 `id_stall` 恒 0、等于没写；exp8 里它才真正起作用——意思是**正在停住的指令不判分支**（这拍源寄存器读到的可能还是旧值，判了会误 taken / not-taken）。

## 七、数据冒险：block 的处理方式与流程

### 例子：`add.w r2,r1,r1` 紧跟 `add.w r3,r2,r2`

I0 写 r2，I1 立刻用 r2。逐拍（I0 已在流水线里，I1 紧随其后）：

| 拍 | I0 在哪 | I1 在哪 | 命中信号 | 结果 |
|---|---|---|---|---|
| T | IF（`if_inst=I0`） | RAM 输出里（还没进 IF） | — | I0 译码，晚上拍进 EX |
| T+1 | EX（`ex_dest=r2`、`ex_gr_we=1`） | IF（`if_inst=I1`） | `id_ex_hit=1` | `id_stall=1` → I1 冻在 IF |
| T+2 | MEM（`mem_dest=r2`） | 冻住 | `id_mem_hit=1` | 继续停 |
| T+3 | WB（`wb_dest=r2`） | 冻住 | `id_wb_hit=1` | 继续停；本拍末 `rf_we=1` 把 r2 写进寄存器堆 |
| T+4 | 已出流水线 | 恢复 | 三个 hit 全 0 | ID 读到**新** r2，晚上拍进 EX |

- 命中判定（代码原样，mem / wb 同理）：

```
id_ex_hit  = ex_valid  && ex_gr_we  && (ex_dest  != 5'b0)
          && ((id_uses_rj && (ex_dest  == rj)) || (id_uses_rkd && (ex_dest  == id_src2_reg)))
id_src2_reg = src_reg_is_rd ? rd : rk
```

- 做什么：`id_stall = if_valid && (id_ex_hit || id_mem_hit || id_wb_hit)` → `id_allowin=0` → 一路拉低 `if_allowin / if_req_allowin / pre_if_allowin`：preIF 的 PC、if_req、IF **全不动**，EX 及以后照常往前走（所以 I0 该进 MEM 进 MEM、该写回写回）。
- 代价：**停 3 拍**（EX / MEM / WB 各一拍）。exp9 加了 EX / MEM / WB 三路前递之后，这种 ALU→ALU 的撞车**一拍都不用停**，只有 load-use 停 1 拍——这就是 exp8 与 exp9 的差别。
- 为什么 WB 也要算进 hit：本版没有前递，寄存器堆是"WB 拍末才写进去"的，WB 这一拍 ID 读到的还是旧值，所以必须再等一拍。
- 停顿时取指为什么不错位：`inst_sram_en = pre_if_valid && pre_if_allowin`，冻结期间不发新请求，同步 RAM 的输出保持上一次读的值，正好和冻结的 `if_req_pc` 一一对应；恢复后 IF 采到的还是同一条指令。

### 处理方式：ID 级阻塞（原地停住，不插指令、不清流水）

一句话分工：**前端冻住，后端照走**。

1. ID 组合逻辑当拍算出三个 hit → `id_stall = 1`；
2. `id_ready_go = ~id_stall`（`:344`）= 0 是起点，随后沿握手链一路反压：
   `id_allowin`（`:346`）→ `if_allowin`（`:103`）→ `if_req_allowin`（`:45`）→ `pre_if_allowin`（`:46`），每级都是"本级不算完，就不收下一条"；
3. 于是这四个位置的分寄存器本拍一律不更新：`pre_if_pc`、`if_req_valid` / `if_req_pc`、`if_valid` / `if_pc` / `if_inst`；
4. EX 及以后不受影响：`id_to_ex_valid = if_valid && id_ready_go`（`:347`）= 0，只是本拍不给 EX 送新指令；已经在 EX / MEM / WB 的指令照常前进——生产者该发访存发访存、该写回写回；
5. 生产者在 WB 拍末把值写进寄存器堆（`rf_we = wb_gr_we && wb_valid`），下一拍它的 `wb_valid` 已消失，三个 hit 全归零 → `id_stall = 0` → 前端解冻，ID 重新组合读寄存器堆，这一拍读到的就是新值。

**停几拍看"撞车时生产者在哪一级"**，不是固定值：

| 撞车时生产者在 | 消费者在哪 | 停几拍 |
|---|---|---|
| EX | IF（紧邻） | 3（EX / MEM / WB 各一拍） |
| MEM | IF（隔一条） | 2 |
| WB | IF（隔两条） | 1 |
| 已出流水线 | — | 0 |

相邻 `add.w` 依赖 `add.w` 是最坏情况，3 拍；指令隔得越远代价越小。

再补两点容易问到的：

- **r0 和不用的源不会误停**：`*_dest != 5'b0` 排除写 0 号寄存器；`id_uses_rj` / `id_uses_rkd` 保证只查这条指令真正要读的源——`addi.w` 只查 `rj`（`id_uses_rkd = 0`），`lu12i.w` / `b` / `bl` 两个都不查。
- **停顿期间不判分支**：`br_taken` 里串了 `~id_stall`（`:328`）；否则停住这拍源寄存器可能还是旧值，分支会被误判 taken / not-taken。

## 八、控制冒险：cancel 的处理方式与流程

### 例子：`beq` 判成 taken

设 T 拍 `if_inst = beq` 且 `br_taken=1`（同时 `if_valid=1`、`~id_stall`）。**同拍**做三件事（下一小节按门控拆成四行对照）：

1. RAM 这一拍的输出是错路的 I1（请求是上一拍发的）→ `if_req_to_if_valid = if_req_valid && !br_taken = 0` → 下一拍**不把它收进 IF**；
2. preIF 这一拍刚发出去的错路请求（I2）作废 → `if_req_valid <= pre_if_valid && !br_taken = 0`；
3. `pre_if_pc <= br_target` → 下一拍 preIF 改发目标的请求。

| 拍 | 发生什么 |
|---|---|
| T | beq 在 ID 判定，上面三件事同拍做完 |
| T+1 | preIF 发目标地址的请求；IF / ID 是空泡 |
| T+2 | 目标的指令数据还在 RAM 里（取指是两拍一级） |
| T+3 | 目标指令进 IF → ID 译码 → 晚上拍进 EX |

- 代价：**2 拍空泡**（错路的两条指令各占一格）。
- 只作废 IF / if_req 两级就够了：它们是分支后面唯一被错取进来的两条。

### 处理方式：ID 拍一次判完，同拍 cancel + 改道

`br_taken`（`:323` ~ `:328`）在 ID 组合逻辑里算出：是 `beq` / `bne` / `jirl` / `bl` / `b` 之一、判定要跳、`if_valid`、且 `~id_stall`。它一跳，同一拍做四件事：

| # | 动作 | 代码 | 拦住的是谁 |
|---|---|---|---|
| ① | 不接收新取指请求 | `if_req_valid <= pre_if_valid && !br_taken`（`:84`） | `pre_if_pc` 这拍正发的那条（分支后第 2 条，`if_pc + 8`） |
| ② | 不更新 if_req 的 PC | `else if (if_req_allowin && pre_if_valid && !br_taken)`（`:92`） | 同上，防止 PC 被错路径值写进去 |
| ③ | 不放行进 IF | `if_req_to_if_valid = if_req_valid && !br_taken`（`:105`） | 上一拍已受理、这拍数据正回来的那条（分支后第 1 条，`if_pc + 4`） |
| ④ | 改道 | `if (br_taken) pre_if_pc <= br_target`（`:63`） | 下一拍起 preIF 发的就是目标地址 |

`br_target`（`:330`）：`beq` / `bne` / `bl` / `b` 是 `if_pc + br_offs`；`jirl` 是 `id_rj_value + jirl_offs`。

**为什么三处门控要一起来**：`br_taken` 出现在 ID 拍，此刻前端同时有三条指令处在不同位置——`if_req` 寄存器里的（第 1 条）、正在发出的请求（第 2 条）、`pre_if_pc` 里准备下一拍的地址。漏掉任何一处，就会有一条错路径指令活下来。

**逐拍**（T 拍 `if_inst = beq` 且 taken）：

| 拍 | preIF 发什么 | if_req 里 | IF 里 | 备注 |
|---|---|---|---|---|
| T | `if_pc + 8`（错路） | `if_pc + 4`（错路） | beq（在 ID 判定） | ①②③④ 同拍生效 |
| T+1 | `br_target` | 空 | 空泡 | `if_valid = 0` |
| T+2 | `br_target + 4` | `br_target` | 空泡 | 目标的数据这拍才回来 |
| T+3 | … | … | 目标指令进 IF | 下一拍进 ID，流水恢复 |

**代价：2 拍空泡。**

延伸四点：

- **错路径那条读请求不用管**：`inst_sram_en`（`:70`）不带 `br_taken`，T 拍第 2 条的读请求照样发到指令 RAM，但它是纯读、无副作用，数据回来时 `if_valid` 已是 0，直接丢弃——这叫"取消"，不是"撤销"。
- **错路径指令没有副作用**：它最多走到 IF 就被拦住，从没进过 ID / EX，也就从没发过访存写请求。
- **不用清前面几级**：ID 是组合逻辑（无寄存器），IF / if_req 两级已是错路径能到的最远处；EX 及以后装的是分支之前的指令，本来不该动。
- **分支没跳**：`br_taken = 0`，门控全开，前端顺取，零代价；`bl` / `jirl` 还要把自己（`if_pc + 4` 链接地址）送进 EX 写 r1——那是 EX 的事，与 cancel 无关。

## 九、exp7 / exp8 / exp9 一句话边界

- exp7：五级流水骨架，**不处理冒险**（`id_stall` 恒 0、无 cancel），镜像要插 nop；
- exp8（本版）：**cancel 解控制 + 阻塞解数据**，无前递；
- exp9：把阻塞换成 EX / MEM / WB 三路前递，只剩 load-use 停一拍。

端到端数字（同一套 n1~n20 测试）：exp7 2058995 ns、exp8 1349305 ns、exp9 639855 ns。
