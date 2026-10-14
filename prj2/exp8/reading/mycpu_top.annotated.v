// ============================================================================
// 5-stage pipelined LoongArch LA32R CPU (preIF -> IF -> ID -> EX -> MEM -> WB)
// Experiment: exp8 pipeline CPU (cancel for control hazards, blocking for data)
//  - data hazard : ID blocks until the producer has written back the regfile
//  - control hazard : branch resolved in ID; taken branch cancels the
//                     wrong-path insts in if_req/IF and redirects the PC
//  - inst/data RAM : synchronous read model (rdata returns one cycle after the
//                    request), matching the soc_bram sync_ram / BRAM flow
// ============================================================================
// ---------------------------------------------------------------------------
// 本版要点：数据冒险用【阻塞 block】、控制冒险用【取消 cancel】。
// 下面每行右侧的中文就是该行的作用，标了【阻塞】【cancel】的即两类冒险的处理点：
//   【阻塞】ID 要读的源与在途(EX / MEM / WB)写目标撞车 → 冻住 ID 及上游，等 WB 拍末写回
//   【cancel】分支在 ID 判定 taken → 作废已错取的两条 + 改道 pre_if_pc
// ---------------------------------------------------------------------------
module mycpu_top(
    input  wire        clk,
    input  wire        resetn,
    // inst sram interface
    output wire        inst_sram_en,
    output wire [3:0]  inst_sram_we,
    output wire [31:0] inst_sram_addr,
    output wire [31:0] inst_sram_wdata,
    input  wire [31:0] inst_sram_rdata,
    // data sram interface
    output wire        data_sram_en,
    output wire [3:0]  data_sram_we,
    output wire [31:0] data_sram_addr,
    output wire [31:0] data_sram_wdata,
    input  wire [31:0] data_sram_rdata,
    // trace debug interface
    output wire [31:0] debug_wb_pc,
    output wire [ 3:0] debug_wb_rf_we,
    output wire [ 4:0] debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata
);

reg reset;
always @(posedge clk) reset <= ~resetn;   // 复位同步一拍，reset 高有效

// ============================ preIF fetch request ============================
reg         pre_if_valid;   // preIF 级 valid：本轮要发的取指请求
reg  [31:0] pre_if_pc;   // preIF 级的请求地址（inst_sram_addr 直接用它）

wire pre_if_ready_go = 1'b1;   // preIF / if_req 两级都一拍完成
wire if_req_ready_go = 1'b1;

// if_req keeps a one-cycle-delayed copy of the fetch PC.  The synchronous
// inst RAM returns the instruction one cycle after the request, so IF samples
// (if_req_pc, inst_sram_rdata) in the cycle the data comes back.
wire if_req_allowin = !if_req_valid || (if_req_ready_go && if_allowin);   // 【握手】下游 IF 肯收、或本级为空，才允许更新 —— 数据冒险的停顿就靠这条链传上来
wire pre_if_allowin = !pre_if_valid || (pre_if_ready_go && if_req_allowin);   // 【前端反压链最上游】id_allowin 一拉低这里就变 0，pre_if_pc 不再更新

always @(posedge clk) begin
    if (reset) begin
        pre_if_valid <= 1'b0;
    end
    else if (pre_if_allowin) begin
        pre_if_valid <= 1'b1;   // valid 置 1 后一直保持（取指不中断）
    end
end

always @(posedge clk) begin
    if (reset) begin
        pre_if_pc <= 32'h1bfffffc;  // reset entry is 0x1c000000; pre-load entry-4 so the
                                // first fetch request after reset targets the entry
    end
    else if (pre_if_allowin) begin
        if (br_taken) pre_if_pc <= br_target;   // 【cancel ④ 改道】分支 taken：下一拍改取 br_target（不撤销本拍已发出的请求）
        else          pre_if_pc <= pre_if_pc + 32'd4;   // 顺序取指：PC + 4
    end
end

// Fetch only while the front end advances, so that the RAM's registered output
// always corresponds to the PC captured by if_req.
assign inst_sram_en    = pre_if_valid && pre_if_allowin;   // 【冻结期不发请求】保证 RAM 的寄存输出与 if_req_pc 一一对应 → 停顿时取指不错位
assign inst_sram_we    = 4'b0000;
assign inst_sram_addr  = pre_if_pc;   // 取指请求地址 = pre_if_pc
assign inst_sram_wdata = 32'b0;

// ====================== fetch-return (if_req) stage =======================
reg         if_req_valid;
reg  [31:0] if_req_pc;

always @(posedge clk) begin
    if (reset) begin
        if_req_valid <= 1'b0;
    end
    else if (if_req_allowin) begin
        if_req_valid <= pre_if_valid && !br_taken;   // 【cancel ①】分支 taken 当拍：不再接收这一拍正发出去的错路径请求
    end
end

always @(posedge clk) begin
    if (reset) begin
        if_req_pc <= 32'h1bfffffc;
    end
    else if (if_req_allowin && pre_if_valid && !br_taken) begin   // 【cancel ②】同上：不把错路径 PC 写进 if_req_pc（否则下一拍 PC 与数据配错）
        if_req_pc <= pre_if_pc;   // → if_req_pc 在 cancel 那拍保持不动
    end
end

// =============================== IF stage ================================
reg         if_valid;
reg  [31:0] if_pc;
reg  [31:0] if_inst;

wire if_ready_go = 1'b1;
wire if_allowin  = !if_valid || (if_ready_go && id_allowin);   // 【握手】IF 的下游是 ID：ID 一停，IF 跟着停
// cancel the wrong-path instruction queued behind a taken branch
wire if_req_to_if_valid = if_req_valid && !br_taken;   // 【cancel ③】拦住"上一拍已受理、这拍数据刚从 RAM 回来"的那条错路径指令

always @(posedge clk) begin
    if (reset) begin
        if_valid <= 1'b0;
    end
    else if (if_allowin) begin
        if_valid <= if_req_to_if_valid;   // 错路径那拍 if_req_to_if_valid=0 → IF 进来一个空泡
    end
end

always @(posedge clk) begin
    if (reset) begin
        if_pc <= 32'h1bfffffc;
    end
    else if (if_allowin && if_req_to_if_valid) begin
        if_pc <= if_req_pc;   // PC 与指令数据同拍对齐
    end
end

always @(posedge clk) begin
    if (reset) begin
        if_inst <= 32'h0;
    end
    else if (if_allowin && if_req_to_if_valid) begin
        if_inst <= inst_sram_rdata;   // 同步 RAM：这一拍的数据对应 if_req_pc
    end
end

// =========================== ID decode (combinational) =======================
wire [ 5:0] op_31_26;
wire [ 3:0] op_25_22;
wire [ 1:0] op_21_20;
wire [ 4:0] op_19_15;
wire [ 4:0] rd;
wire [ 4:0] rj;
wire [ 4:0] rk;
wire [11:0] i12;
wire [19:0] i20;
wire [15:0] i16;
wire [25:0] i26;

wire [63:0] op_31_26_d;
wire [15:0] op_25_22_d;
wire [ 3:0] op_21_20_d;
wire [31:0] op_19_15_d;

wire        inst_add_w;
wire        inst_sub_w;
wire        inst_slt;
wire        inst_sltu;
wire        inst_nor;
wire        inst_and;
wire        inst_or;
wire        inst_xor;
wire        inst_slli_w;
wire        inst_srli_w;
wire        inst_srai_w;
wire        inst_addi_w;
wire        inst_ld_w;
wire        inst_st_w;
wire        inst_jirl;
wire        inst_b;
wire        inst_bl;
wire        inst_beq;
wire        inst_bne;
wire        inst_lu12i_w;

wire        need_ui5;
wire        need_si12;
wire        need_si16;
wire        need_si20;
wire        need_si26;
wire        src2_is_4;

wire [11:0] alu_op;
wire        src1_is_pc;
wire        src2_is_imm;
wire        res_from_mem;
wire        dst_is_r1;
wire        gr_we;
wire        mem_we;
wire        src_reg_is_rd;
wire [ 4:0] dest;
wire [31:0] imm;
wire [31:0] br_offs;
wire [31:0] jirl_offs;

assign op_31_26  = if_inst[31:26];   // 字段切分：op / rd / rj / rk / 各种立即数（立即数会占住 rj、rk 的位置）
assign op_25_22  = if_inst[25:22];
assign op_21_20  = if_inst[21:20];
assign op_19_15  = if_inst[19:15];

assign rd   = if_inst[ 4: 0];   // rd：多数指令是目标；beq / bne / st.w 里它是第二源
assign rj   = if_inst[ 9: 5];   // rj：第一源（基址 / 被比较的一方 / 加数）
assign rk   = if_inst[14:10];   // rk：第二源（仅 3R 型）；移位指令的移位量也放这里，但那是位段不是寄存器

assign i12  = if_inst[21:10];   // i12 覆盖 rk 的位置
assign i20  = if_inst[24: 5];   // i20 覆盖 rj 和 rk 的位置（lu12i.w）
assign i16  = if_inst[25:10];
assign i26  = {if_inst[ 9: 0], if_inst[25:10]};   // i26 覆盖 rj 和 rk 的位置（b / bl）

decoder_6_64 u_dec0(.in(op_31_26 ), .out(op_31_26_d ));
decoder_4_16 u_dec1(.in(op_25_22 ), .out(op_25_22_d ));
decoder_2_4  u_dec2(.in(op_21_20 ), .out(op_21_20_d ));
decoder_5_32 u_dec3(.in(op_19_15 ), .out(op_19_15_d ));

assign inst_add_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h00];
assign inst_sub_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h02];
assign inst_slt    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h04];
assign inst_sltu   = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h05];
assign inst_nor    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h08];
assign inst_and    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h09];
assign inst_or     = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0a];
assign inst_xor    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0b];
assign inst_slli_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h01];
assign inst_srli_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h09];
assign inst_srai_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h11];
assign inst_addi_w = op_31_26_d[6'h00] & op_25_22_d[4'ha];
assign inst_ld_w   = op_31_26_d[6'h0a] & op_25_22_d[4'h2];
assign inst_st_w   = op_31_26_d[6'h0a] & op_25_22_d[4'h6];
assign inst_jirl   = op_31_26_d[6'h13];
assign inst_b      = op_31_26_d[6'h14];   // b：无条件跳转，不读寄存器、不写寄存器
assign inst_bl     = op_31_26_d[6'h15];   // bl：跳转 + 链接，返回地址写 r1
assign inst_beq    = op_31_26_d[6'h16];
assign inst_bne    = op_31_26_d[6'h17];
assign inst_lu12i_w= op_31_26_d[6'h05] & ~if_inst[25];   // lu12i.w：把 20 位立即数装进 rd 高位（低 12 位补 0）

assign alu_op[ 0] = inst_add_w | inst_addi_w | inst_ld_w | inst_st_w
                    | inst_jirl | inst_bl;
assign alu_op[ 1] = inst_sub_w;
assign alu_op[ 2] = inst_slt;
assign alu_op[ 3] = inst_sltu;
assign alu_op[ 4] = inst_and;
assign alu_op[ 5] = inst_nor;
assign alu_op[ 6] = inst_or;
assign alu_op[ 7] = inst_xor;
assign alu_op[ 8] = inst_slli_w;
assign alu_op[ 9] = inst_srli_w;
assign alu_op[10] = inst_srai_w;
assign alu_op[11] = inst_lu12i_w;

assign need_ui5   =  inst_slli_w | inst_srli_w | inst_srai_w;   // 移位的第二操作数是 5 位立即数（借 rk 字段承载），不算"读寄存器"
assign need_si12  =  inst_addi_w | inst_ld_w | inst_st_w;   // si12 立即数：addi.w / ld.w / st.w
assign need_si16  =  inst_jirl | inst_beq | inst_bne;
assign need_si20  =  inst_lu12i_w;
assign need_si26  =  inst_b | inst_bl;
assign src2_is_4  =  inst_jirl | inst_bl;   // jirl / bl 的第二操作数是常数 4

assign imm = src2_is_4 ? 32'h4                      :
             need_si20 ? {i20[19:0], 12'b0}         :
             need_ui5  ? {27'd0, rk}                :
                         {{20{i12[11]}}, i12[11:0]};   // need_si12: sign-extended i12

assign br_offs = need_si26 ? {{ 4{i26[25]}}, i26[25:0], 2'b0} :
                             {{14{i16[15]}}, i16[15:0], 2'b0} ;

assign jirl_offs = {{14{i16[15]}}, i16[15:0], 2'b0};

assign src_reg_is_rd = inst_beq | inst_bne | inst_st_w;   // 第二源落在 rd 还是 rk：只有 beq / bne / st.w 用 rd

assign src1_is_pc    = inst_jirl | inst_bl;

assign src2_is_imm   = inst_slli_w |
                       inst_srli_w |
                       inst_srai_w |
                       inst_addi_w |
                       inst_ld_w   |
                       inst_st_w   |
                       inst_lu12i_w|
                       inst_jirl   |
                       inst_bl     ;

assign res_from_mem  = inst_ld_w;
assign dst_is_r1     = inst_bl;
assign gr_we         = ~inst_st_w & ~inst_beq & ~inst_bne & ~inst_b;   // 写寄存器使能：st.w / beq / bne / b 不写
assign mem_we        = inst_st_w;
assign dest          = dst_is_r1 ? 5'd1 : rd;   // 写目标号：bl 固定写 r1

// regfile read ports
wire [ 4:0] rf_raddr1;
wire [31:0] rf_rdata1;
wire [ 4:0] rf_raddr2;
wire [31:0] rf_rdata2;
wire        rf_we   ;
wire [ 4:0] rf_waddr;
wire [31:0] rf_wdata;

assign rf_raddr1 = rj;   // 寄存器堆读口 1 地址 = rj（永远是第一源）
assign rf_raddr2 = src_reg_is_rd ? rd : rk;   // 读口 2 地址 = rd 或 rk

regfile u_regfile(
    .clk    (clk      ),
    .raddr1 (rf_raddr1),
    .rdata1 (rf_rdata1),
    .raddr2 (rf_raddr2),
    .rdata2 (rf_rdata2),
    .we     (rf_we    ),
    .waddr  (rf_waddr ),
    .wdata  (rf_wdata )
    );

// whether the source register is actually used
wire id_uses_rj  = ~(inst_b | inst_bl | inst_lu12i_w);   // 除 b / bl / lu12i.w 之外都读 rj（这三条的 rj 位其实是立即数的一部分）
wire id_uses_rkd = inst_add_w | inst_sub_w | inst_slt | inst_sltu   // 只有这些指令有第二源 → 冒险检测只在这两个标志为 1 时比对，否则会拿立即数位段当寄存器号
                 | inst_and | inst_or | inst_nor | inst_xor
                 | inst_beq | inst_bne | inst_st_w;

// ---- exp7 stage: no forwarding, operands come straight from the regfile ----
wire [31:0] ex_alu_result;   // EX stage ALU result (combinational)
wire [31:0] mem_value;       // MEM stage result
wire [31:0] wb_result;       // WB stage result

wire [31:0] id_rj_value  = rf_rdata1;   // 【本版无前递】第一源直接来自寄存器堆，可能还是旧值
wire [31:0] id_rkd_value = rf_rdata2;   // 【本版无前递】第二源（rkd = rk 或 rd）同样直接来自寄存器堆

// ---- branch resolved in ID ----
wire rj_eq_rd = (id_rj_value == id_rkd_value);   // 分支比较结果（beq 判相等、bne 判不等）
wire br_taken = (   (inst_beq && rj_eq_rd)   // 分支在 ID 拍就判定完（越早代价越小）
                 || (inst_bne && !rj_eq_rd)
                 || inst_jirl
                 || inst_bl
                 || inst_b
                ) && if_valid && ~id_stall;   // 【要点】源操作数没就绪就不许判分支，否则会拿旧值误判 taken / not-taken
wire [31:0] br_target;
assign br_target = (inst_beq || inst_bne || inst_bl || inst_b) ? (if_pc + br_offs) :   // 分支目标 = if_pc + 偏移
                                                    /*inst_jirl*/ (id_rj_value + jirl_offs);   // jirl：目标用寄存器值算（id_rj_value + 偏移）

// ---- data hazard: block ID until the producer has written the regfile ----
wire [4:0] id_src2_reg = src_reg_is_rd ? rd : rk;   // 【阻塞】本条指令第二源的寄存器号：3R 取 rk，beq / bne / st.w 取 rd

wire id_ex_hit  = ex_valid  && ex_gr_we  && (ex_dest  != 5'b0)   // 【阻塞 ① EX 撞车】生产者在 EX → 最坏，要等 3 拍（EX / MEM / WB 各一拍）
               && ( (id_uses_rj && (ex_dest  == rj)) || (id_uses_rkd && (ex_dest  == id_src2_reg)) );   // 三要素：那级有指令且要写寄存器 + 目标非 r0 + 目标号 == 本条要读的源号
wire id_mem_hit = mem_valid && mem_gr_we && (mem_dest != 5'b0)   // 【阻塞 ② MEM 撞车】生产者在 MEM → 等 2 拍
               && ( (id_uses_rj && (mem_dest == rj)) || (id_uses_rkd && (mem_dest == id_src2_reg)) );
wire id_wb_hit  = wb_valid  && wb_gr_we  && (wb_dest  != 5'b0)   // 【阻塞 ③ WB 撞车】生产者在 WB → 等 1 拍（寄存器堆要 WB 拍末才写）
               && ( (id_uses_rj && (wb_dest  == rj)) || (id_uses_rkd && (wb_dest  == id_src2_reg)) );

wire id_stall = if_valid && (id_ex_hit || id_mem_hit || id_wb_hit);   // 【阻塞总开关】三路命中任一即停；串 if_valid 是 IF 空时不瞎停
wire id_ready_go  = ~id_stall;   // 停下 → ready_go = 0
// ID is the combinational decode between IF regs and EX (classic 5-stage)
wire id_allowin   = !if_valid || (id_ready_go && ex_allowin);   // 【反压起点】id_allowin=0 → if_allowin → if_req_allowin → pre_if_allowin 全 0
wire id_to_ex_valid = if_valid && id_ready_go;   // 【停顿时】不给 EX 送新指令；已在 EX / MEM / WB 的指令照常前进

// =============================== EX stage ================================
reg         ex_valid;
reg  [31:0] ex_pc;
reg  [11:0] ex_alu_op;
reg  [31:0] ex_alu_src1;
reg  [31:0] ex_alu_src2;
reg  [31:0] ex_rkd_value;   // store data for st.w
reg         ex_gr_we;
reg         ex_mem_we;
reg         ex_res_from_mem;
reg  [ 4:0] ex_dest;

wire ex_ready_go  = 1'b1;   // EX 一拍完成
wire ex_allowin   = !ex_valid || (ex_ready_go && mem_allowin);   // 握手：下游 MEM 肯收才更新
wire ex_to_mem_valid = ex_valid && ex_ready_go;

always @(posedge clk) begin
    if (reset) begin
        ex_valid <= 1'b0;
    end
    else if (ex_allowin) begin
        ex_valid <= id_to_ex_valid;
    end
end

always @(posedge clk) begin
    if (reset) begin
        ex_pc <= 32'b0;
        ex_alu_op <= 12'b0;
        ex_alu_src1 <= 32'b0;
        ex_alu_src2 <= 32'b0;
        ex_rkd_value <= 32'b0;
        ex_gr_we <= 1'b0;
        ex_mem_we <= 1'b0;
        ex_res_from_mem <= 1'b0;
        ex_dest <= 5'b0;
    end
    else if (id_to_ex_valid && ex_allowin) begin
        ex_pc <= if_pc;
        ex_alu_op <= alu_op;
        ex_alu_src1 <= src1_is_pc ? if_pc : id_rj_value;   // src1 可以是 PC（bl / jirl）
        ex_alu_src2 <= src2_is_imm ? imm : id_rkd_value;   // src2 可以是立即数
        ex_rkd_value <= id_rkd_value;   // 要存的数据随流水线走（st.w 用）
        ex_gr_we <= gr_we;
        ex_mem_we <= mem_we;
        ex_res_from_mem <= res_from_mem;
        ex_dest <= dest;   // 目标寄存器号进 MEM / WB
    end
end

alu u_alu(
    .alu_op     (ex_alu_op    ),
    .alu_src1   (ex_alu_src1  ),
    .alu_src2   (ex_alu_src2  ),
    .alu_result (ex_alu_result)
    );

// EX issues the memory request; the sync data RAM returns rdata during the
// following MEM stage, so no extra register is needed before WB
assign data_sram_en    = ex_valid && (ex_mem_we || ex_res_from_mem);   // 访存请求在 EX 拍发出（同步 RAM 一拍后返回，正好落在 MEM 级）
assign data_sram_we    = ex_mem_we ? 4'b1111 : 4'b0000;   // st.w 写满 4 字节
assign data_sram_addr  = ex_alu_result;
assign data_sram_wdata = ex_rkd_value;

// =============================== MEM stage ===============================
reg         mem_valid;
reg  [31:0] mem_pc;
reg  [31:0] mem_alu_result;
reg         mem_gr_we;
reg         mem_res_from_mem;
reg  [ 4:0] mem_dest;

wire mem_ready_go = 1'b1;
wire mem_allowin  = !mem_valid || (mem_ready_go && wb_allowin);
wire mem_to_wb_valid = mem_valid && mem_ready_go;

always @(posedge clk) begin
    if (reset) begin
        mem_valid <= 1'b0;
    end
    else if (mem_allowin) begin
        mem_valid <= ex_to_mem_valid;
    end
end

always @(posedge clk) begin
    if (reset) begin
        mem_pc <= 32'b0;
        mem_alu_result <= 32'b0;
        mem_gr_we <= 1'b0;
        mem_res_from_mem <= 1'b0;
        mem_dest <= 5'b0;
    end
    else if (ex_to_mem_valid && mem_allowin) begin
        mem_pc <= ex_pc;
        mem_alu_result <= ex_alu_result;
        mem_gr_we <= ex_gr_we;
        mem_res_from_mem <= ex_res_from_mem;
        mem_dest <= ex_dest;
    end
end

// ld.w data is valid on the RAM output during the MEM stage (the request was
// issued one cycle earlier in EX)
assign mem_value = mem_res_from_mem ? data_sram_rdata : mem_alu_result;   // ld.w 的数据这一拍才有效（读请求是上一拍在 EX 发的）

// =============================== WB stage ================================
reg         wb_valid;
reg  [31:0] wb_pc;
reg         wb_gr_we;
reg  [ 4:0] wb_dest;
reg  [31:0] wb_value;

wire wb_ready_go = 1'b1;   // WB 一拍完成
wire wb_allowin  = !wb_valid || wb_ready_go;

always @(posedge clk) begin
    if (reset) begin
        wb_valid <= 1'b0;
    end
    else if (wb_allowin) begin
        wb_valid <= mem_to_wb_valid;
    end
end

always @(posedge clk) begin
    if (reset) begin
        wb_pc <= 32'b0;
        wb_gr_we <= 1'b0;
        wb_dest <= 5'b0;
        wb_value <= 32'b0;
    end
    else if (mem_to_wb_valid && wb_allowin) begin
        wb_pc <= mem_pc;
        wb_gr_we <= mem_gr_we;
        wb_dest <= mem_dest;
        wb_value <= mem_value;
    end
end

// regfile write port
assign rf_we    = wb_gr_we && wb_valid;   // 【阻塞的终点】WB 拍末写回寄存器堆，下一拍 ID 才读得到新值
assign rf_waddr = wb_dest;   // 写口地址
assign rf_wdata = wb_value;

// WB forwarding source: same value that is written to the regfile
assign wb_result = wb_value;   // exp9 前馈源的来源（本版没用到）

// debug info (WB stage)
assign debug_wb_pc       = wb_pc;   // 调试口：与 golden trace 比对用
assign debug_wb_rf_we    = {4{rf_we}};
assign debug_wb_rf_wnum  = wb_dest;
assign debug_wb_rf_wdata = wb_value;

endmodule
