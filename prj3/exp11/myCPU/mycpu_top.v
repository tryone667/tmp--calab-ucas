// ============================================================================
// 5-stage pipeline CPU (preIF -> IF -> ID -> EX -> MEM -> WB)
// Experiment 11: add branch (blt/bge/bltu/bgeu) and byte/half load-store
// instructions (ld.b/ld.h/ld.bu/ld.hu/st.b/st.h), built on exp10 core
// (pcaddu12i/slti/sltui/andi/ori/xori/sll/srl/sra/mul/mulh/div/mod).
//  - mul/mulh : single-cycle in ALU (see alu.v)
//  - div/mod  : multi-cycle divider unit in EX (module divider below);
//               pipeline stalls while it runs
//  - load-use / div-consumer hazards stall; EX/MEM/WB forwarding
//  - control hazard: resolve branch in ID (signed/unsigned compare)
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
        pre_if_pc <= 32'h1bfffffc;  //trick: next fetch address after reset is 0x1c000000
    end
    else if (pre_if_allowin) begin
        if (br_taken) pre_if_pc <= br_target;
        else          pre_if_pc <= pre_if_pc + 3'h4;
    end
end

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
        if_req_valid <= pre_if_valid && !br_taken;
    end
end

always @(posedge clk) begin
    if (reset) begin
        if_req_pc <= 32'h1bfffffc;
    end
    else if (if_req_allowin && pre_if_valid && !br_taken) begin
        if_req_pc <= pre_if_pc;
    end
end

// =============================== IF stage ================================
reg         if_valid;
reg  [31:0] if_pc;
reg  [31:0] if_inst;

wire if_ready_go = 1'b1;
wire if_allowin  = !if_valid || (if_ready_go && id_allowin);
wire if_req_to_if_valid = if_req_valid && !br_taken;

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
wire        inst_ld_b;
wire        inst_ld_h;
wire        inst_ld_w;
wire        inst_ld_bu;
wire        inst_ld_hu;
wire        inst_st_b;
wire        inst_st_h;
wire        inst_st_w;
wire        inst_jirl;
wire        inst_b;
wire        inst_bl;
wire        inst_beq;
wire        inst_bne;
wire        inst_blt;
wire        inst_bge;
wire        inst_bltu;
wire        inst_bgeu;
wire        inst_lu12i_w;
wire        inst_pcaddu12i;
wire        inst_slti;
wire        inst_sltui;
wire        inst_andi;
wire        inst_ori;
wire        inst_xori;
wire        inst_sll_w;
wire        inst_srl_w;
wire        inst_sra_w;
wire        inst_mul_w;
wire        inst_mulh_w;
wire        inst_mulh_wu;
wire        inst_div_w;
wire        inst_div_wu;
wire        inst_mod_w;
wire        inst_mod_wu;

wire        need_ui5;
wire        need_si12;
wire        need_ui12;
wire        need_si16;
wire        need_si20;
wire        need_si26;
wire        src2_is_4;

wire [17:0] alu_op;   // one-hot add..mulh; div/mod run in the divider unit
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

// load/store type code carried through the pipeline:
// 0 none  1 st.b  2 st.h  3 st.w  4 ld.b  5 ld.h  6 ld.w  7 ld.bu  8 ld.hu
wire [3:0] id_ls_type;

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

// 3R ALU (op_31_26=0x00, op_25_22=0x00, op_21_20=01/10)
assign inst_add_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h00];
assign inst_sub_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h02];
assign inst_slt    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h04];
assign inst_sltu   = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h05];
assign inst_nor    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h08];
assign inst_and    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h09];
assign inst_or     = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0a];
assign inst_xor    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0b];
assign inst_sll_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0e];
assign inst_srl_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0f];
assign inst_sra_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h10];
assign inst_mul_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h18];
assign inst_mulh_w = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h19];
assign inst_mulh_wu= op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h1a];
assign inst_div_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h00];
assign inst_mod_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h01];
assign inst_div_wu = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h02];
assign inst_mod_wu = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h03];
assign inst_slli_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h01];
assign inst_srli_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h09];
assign inst_srai_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h11];
// 2RI12 ALU: op_31_26 = 0x00, subop in op_25_22
assign inst_addi_w = op_31_26_d[6'h00] & op_25_22_d[4'ha];
assign inst_slti   = op_31_26_d[6'h00] & op_25_22_d[4'h8];
assign inst_sltui  = op_31_26_d[6'h00] & op_25_22_d[4'h9];
assign inst_andi   = op_31_26_d[6'h00] & op_25_22_d[4'hd];
assign inst_ori    = op_31_26_d[6'h00] & op_25_22_d[4'he];
assign inst_xori   = op_31_26_d[6'h00] & op_25_22_d[4'hf];
// load/store: op_31_26 = 0x0a, size in op_25_22
assign inst_ld_b   = op_31_26_d[6'h0a] & op_25_22_d[4'h0];
assign inst_ld_h   = op_31_26_d[6'h0a] & op_25_22_d[4'h1];
assign inst_ld_w   = op_31_26_d[6'h0a] & op_25_22_d[4'h2];
assign inst_ld_bu  = op_31_26_d[6'h0a] & op_25_22_d[4'h8];
assign inst_ld_hu  = op_31_26_d[6'h0a] & op_25_22_d[4'h9];
assign inst_st_b   = op_31_26_d[6'h0a] & op_25_22_d[4'h4];
assign inst_st_h   = op_31_26_d[6'h0a] & op_25_22_d[4'h5];
assign inst_st_w   = op_31_26_d[6'h0a] & op_25_22_d[4'h6];
// branches & jumps
assign inst_jirl   = op_31_26_d[6'h13];
assign inst_b      = op_31_26_d[6'h14];
assign inst_bl     = op_31_26_d[6'h15];
assign inst_beq    = op_31_26_d[6'h16];
assign inst_bne    = op_31_26_d[6'h17];
assign inst_blt    = op_31_26_d[6'h18];
assign inst_bge    = op_31_26_d[6'h19];
assign inst_bltu   = op_31_26_d[6'h1a];
assign inst_bgeu   = op_31_26_d[6'h1b];
// 2RI20
assign inst_lu12i_w = op_31_26_d[6'h05] & ~if_inst[25];
assign inst_pcaddu12i = op_31_26_d[6'h07] & ~if_inst[25];

assign alu_op[ 0] = inst_add_w | inst_addi_w | inst_ld_b | inst_ld_h | inst_ld_w
                    | inst_ld_bu | inst_ld_hu | inst_st_b | inst_st_h | inst_st_w
                    | inst_jirl | inst_bl | inst_pcaddu12i;
assign alu_op[ 1] = inst_sub_w;
assign alu_op[ 2] = inst_slt | inst_slti;
assign alu_op[ 3] = inst_sltu | inst_sltui;
assign alu_op[ 4] = inst_and | inst_andi;
assign alu_op[ 5] = inst_nor;
assign alu_op[ 6] = inst_or | inst_ori;
assign alu_op[ 7] = inst_xor | inst_xori;
assign alu_op[ 8] = inst_slli_w;
assign alu_op[ 9] = inst_srli_w;
assign alu_op[10] = inst_srai_w;
assign alu_op[11] = inst_lu12i_w;
assign alu_op[12] = inst_sll_w;
assign alu_op[13] = inst_srl_w;
assign alu_op[14] = inst_sra_w;
assign alu_op[15] = inst_mul_w;
assign alu_op[16] = inst_mulh_w;
assign alu_op[17] = inst_mulh_wu;

// div/mod results come from the divider unit in EX (not from alu_op):
// one shared predicate per fact, carried into EX by pipeline registers.
wire id_alu_is_div = inst_div_w | inst_div_wu | inst_mod_w | inst_mod_wu;

assign id_ls_type = inst_st_b  ? 4'd1 :
                    inst_st_h  ? 4'd2 :
                    inst_st_w  ? 4'd3 :
                    inst_ld_b  ? 4'd4 :
                    inst_ld_h  ? 4'd5 :
                    inst_ld_w  ? 4'd6 :
                    inst_ld_bu ? 4'd7 :
                    inst_ld_hu ? 4'd8 : 4'd0;

assign need_ui5   =  inst_slli_w | inst_srli_w | inst_srai_w;
assign need_si12  =  inst_addi_w
                   | inst_slti | inst_sltui
                   | inst_ld_b | inst_ld_h | inst_ld_w
                   | inst_ld_bu | inst_ld_hu
                   | inst_st_b | inst_st_h | inst_st_w;
assign need_ui12  =  inst_andi | inst_ori | inst_xori;
assign need_si16  =  inst_jirl | inst_beq | inst_bne
                   | inst_blt | inst_bge | inst_bltu | inst_bgeu;
assign need_si20  =  inst_lu12i_w | inst_pcaddu12i;
assign need_si26  =  inst_b | inst_bl;
assign src2_is_4  =  inst_jirl | inst_bl;

assign imm = src2_is_4      ? 32'h4                        :
             inst_lu12i_w   ? {i20[19:0], 12'b0}           :
             inst_pcaddu12i ? {{12{i20[19]}}, i20[19:0], 12'b0} :
             need_ui5       ? {27'd0, rk}                  :
             need_ui12      ? {20'd0, i12}                 :
/*need_si12*/                {{20{i12[11]}}, i12[11:0]}    ;

assign br_offs = need_si26 ? {{ 4{i26[25]}}, i26[25:0], 2'b0} :
                             {{14{i16[15]}}, i16[15:0], 2'b0} ;

assign jirl_offs = {{14{i16[15]}}, i16[15:0], 2'b0};

assign src_reg_is_rd = inst_beq | inst_bne | inst_blt | inst_bge
                     | inst_bltu | inst_bgeu
                     | inst_st_b | inst_st_h | inst_st_w;

assign src1_is_pc    = inst_jirl | inst_bl | inst_pcaddu12i;

assign src2_is_imm   = inst_slli_w |
                       inst_srli_w |
                       inst_srai_w |
                       inst_addi_w |
                       inst_slti   |
                       inst_sltui  |
                       inst_andi   |
                       inst_ori    |
                       inst_xori   |
                       inst_ld_b   |
                       inst_ld_h   |
                       inst_ld_w   |
                       inst_ld_bu  |
                       inst_ld_hu  |
                       inst_st_b   |
                       inst_st_h   |
                       inst_st_w   |
                       inst_lu12i_w|
                       inst_pcaddu12i|
                       inst_jirl   |
                       inst_bl     ;

assign res_from_mem  = inst_ld_b | inst_ld_h | inst_ld_w
                     | inst_ld_bu | inst_ld_hu;
assign dst_is_r1     = inst_bl;
assign gr_we         = ~(inst_st_b | inst_st_h | inst_st_w
                       | inst_beq | inst_bne
                       | inst_blt | inst_bge | inst_bltu | inst_bgeu
                       | inst_b);
assign mem_we        = inst_st_b | inst_st_h | inst_st_w;
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
wire id_uses_rj  = ~(inst_b | inst_bl | inst_lu12i_w | inst_pcaddu12i);
wire id_uses_rkd = inst_add_w | inst_sub_w | inst_slt | inst_sltu
                 | inst_and | inst_or | inst_nor | inst_xor
                 | inst_beq | inst_bne
                 | inst_blt | inst_bge | inst_bltu | inst_bgeu
                 | inst_st_b | inst_st_h | inst_st_w
                 | inst_sll_w | inst_srl_w | inst_sra_w
                 | inst_mul_w | inst_mulh_w | inst_mulh_wu
                 | inst_div_w | inst_div_wu | inst_mod_w | inst_mod_wu;

// ---- data forwarding: EX/MEM/WB results to ID ----
wire [31:0] ex_alu_result;   // EX stage result (combinational)
wire [31:0] mem_value;       // MEM stage result
wire [31:0] wb_result;       // WB stage result

wire fwd_ex_to_rj  = ex_valid && ex_gr_we && ~ex_res_from_mem
                   && (ex_dest != 5'b0) && (ex_dest == rj);
wire fwd_ex_to_rkd = ex_valid && ex_gr_we && ~ex_res_from_mem
                   && (ex_dest != 5'b0) && (ex_dest == (src_reg_is_rd ? rd : rk));
wire fwd_mem_to_rj  = mem_valid && mem_gr_we && (mem_dest != 5'b0) && (mem_dest == rj);
wire fwd_mem_to_rkd = mem_valid && mem_gr_we && (mem_dest != 5'b0)
                    && (mem_dest == (src_reg_is_rd ? rd : rk));
wire fwd_wb_to_rj  = wb_valid && wb_gr_we && (wb_dest != 5'b0) && (wb_dest == rj);
wire fwd_wb_to_rkd = wb_valid && wb_gr_we && (wb_dest != 5'b0)
                   && (wb_dest == (src_reg_is_rd ? rd : rk));

wire [31:0] id_rj_value  = fwd_ex_to_rj  ? ex_alu_result :
                           fwd_mem_to_rj ? mem_value     :
                           fwd_wb_to_rj  ? wb_result     :
                                           rf_rdata1     ;
wire [31:0] id_rkd_value = fwd_ex_to_rkd  ? ex_alu_result :
                           fwd_mem_to_rkd ? mem_value     :
                           fwd_wb_to_rkd  ? wb_result     :
                                            rf_rdata2    ;

// ---- branch resolved in ID ----
wire rj_eq_rd    = (id_rj_value == id_rkd_value);
wire rj_lt_rd_s  = $signed(id_rj_value) < $signed(id_rkd_value);
wire rj_lt_rd_u  = (id_rj_value < id_rkd_value);
wire br_taken = (   (inst_beq  && rj_eq_rd)
                 || (inst_bne  && !rj_eq_rd)
                 || (inst_blt  && rj_lt_rd_s)
                 || (inst_bge  && !rj_lt_rd_s)
                 || (inst_bltu && rj_lt_rd_u)
                 || (inst_bgeu && !rj_lt_rd_u)
                 || inst_jirl
                 || inst_bl
                 || inst_b
                ) && if_valid && ~id_stall;
wire [31:0] br_target;
assign br_target = (inst_beq || inst_bne || inst_blt || inst_bge
                 || inst_bltu || inst_bgeu || inst_bl || inst_b) ? (if_pc + br_offs) :
                                                    /*inst_jirl*/ (id_rj_value + jirl_offs);

// ---- data hazard: stall while EX holds a result ID needs ----
//  1) EX load (data not back yet)
//  2) EX div/mod (multi-cycle, result valid only after it leaves EX)
//     ex_alu_is_div is the pipelined copy of the ID-time div predicate
//     id_alu_is_div (declared with the EX registers below).
wire id_stall = if_valid && ex_valid && ex_gr_we && (ex_dest != 5'b0)
             && (ex_res_from_mem || ex_alu_is_div)
             && ( (id_uses_rj  && (ex_dest == rj))
               || (id_uses_rkd && (ex_dest == (src_reg_is_rd ? rd : rk))) );

wire id_ready_go  = ~id_stall;
wire id_allowin   = !if_valid || (id_ready_go && ex_allowin);
wire id_to_ex_valid = if_valid && id_ready_go;

// =============================== EX stage ================================
reg         ex_valid;
reg  [31:0] ex_pc;
reg  [17:0] ex_alu_op;
reg  [31:0] ex_alu_src1;
reg  [31:0] ex_alu_src2;
reg  [31:0] ex_rkd_value;   // store data
reg         ex_gr_we;
reg  [3:0]  ex_ls_type;     // load/store type
reg         ex_res_from_mem;
reg  [ 4:0] ex_dest;
reg         ex_alu_is_div;  // instruction in EX is div/mod

// ---- multi-cycle divider unit (div/mod instructions) ----
wire        ex_div_start  = id_to_ex_valid && ex_allowin && id_alu_is_div;
wire        ex_div_busy;
wire [31:0] ex_div_result;

divider u_divider(
    .clk    (clk                       ),
    .reset  (reset                     ),
    .start  (ex_div_start              ),
    .unsign (inst_div_wu | inst_mod_wu ),
    .mod    (inst_mod_w  | inst_mod_wu ),
    .a      (id_rj_value               ),
    .b      (id_rkd_value              ),
    .busy   (ex_div_busy               ),
    .result (ex_div_result             )
    );

wire ex_ready_go  = ~ex_div_busy;
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
        ex_alu_op <= 18'b0;
        ex_alu_src1 <= 32'b0;
        ex_alu_src2 <= 32'b0;
        ex_rkd_value <= 32'b0;
        ex_gr_we <= 1'b0;
        ex_ls_type <= 4'd0;
        ex_res_from_mem <= 1'b0;
        ex_dest <= 5'b0;
        ex_alu_is_div <= 1'b0;
    end
    else if (id_to_ex_valid && ex_allowin) begin
        ex_pc <= if_pc;
        ex_alu_op <= alu_op;
        ex_alu_src1 <= src1_is_pc ? if_pc : id_rj_value;
        ex_alu_src2 <= src2_is_imm ? imm : id_rkd_value;
        ex_rkd_value <= id_rkd_value;
        ex_gr_we <= gr_we;
        ex_ls_type <= id_ls_type;
        ex_res_from_mem <= res_from_mem;
        ex_dest <= dest;
        ex_alu_is_div <= id_alu_is_div;
    end
end

wire [31:0] ex_alu_result_raw;
alu u_alu(
    .alu_op     (ex_alu_op    ),
    .alu_src1   (ex_alu_src1  ),
    .alu_src2   (ex_alu_src2  ),
    .alu_result (ex_alu_result_raw)
    );

// div/mod result comes from the divider unit (multi-cycle, EX)
assign ex_alu_result = ex_alu_is_div ? ex_div_result : ex_alu_result_raw;

// memory request: issued during the EX stage, data returns in MEM stage
assign data_sram_en    = ex_valid && (ex_ls_type != 4'd0);
assign data_sram_we    = (ex_ls_type == 4'd1) ? (4'b0001 << ex_alu_result[1:0]) :
                         (ex_ls_type == 4'd2) ? (4'b0011 << {ex_alu_result[1], 1'b0}) :
                         (ex_ls_type == 4'd3) ? 4'b1111 : 4'b0000;
assign data_sram_addr  = ex_alu_result;
assign data_sram_wdata = (ex_ls_type == 4'd1) ? {4{ex_rkd_value[7:0]}} :
                         (ex_ls_type == 4'd2) ? {2{ex_rkd_value[15:0]}} :
                                                ex_rkd_value;

// =============================== MEM stage ===============================
reg         mem_valid;
reg  [31:0] mem_pc;
reg  [31:0] mem_alu_result;
reg         mem_gr_we;
reg  [3:0]  mem_ls_type;
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
        mem_ls_type <= 4'd0;
        mem_res_from_mem <= 1'b0;
        mem_dest <= 5'b0;
    end
    else if (ex_to_mem_valid && mem_allowin) begin
        mem_pc <= ex_pc;
        mem_alu_result <= ex_alu_result;
        mem_gr_we <= ex_gr_we;
        mem_ls_type <= ex_ls_type;
        mem_res_from_mem <= ex_res_from_mem;
        mem_dest <= ex_dest;
    end
end

// load data selection (request was issued one cycle earlier in EX)
wire [31:0] mem_byte_shifted = data_sram_rdata >> {mem_alu_result[1:0], 3'b0};
wire [31:0] mem_half_val = mem_alu_result[1] ? data_sram_rdata[31:16]
                                             : data_sram_rdata[15:0];
wire [31:0] mem_load_val =
    (mem_ls_type == 4'd6) ? data_sram_rdata :
    (mem_ls_type == 4'd5) ? {{16{mem_half_val[15]}}, mem_half_val[15:0]} :
    (mem_ls_type == 4'd8) ? {16'd0, mem_half_val[15:0]} :
    (mem_ls_type == 4'd4) ? {{24{mem_byte_shifted[7]}}, mem_byte_shifted[7:0]} :
    (mem_ls_type == 4'd7) ? {24'd0, mem_byte_shifted[7:0]} :
                             32'b0;

assign mem_value = mem_res_from_mem ? mem_load_val : mem_alu_result;

// =============================== WB stage ================================
reg         wb_valid;
reg  [31:0] wb_pc;
reg         wb_gr_we;
reg  [ 4:0] wb_dest;
reg  [31:0] wb_value;

wire wb_ready_go = 1'b1;
wire wb_allowin  = !wb_valid || (wb_ready_go && 1'b1);

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

assign wb_result = wb_value;

// debug info (WB stage)
assign debug_wb_pc       = wb_pc;
assign debug_wb_rf_we    = {4{rf_we}};
assign debug_wb_rf_wnum  = wb_dest;
assign debug_wb_rf_wdata = wb_value;

endmodule

// ============================================================================
// divider : multi-cycle restoring divider for LA32R div.w / mod.w /
//           div.wu / mod.wu.  start is a one-cycle pulse; the unit then runs
//           32 steps with busy high; result is mod ? remainder : quotient,
//           quotient truncated toward zero and remainder taking the
//           dividend sign for the signed variants.
// ============================================================================
module divider(
    input  wire        clk,
    input  wire        reset,
    input  wire        start,
    input  wire        unsign,
    input  wire        mod,
    input  wire [31:0] a,
    input  wire [31:0] b,
    output wire        busy,
    output wire [31:0] result
);

reg         busy_r;
reg         unsign_r;
reg         mod_r;
reg         q_neg;
reg         r_neg;
reg  [63:0] acc;
reg  [31:0] babs;
reg  [ 4:0] step;
reg  [31:0] quot;
reg  [31:0] rem;

assign busy   = busy_r;
assign result = mod_r ? rem : quot;

wire [31:0] rem_n = {acc[62:32], acc[31]};
wire [31:0] q_n   = {acc[30: 0], 1'b0};
wire        ge    = (babs != 32'd0) && (rem_n >= babs);
wire [63:0] acc_n = ge ? {rem_n - babs, q_n | 32'd1} : {rem_n, q_n};

always @(posedge clk) begin
    if (reset) begin
        busy_r   <= 1'b0;
        unsign_r <= 1'b0;
        mod_r    <= 1'b0;
        q_neg    <= 1'b0;
        r_neg    <= 1'b0;
        acc      <= 64'b0;
        babs     <= 32'b0;
        step     <= 5'd0;
        quot     <= 32'b0;
        rem      <= 32'b0;
    end
    else if (start) begin
        busy_r   <= 1'b1;
        unsign_r <= unsign;
        mod_r    <= mod;
        q_neg    <= ~unsign && (a[31] ^ b[31]);
        r_neg    <= ~unsign &&  a[31];
        step     <= 5'd0;
        if (unsign) begin
            acc  <= {32'd0, a};
            babs <= b;
        end
        else begin
            acc  <= {32'd0, a[31] ? (~a + 32'd1) : a};
            babs <= b[31] ? (~b + 32'd1) : b;
        end
    end
    else if (busy_r) begin
        if (step == 5'd31) begin
            busy_r <= 1'b0;
            if (unsign_r) begin
                quot <= acc_n[31: 0];
                rem  <= acc_n[63:32];
            end
            else begin
                quot <= q_neg ? (~acc_n[31: 0] + 32'd1) : acc_n[31: 0];
                rem  <= r_neg ? (~acc_n[63:32] + 32'd1) : acc_n[63:32];
            end
        end
        else begin
            step <= step + 1'b1;
            acc  <= acc_n;
        end
    end
end

endmodule
