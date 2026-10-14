// ============================================================================
// 5-stage pipelined LoongArch LA32R CPU (preIF -> IF -> ID -> EX -> MEM -> WB)
// Experiment: exp7 pipeline CPU (v7 stage: no hazard handling, NOP image)
//  - data hazard : none - the NOP-inserted test image separates dependent insts
//  - control hazard : branch resolved in ID, PC redirect only (no cancel)
//  - inst/data RAM : synchronous read model (rdata returns one cycle after the
//                    request), matching the soc_bram sync_ram / BRAM flow
// ============================================================================
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
always @(posedge clk) reset <= ~resetn;

// ============================ preIF fetch request ============================
reg         pre_if_valid;
reg  [31:0] pre_if_pc;

wire pre_if_ready_go = 1'b1;
wire if_req_ready_go = 1'b1;

// if_req keeps a one-cycle-delayed copy of the fetch PC.  The synchronous
// inst RAM returns the instruction one cycle after the request, so IF samples
// (if_req_pc, inst_sram_rdata) in the cycle the data comes back.
wire if_req_allowin = !if_req_valid || (if_req_ready_go && if_allowin);
wire pre_if_allowin = !pre_if_valid || (pre_if_ready_go && if_req_allowin);

always @(posedge clk) begin
    if (reset) begin
        pre_if_valid <= 1'b0;
    end
    else if (pre_if_allowin) begin
        pre_if_valid <= 1'b1;
    end
end

always @(posedge clk) begin
    if (reset) begin
        pre_if_pc <= 32'h1bfffffc;  // reset entry is 0x1c000000; pre-load entry-4 so the
                                // first fetch request after reset targets the entry
    end
    else if (pre_if_allowin) begin
        if (br_taken) pre_if_pc <= br_target;
        else          pre_if_pc <= pre_if_pc + 32'd4;
    end
end

// Fetch only while the front end advances, so that the RAM's registered output
// always corresponds to the PC captured by if_req.
assign inst_sram_en    = pre_if_valid && pre_if_allowin;
assign inst_sram_we    = 4'b0000;
assign inst_sram_addr  = pre_if_pc;
assign inst_sram_wdata = 32'b0;

// ====================== fetch-return (if_req) stage =======================
reg         if_req_valid;
reg  [31:0] if_req_pc;

always @(posedge clk) begin
    if (reset) begin
        if_req_valid <= 1'b0;
    end
    else if (if_req_allowin) begin
        if_req_valid <= pre_if_valid;
    end
end

always @(posedge clk) begin
    if (reset) begin
        if_req_pc <= 32'h1bfffffc;
    end
    else if (if_req_allowin && pre_if_valid) begin
        if_req_pc <= pre_if_pc;
    end
end

// =============================== IF stage ================================
reg         if_valid;
reg  [31:0] if_pc;
reg  [31:0] if_inst;

wire if_ready_go = 1'b1;
wire if_allowin  = !if_valid || (if_ready_go && id_allowin);
// exp7 stage: no cancel; the wrong-path instruction is a NOP in the image
wire if_req_to_if_valid = if_req_valid;

always @(posedge clk) begin
    if (reset) begin
        if_valid <= 1'b0;
    end
    else if (if_allowin) begin
        if_valid <= if_req_to_if_valid;
    end
end

always @(posedge clk) begin
    if (reset) begin
        if_pc <= 32'h1bfffffc;
    end
    else if (if_allowin && if_req_to_if_valid) begin
        if_pc <= if_req_pc;
    end
end

always @(posedge clk) begin
    if (reset) begin
        if_inst <= 32'h0;
    end
    else if (if_allowin && if_req_to_if_valid) begin
        if_inst <= inst_sram_rdata;
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

assign op_31_26  = if_inst[31:26];
assign op_25_22  = if_inst[25:22];
assign op_21_20  = if_inst[21:20];
assign op_19_15  = if_inst[19:15];

assign rd   = if_inst[ 4: 0];
assign rj   = if_inst[ 9: 5];
assign rk   = if_inst[14:10];

assign i12  = if_inst[21:10];
assign i20  = if_inst[24: 5];
assign i16  = if_inst[25:10];
assign i26  = {if_inst[ 9: 0], if_inst[25:10]};

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
assign inst_b      = op_31_26_d[6'h14];
assign inst_bl     = op_31_26_d[6'h15];
assign inst_beq    = op_31_26_d[6'h16];
assign inst_bne    = op_31_26_d[6'h17];
assign inst_lu12i_w= op_31_26_d[6'h05] & ~if_inst[25];

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

assign need_ui5   =  inst_slli_w | inst_srli_w | inst_srai_w;
assign need_si12  =  inst_addi_w | inst_ld_w | inst_st_w;
assign need_si16  =  inst_jirl | inst_beq | inst_bne;
assign need_si20  =  inst_lu12i_w;
assign need_si26  =  inst_b | inst_bl;
assign src2_is_4  =  inst_jirl | inst_bl;

assign imm = src2_is_4 ? 32'h4                      :
             need_si20 ? {i20[19:0], 12'b0}         :
             need_ui5  ? {27'd0, rk}                :
                         {{20{i12[11]}}, i12[11:0]};   // need_si12: sign-extended i12

assign br_offs = need_si26 ? {{ 4{i26[25]}}, i26[25:0], 2'b0} :
                             {{14{i16[15]}}, i16[15:0], 2'b0} ;

assign jirl_offs = {{14{i16[15]}}, i16[15:0], 2'b0};

assign src_reg_is_rd = inst_beq | inst_bne | inst_st_w;

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
assign gr_we         = ~inst_st_w & ~inst_beq & ~inst_bne & ~inst_b;
assign mem_we        = inst_st_w;
assign dest          = dst_is_r1 ? 5'd1 : rd;

// regfile read ports
wire [ 4:0] rf_raddr1;
wire [31:0] rf_rdata1;
wire [ 4:0] rf_raddr2;
wire [31:0] rf_rdata2;
wire        rf_we   ;
wire [ 4:0] rf_waddr;
wire [31:0] rf_wdata;

assign rf_raddr1 = rj;
assign rf_raddr2 = src_reg_is_rd ? rd : rk;

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
wire id_uses_rj  = ~(inst_b | inst_bl | inst_lu12i_w);
wire id_uses_rkd = inst_add_w | inst_sub_w | inst_slt | inst_sltu
                 | inst_and | inst_or | inst_nor | inst_xor
                 | inst_beq | inst_bne | inst_st_w;

// ---- exp7 stage: no forwarding, operands come straight from the regfile ----
wire [31:0] ex_alu_result;   // EX stage ALU result (combinational)
wire [31:0] mem_value;       // MEM stage result
wire [31:0] wb_result;       // WB stage result

wire [31:0] id_rj_value  = rf_rdata1;
wire [31:0] id_rkd_value = rf_rdata2;

// ---- branch resolved in ID ----
wire rj_eq_rd = (id_rj_value == id_rkd_value);
wire br_taken = (   (inst_beq && rj_eq_rd)
                 || (inst_bne && !rj_eq_rd)
                 || inst_jirl
                 || inst_bl
                 || inst_b
                ) && if_valid && ~id_stall;
wire [31:0] br_target;
assign br_target = (inst_beq || inst_bne || inst_bl || inst_b) ? (if_pc + br_offs) :
                                                    /*inst_jirl*/ (id_rj_value + jirl_offs);

// ---- exp7 stage: no blocking; the NOP-inserted image covers RAW ----
wire id_stall = 1'b0;
wire id_ready_go  = ~id_stall;
// ID is the combinational decode between IF regs and EX (classic 5-stage)
wire id_allowin   = !if_valid || (id_ready_go && ex_allowin);
wire id_to_ex_valid = if_valid && id_ready_go;

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

wire ex_ready_go  = 1'b1;
wire ex_allowin   = !ex_valid || (ex_ready_go && mem_allowin);
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
        ex_alu_src1 <= src1_is_pc ? if_pc : id_rj_value;
        ex_alu_src2 <= src2_is_imm ? imm : id_rkd_value;
        ex_rkd_value <= id_rkd_value;
        ex_gr_we <= gr_we;
        ex_mem_we <= mem_we;
        ex_res_from_mem <= res_from_mem;
        ex_dest <= dest;
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
assign data_sram_en    = ex_valid && (ex_mem_we || ex_res_from_mem);
assign data_sram_we    = ex_mem_we ? 4'b1111 : 4'b0000;
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
assign mem_value = mem_res_from_mem ? data_sram_rdata : mem_alu_result;

// =============================== WB stage ================================
reg         wb_valid;
reg  [31:0] wb_pc;
reg         wb_gr_we;
reg  [ 4:0] wb_dest;
reg  [31:0] wb_value;

wire wb_ready_go = 1'b1;
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
assign rf_we    = wb_gr_we && wb_valid;
assign rf_waddr = wb_dest;
assign rf_wdata = wb_value;

// WB forwarding source: same value that is written to the regfile
assign wb_result = wb_value;

// debug info (WB stage)
assign debug_wb_pc       = wb_pc;
assign debug_wb_rf_we    = {4{rf_we}};
assign debug_wb_rf_wnum  = wb_dest;
assign debug_wb_rf_wdata = wb_value;

endmodule
