`timescale 10ns / 1ns

module custom_cpu(
	input         clk,
	input         rst,

	output [31:0] PC,
	output        Inst_Req_Valid,
	input         Inst_Req_Ready,

	input  [31:0] Instruction,
	input         Inst_Valid,
	output        Inst_Ready,

	output [31:0] Address,
	output        MemWrite,
	output [31:0] Write_data,
	output [ 3:0] Write_strb,
	output        MemRead,
	input         Mem_Req_Ready,

	input  [31:0] Read_data,
	input         Read_data_Valid,
	output        Read_data_Ready,

	input         intr,

	output [31:0] cpu_perf_cnt_0,
	output [31:0] cpu_perf_cnt_1,
	output [31:0] cpu_perf_cnt_2,
	output [31:0] cpu_perf_cnt_3,
	output [31:0] cpu_perf_cnt_4,
	output [31:0] cpu_perf_cnt_5,
	output [31:0] cpu_perf_cnt_6,
	output [31:0] cpu_perf_cnt_7,
	output [31:0] cpu_perf_cnt_8,
	output [31:0] cpu_perf_cnt_9,
	output [31:0] cpu_perf_cnt_10,
	output [31:0] cpu_perf_cnt_11,
	output [31:0] cpu_perf_cnt_12,
	output [31:0] cpu_perf_cnt_13,
	output [31:0] cpu_perf_cnt_14,
	output [31:0] cpu_perf_cnt_15,

	output [69:0] inst_retire
);

	localparam BTB_ENTRIES = 16;

	reg [31:0] fetch_pc;
	reg        fetch_req_valid;
	reg        fetch_busy;
	reg        fetch_drop;
	reg [31:0] fetch_req_pc;
	reg [31:0] fetch_req_pred_pc;
	reg        fetch_req_pred_taken;

	reg        if_buf_valid;
	reg [31:0] if_buf_inst;
	reg [31:0] if_buf_pc;
	reg [31:0] if_buf_pred_pc;
	reg        if_buf_pred_taken;

	reg        id_valid;
	reg [31:0] id_inst;
	reg [31:0] id_pc;
	reg [31:0] id_pred_pc;
	reg        id_pred_taken;

	reg        ex_valid;
	reg [31:0] ex_inst;
	reg [31:0] ex_pc;
	reg [31:0] ex_pred_pc;
	reg        ex_pred_taken;
	reg [31:0] ex_src1;
	reg [31:0] ex_src2;
	reg [31:0] ex_rt_value;

	reg        mem_valid;
	reg [31:0] mem_inst;
	reg [31:0] mem_pc;
	reg [31:0] mem_aluout;
	reg [31:0] mem_store_value;
	reg [31:0] mem_rt_value;
	reg        mem_wen;
	reg [4:0]  mem_waddr;
	reg [31:0] mem_wdata;
	reg        mem_hi_we;
	reg        mem_lo_we;
	reg [31:0] mem_hi_data;
	reg [31:0] mem_lo_data;
	reg        mem_cp0_we;
	reg [31:0] mem_cp0_data;
	reg        mem_req_done;
	reg        mem_load_done;
	reg [31:0] mem_load_buf;

	reg        wb_valid;
	reg [31:0] wb_inst;
	reg [31:0] wb_pc;
	reg        wb_wen;
	reg [4:0]  wb_waddr;
	reg [31:0] wb_wdata;
	reg        wb_hi_we;
	reg        wb_lo_we;
	reg [31:0] wb_hi_data;
	reg [31:0] wb_lo_data;
	reg        wb_cp0_we;
	reg [31:0] wb_cp0_data;

	reg [31:0] HI;
	reg [31:0] LO;
	reg [31:0] cp0_epc;
	reg        in_exception;
	reg        intr_sample;

	reg        div_busy;
	reg        div_done;
	reg [ 5:0] div_count;
	reg [31:0] div_dividend;
	reg [31:0] div_divisor;
	reg [31:0] div_quotient;
	reg [32:0] div_remainder;

	reg [31:0] cycle_cnt;
	reg [31:0] mem_wait_cycle_cnt;
	reg [31:0] retired_inst_cnt;
	reg [31:0] branch_inst_cnt;
	reg [31:0] branch_miss_cnt;
	reg [31:0] load_inst_cnt;
	reg [31:0] store_inst_cnt;

	reg        btb_valid [0:BTB_ENTRIES-1];
	reg [25:0] btb_tag   [0:BTB_ENTRIES-1];
	reg [31:0] btb_target[0:BTB_ENTRIES-1];

	integer i;


	wire id_special = (id_inst[31:26] == 6'b000000);
	wire id_regimm = (id_inst[31:26] == 6'b000001);
	wire id_special2 = (id_inst[31:26] == 6'b011100);
	wire id_nop = (id_inst == 32'b0);
	wire id_shift_fixed = id_special & ((id_inst[5:0] == 6'h00) | (id_inst[5:0] == 6'h02) | (id_inst[5:0] == 6'h03));
	wire id_shift_var = id_special & ((id_inst[5:0] == 6'h04) | (id_inst[5:0] == 6'h06) | (id_inst[5:0] == 6'h07));
	wire id_shift = id_shift_fixed | id_shift_var;
	wire id_r_alu = id_special & ((id_inst[5:0] == 6'h20) | (id_inst[5:0] == 6'h21) |
	                             (id_inst[5:0] == 6'h22) | (id_inst[5:0] == 6'h23) |
	                             (id_inst[5:0] == 6'h24) | (id_inst[5:0] == 6'h25) |
	                             (id_inst[5:0] == 6'h26) | (id_inst[5:0] == 6'h27) |
	                             (id_inst[5:0] == 6'h2a) | (id_inst[5:0] == 6'h2b));
	wire id_i_alu = (id_inst[31:26] == 6'h08) | (id_inst[31:26] == 6'h09) |
	                (id_inst[31:26] == 6'h0a) | (id_inst[31:26] == 6'h0b) |
	                (id_inst[31:26] == 6'h0c) | (id_inst[31:26] == 6'h0d) |
	                (id_inst[31:26] == 6'h0e);
	wire id_lui = (id_inst[31:26] == 6'h0f);
	wire id_load = (id_inst[31:26] == 6'h20) | (id_inst[31:26] == 6'h21) |
	               (id_inst[31:26] == 6'h22) | (id_inst[31:26] == 6'h23) |
	               (id_inst[31:26] == 6'h24) | (id_inst[31:26] == 6'h25) |
	               (id_inst[31:26] == 6'h26);
	wire id_store = (id_inst[31:26] == 6'h28) | (id_inst[31:26] == 6'h29) |
	                (id_inst[31:26] == 6'h2a) | (id_inst[31:26] == 6'h2b) |
	                (id_inst[31:26] == 6'h2e);
	wire id_branch = (id_inst[31:26] == 6'h04) | (id_inst[31:26] == 6'h05) |
	                 (id_inst[31:26] == 6'h06) | (id_inst[31:26] == 6'h07) |
	                 (id_regimm & ((id_inst[20:16] == 5'h00) | (id_inst[20:16] == 5'h01) |
	                               (id_inst[20:16] == 5'h10) | (id_inst[20:16] == 5'h11)));
	wire id_jump = (id_inst[31:26] == 6'h02) | (id_inst[31:26] == 6'h03) |
	               (id_special & ((id_inst[5:0] == 6'h08) | (id_inst[5:0] == 6'h09)));
	wire id_j = (id_inst[31:26] == 6'h02);
	wire id_jal = (id_inst[31:26] == 6'h03);
	wire id_mov = id_special & ((id_inst[5:0] == 6'h0a) | (id_inst[5:0] == 6'h0b));
	wire id_mfhi = id_special & (id_inst[5:0] == 6'h10);
	wire id_mflo = id_special & (id_inst[5:0] == 6'h12);
	wire id_hilo_write = id_special & ((id_inst[5:0] == 6'h11) | (id_inst[5:0] == 6'h13) |
	                                  (id_inst[5:0] == 6'h18) | (id_inst[5:0] == 6'h19) |
	                                  (id_inst[5:0] == 6'h1b));
	wire id_mfc0 = (id_inst[31:26] == 6'b010000) & (id_inst[25:21] == 5'b00000);
	wire id_mtc0 = (id_inst[31:26] == 6'b010000) & (id_inst[25:21] == 5'b00100);
	wire id_eret = (id_inst[31:26] == 6'b010000) & (id_inst[25:21] == 5'b10000) & (id_inst[5:0] == 6'h18);
	wire id_uses_rs_dec = (id_r_alu | id_shift_var | id_mov | id_hilo_write | id_jump |
	                       id_branch | id_i_alu | id_load | id_store) &
	                      ~(id_shift_fixed | id_lui | id_j | id_jal | id_mfc0 | id_mtc0 | id_eret | id_nop);
	wire id_uses_rt_dec = (id_r_alu | id_shift | id_mov |
	                       (id_special & ((id_inst[5:0] == 6'h18) | (id_inst[5:0] == 6'h19) |
	                                      (id_inst[5:0] == 6'h1b))) |
	                       id_store | (id_inst[31:26] == 6'h04) | (id_inst[31:26] == 6'h05) |
	                       id_mtc0 | (id_inst[31:26] == 6'h22) | (id_inst[31:26] == 6'h26)) & ~id_nop;

	wire ex_special_dec = (ex_inst[31:26] == 6'b000000);
	wire ex_regimm_dec = (ex_inst[31:26] == 6'b000001);
	wire ex_special2_dec = (ex_inst[31:26] == 6'b011100);
	wire ex_nop_dec = (ex_inst == 32'b0);
	wire ex_shift_fixed_dec = ex_special_dec & ((ex_inst[5:0] == 6'h00) | (ex_inst[5:0] == 6'h02) | (ex_inst[5:0] == 6'h03));
	wire ex_shift_var_dec = ex_special_dec & ((ex_inst[5:0] == 6'h04) | (ex_inst[5:0] == 6'h06) | (ex_inst[5:0] == 6'h07));
	wire ex_shift_dec = ex_shift_fixed_dec | ex_shift_var_dec;
	wire ex_r_alu_dec = ex_special_dec & ((ex_inst[5:0] == 6'h20) | (ex_inst[5:0] == 6'h21) |
	                                     (ex_inst[5:0] == 6'h22) | (ex_inst[5:0] == 6'h23) |
	                                     (ex_inst[5:0] == 6'h24) | (ex_inst[5:0] == 6'h25) |
	                                     (ex_inst[5:0] == 6'h26) | (ex_inst[5:0] == 6'h27) |
	                                     (ex_inst[5:0] == 6'h2a) | (ex_inst[5:0] == 6'h2b));
	wire ex_i_alu_dec = (ex_inst[31:26] == 6'h08) | (ex_inst[31:26] == 6'h09) |
	                    (ex_inst[31:26] == 6'h0a) | (ex_inst[31:26] == 6'h0b) |
	                    (ex_inst[31:26] == 6'h0c) | (ex_inst[31:26] == 6'h0d) |
	                    (ex_inst[31:26] == 6'h0e);
	wire ex_lui_dec = (ex_inst[31:26] == 6'h0f);
	wire ex_load_dec = (ex_inst[31:26] == 6'h20) | (ex_inst[31:26] == 6'h21) |
	                   (ex_inst[31:26] == 6'h22) | (ex_inst[31:26] == 6'h23) |
	                   (ex_inst[31:26] == 6'h24) | (ex_inst[31:26] == 6'h25) |
	                   (ex_inst[31:26] == 6'h26);
	wire ex_store_dec = (ex_inst[31:26] == 6'h28) | (ex_inst[31:26] == 6'h29) |
	                    (ex_inst[31:26] == 6'h2a) | (ex_inst[31:26] == 6'h2b) |
	                    (ex_inst[31:26] == 6'h2e);
	wire ex_branch_dec = (ex_inst[31:26] == 6'h04) | (ex_inst[31:26] == 6'h05) |
	                     (ex_inst[31:26] == 6'h06) | (ex_inst[31:26] == 6'h07) |
	                     (ex_regimm_dec & ((ex_inst[20:16] == 5'h00) | (ex_inst[20:16] == 5'h01) |
	                                      (ex_inst[20:16] == 5'h10) | (ex_inst[20:16] == 5'h11)));
	wire ex_regimm_link_dec = ex_regimm_dec & ((ex_inst[20:16] == 5'h10) | (ex_inst[20:16] == 5'h11));
	wire ex_jump_dec = (ex_inst[31:26] == 6'h02) | (ex_inst[31:26] == 6'h03) |
	                   (ex_special_dec & ((ex_inst[5:0] == 6'h08) | (ex_inst[5:0] == 6'h09)));
	wire ex_jal_dec = (ex_inst[31:26] == 6'h03);
	wire ex_jalr_dec = ex_special_dec & (ex_inst[5:0] == 6'h09);
	wire ex_jr_dec = ex_special_dec & (ex_inst[5:0] == 6'h08);
	wire ex_mov_dec = ex_special_dec & ((ex_inst[5:0] == 6'h0a) | (ex_inst[5:0] == 6'h0b));
	wire ex_mfhi_dec = ex_special_dec & (ex_inst[5:0] == 6'h10);
	wire ex_mflo_dec = ex_special_dec & (ex_inst[5:0] == 6'h12);
	wire ex_hilo_write_dec = ex_special_dec & ((ex_inst[5:0] == 6'h11) | (ex_inst[5:0] == 6'h13) |
	                                         (ex_inst[5:0] == 6'h18) | (ex_inst[5:0] == 6'h19) |
	                                         (ex_inst[5:0] == 6'h1b));
	wire ex_mul_dec = ex_special2_dec & (ex_inst[5:0] == 6'h02);
	wire ex_divu_dec = ex_special_dec & (ex_inst[5:0] == 6'h1b);
	wire ex_mfc0_dec = (ex_inst[31:26] == 6'b010000) & (ex_inst[25:21] == 5'b00000);
	wire ex_mtc0_dec = (ex_inst[31:26] == 6'b010000) & (ex_inst[25:21] == 5'b00100);
	wire ex_eret_dec = (ex_inst[31:26] == 6'b010000) & (ex_inst[25:21] == 5'b10000) & (ex_inst[5:0] == 6'h18);
	wire [4:0] ex_dest_gpr = ex_jal_dec ? 5'd31 :
	                         ex_jalr_dec ? ex_inst[15:11] :
	                         ex_mfc0_dec ? ex_inst[20:16] :
	                         (ex_load_dec | ex_i_alu_dec | ex_lui_dec) ? ex_inst[20:16] :
	                         ex_regimm_link_dec ? 5'd31 : ex_inst[15:11];

	wire mem_nop_dec = (mem_inst == 32'b0);
	wire mem_special_dec = (mem_inst[31:26] == 6'b000000);
	wire mem_regimm_dec = (mem_inst[31:26] == 6'b000001);
	wire mem_special2_dec = (mem_inst[31:26] == 6'b011100);
	wire mem_shift_fixed_dec = mem_special_dec & ((mem_inst[5:0] == 6'h00) | (mem_inst[5:0] == 6'h02) | (mem_inst[5:0] == 6'h03));
	wire mem_shift_var_dec = mem_special_dec & ((mem_inst[5:0] == 6'h04) | (mem_inst[5:0] == 6'h06) | (mem_inst[5:0] == 6'h07));
	wire mem_shift_dec = mem_shift_fixed_dec | mem_shift_var_dec;
	wire mem_r_alu_dec = mem_special_dec & ((mem_inst[5:0] == 6'h20) | (mem_inst[5:0] == 6'h21) |
	                                      (mem_inst[5:0] == 6'h22) | (mem_inst[5:0] == 6'h23) |
	                                      (mem_inst[5:0] == 6'h24) | (mem_inst[5:0] == 6'h25) |
	                                      (mem_inst[5:0] == 6'h26) | (mem_inst[5:0] == 6'h27) |
	                                      (mem_inst[5:0] == 6'h2a) | (mem_inst[5:0] == 6'h2b));
	wire mem_i_alu_dec = (mem_inst[31:26] == 6'h08) | (mem_inst[31:26] == 6'h09) |
	                     (mem_inst[31:26] == 6'h0a) | (mem_inst[31:26] == 6'h0b) |
	                     (mem_inst[31:26] == 6'h0c) | (mem_inst[31:26] == 6'h0d) |
	                     (mem_inst[31:26] == 6'h0e);
	wire mem_lui_dec = (mem_inst[31:26] == 6'h0f);
	wire mem_load_dec = (mem_inst[31:26] == 6'h20) | (mem_inst[31:26] == 6'h21) |
	                    (mem_inst[31:26] == 6'h22) | (mem_inst[31:26] == 6'h23) |
	                    (mem_inst[31:26] == 6'h24) | (mem_inst[31:26] == 6'h25) |
	                    (mem_inst[31:26] == 6'h26);
	wire mem_store_dec = (mem_inst[31:26] == 6'h28) | (mem_inst[31:26] == 6'h29) |
	                     (mem_inst[31:26] == 6'h2a) | (mem_inst[31:26] == 6'h2b) |
	                     (mem_inst[31:26] == 6'h2e);
	wire mem_regimm_link_dec = mem_regimm_dec & ((mem_inst[20:16] == 5'h10) | (mem_inst[20:16] == 5'h11));
	wire mem_jal_dec = (mem_inst[31:26] == 6'h03);
	wire mem_jalr_dec = mem_special_dec & (mem_inst[5:0] == 6'h09);
	wire mem_mov_dec = mem_special_dec & ((mem_inst[5:0] == 6'h0a) | (mem_inst[5:0] == 6'h0b));
	wire mem_mfhi_dec = mem_special_dec & (mem_inst[5:0] == 6'h10);
	wire mem_mflo_dec = mem_special_dec & (mem_inst[5:0] == 6'h12);
	wire mem_hilo_write_dec = mem_special_dec & ((mem_inst[5:0] == 6'h11) | (mem_inst[5:0] == 6'h13) |
	                                          (mem_inst[5:0] == 6'h18) | (mem_inst[5:0] == 6'h19) |
	                                          (mem_inst[5:0] == 6'h1b));
	wire mem_mul_dec = mem_special2_dec & (mem_inst[5:0] == 6'h02);
	wire mem_mfc0_dec = (mem_inst[31:26] == 6'b010000) & (mem_inst[25:21] == 5'b00000);
	wire [4:0] mem_dest_gpr = mem_jal_dec ? 5'd31 :
	                          mem_jalr_dec ? mem_inst[15:11] :
	                          mem_mfc0_dec ? mem_inst[20:16] :
	                          (mem_load_dec | mem_i_alu_dec | mem_lui_dec) ? mem_inst[20:16] :
	                          mem_regimm_link_dec ? 5'd31 : mem_inst[15:11];

	wire wb_nop_dec = (wb_inst == 32'b0);
	wire wb_load_dec = (wb_inst[31:26] == 6'h20) | (wb_inst[31:26] == 6'h21) |
	                   (wb_inst[31:26] == 6'h22) | (wb_inst[31:26] == 6'h23) |
	                   (wb_inst[31:26] == 6'h24) | (wb_inst[31:26] == 6'h25) |
	                   (wb_inst[31:26] == 6'h26);
	wire wb_store_dec = (wb_inst[31:26] == 6'h28) | (wb_inst[31:26] == 6'h29) |
	                    (wb_inst[31:26] == 6'h2a) | (wb_inst[31:26] == 6'h2b) |
	                    (wb_inst[31:26] == 6'h2e);
	wire wb_special_dec = (wb_inst[31:26] == 6'b000000);
	wire wb_hilo_write_dec = wb_special_dec & ((wb_inst[5:0] == 6'h11) | (wb_inst[5:0] == 6'h13) |
	                                        (wb_inst[5:0] == 6'h18) | (wb_inst[5:0] == 6'h19) |
	                                        (wb_inst[5:0] == 6'h1b));

	wire [4:0] RF_raddr1;
	wire [4:0] RF_raddr2;
	wire [4:0] RF_waddr;
	wire       RF_wen;
	wire [31:0] RF_wdata;
	wire [31:0] RF_rdata1;
	wire [31:0] RF_rdata2;

	assign RF_raddr1 = id_inst[25:21];
	assign RF_raddr2 = id_inst[20:16];
	assign RF_waddr  = wb_waddr;
	assign RF_wdata  = wb_wdata;
	assign RF_wen    = wb_valid & wb_wen;

	reg_file u_reg_file (
		.clk    (clk),
		.waddr  (RF_waddr),
		.raddr1 (RF_raddr1),
		.raddr2 (RF_raddr2),
		.wen    (RF_wen),
		.wdata  (RF_wdata),
		.rdata1 (RF_rdata1),
		.rdata2 (RF_rdata2)
	);

	wire [3:0] fetch_btb_index;
	wire       fetch_btb_hit;
	wire [31:0] fetch_pred_pc;
	wire        fetch_pred_taken;

	assign fetch_btb_index = fetch_pc[5:2];
	assign fetch_btb_hit = btb_valid[fetch_btb_index] &
	                       (btb_tag[fetch_btb_index] == fetch_pc[31:6]);
	assign fetch_pred_taken = fetch_btb_hit;
	assign fetch_pred_pc = fetch_btb_hit ? btb_target[fetch_btb_index] :
	                                     (fetch_pc + 32'd4);

	wire ex_allowin;
	wire ex_ready_go;
	wire mem_allowin;
	wire wb_allowin;
	wire id_allowin;
	wire id_ready_go;
	wire if_buf_pop;
	wire fetch_start;
	wire fetch_ar_fire;
	wire fetch_rsp_fire;
	wire fetch_rsp_usable;
	wire fetch_rsp_to_id;
	wire fetch_flush;
	wire fetch_pending_after_flush;
	wire redirect_valid;
	wire [31:0] redirect_pc;
	wire ex_redirect_valid;
	wire id_redirect_valid;
	wire pipeline_empty;
	wire drain_intr;
	wire take_intr;

	wire id_uses_rs;
	wire id_uses_rt;
	wire id_hazard_rs_ex;
	wire id_hazard_rt_ex;
	wire id_hazard_rs_mem;
	wire id_hazard_rt_mem;
	wire id_hilo_hazard;
	wire id_dep_ex_gpr;
	wire ex_gpr_pending;
	wire mem_forward_valid;
	wire mem_result_ready;
	wire wb_forward_valid;
	wire [31:0] id_rs_value;
	wire [31:0] id_rt_value;
	wire [31:0] ex_src1_actual;
	wire [31:0] ex_src2_actual;
	wire [31:0] ex_rt_value_actual;
	wire [31:0] ex_hi_actual;
	wire [31:0] ex_lo_actual;

	assign id_uses_rs = id_valid & id_uses_rs_dec;
	assign id_uses_rt = id_valid & id_uses_rt_dec;

	assign id_hazard_rs_ex = id_uses_rs & ex_valid & ex_load_dec &
	                         (ex_dest_gpr != 5'b0) &
	                         (ex_dest_gpr == id_inst[25:21]);
	assign id_hazard_rt_ex = id_uses_rt & ex_valid & ex_load_dec &
	                         (ex_dest_gpr != 5'b0) &
	                         (ex_dest_gpr == id_inst[20:16]);
	assign ex_gpr_pending = ex_valid & ~ex_nop_dec &
	                        (ex_load_dec | ex_r_alu_dec | ex_shift_dec |
	                         ex_i_alu_dec | ex_lui_dec | ex_jal_dec |
	                         ex_jalr_dec | ex_regimm_link_dec |
	                         ex_mov_dec | ex_mfhi_dec | ex_mflo_dec |
	                         ex_mul_dec | ex_mfc0_dec) &
	                        (ex_dest_gpr != 5'b0);
	assign id_dep_ex_gpr = ex_gpr_pending &
	                       ((id_uses_rs & (ex_dest_gpr == id_inst[25:21])) |
	                        (id_uses_rt & (ex_dest_gpr == id_inst[20:16])));
	assign mem_forward_valid = mem_valid & mem_wen & ~mem_load_dec &
	                           (mem_waddr != 5'b0);
	assign mem_result_ready = mem_forward_valid |
	                          (mem_valid & mem_wen & mem_load_dec &
	                           (mem_load_done | Read_data_Valid) &
	                           (mem_waddr != 5'b0));
	assign wb_forward_valid = wb_valid & wb_wen & (wb_waddr != 5'b0);

	assign id_hazard_rs_mem = id_uses_rs & mem_valid & mem_wen &
	                          (mem_dest_gpr != 5'b0) &
	                          (mem_dest_gpr == id_inst[25:21]) &
	                          ~mem_result_ready;
	assign id_hazard_rt_mem = id_uses_rt & mem_valid & mem_wen &
	                          (mem_dest_gpr != 5'b0) &
	                          (mem_dest_gpr == id_inst[20:16]) &
	                          ~mem_result_ready;
	assign id_hilo_hazard = 1'b0;

	assign id_ready_go = ~id_valid |
	                     ~(id_hazard_rs_ex | id_hazard_rt_ex |
	                       id_hazard_rs_mem | id_hazard_rt_mem |
	                       id_hilo_hazard);

	assign id_rs_value = (mem_forward_valid & (mem_waddr == id_inst[25:21])) ? mem_wdata :
	                     (wb_forward_valid & (wb_waddr == id_inst[25:21])) ? wb_wdata :
	                     RF_rdata1;
	assign id_rt_value = (mem_forward_valid & (mem_waddr == id_inst[20:16])) ? mem_wdata :
	                     (wb_forward_valid & (wb_waddr == id_inst[20:16])) ? wb_wdata :
	                     RF_rdata2;

	assign ex_src1_actual = (mem_forward_valid & (mem_waddr == ex_rs)) ? mem_wdata :
	                        (wb_forward_valid & (wb_waddr == ex_rs)) ? wb_wdata :
	                        ex_src1;
	assign ex_src2_actual = (mem_forward_valid & (mem_waddr == ex_rt)) ? mem_wdata :
	                        (wb_forward_valid & (wb_waddr == ex_rt)) ? wb_wdata :
	                        ex_src2;
	assign ex_rt_value_actual = ex_src2_actual;
	assign ex_hi_actual = (mem_valid & mem_hi_we) ? mem_hi_data :
	                      (wb_valid & wb_hi_we) ? wb_hi_data :
	                      HI;
	assign ex_lo_actual = (mem_valid & mem_lo_we) ? mem_lo_data :
	                      (wb_valid & wb_lo_we) ? wb_lo_data :
	                      LO;

	assign wb_allowin = 1'b1;

	wire mem_is_load;
	wire mem_is_store;
	wire mem_ready_go;
	assign mem_is_load = mem_valid & mem_load_dec;
	assign mem_is_store = mem_valid & mem_store_dec;
	assign mem_ready_go = ~mem_valid |
	                      (mem_is_load ? (mem_load_done | Read_data_Valid) :
	                       (mem_is_store ? Mem_Req_Ready : 1'b1));
	assign mem_allowin = ~mem_valid | (mem_ready_go & wb_allowin);

	assign ex_ready_go = ~ex_divu_dec | div_done;
	assign ex_allowin = ~ex_valid | (ex_ready_go & mem_allowin);
	assign id_allowin = ~id_valid | (id_ready_go & ex_allowin);
	assign if_buf_pop = if_buf_valid & id_allowin & ~redirect_valid & ~take_intr;

	assign fetch_start = ~fetch_req_valid & (~fetch_busy | fetch_rsp_fire) &
	                     ((~if_buf_valid | if_buf_pop) &
	                      ~(fetch_rsp_usable & ~fetch_rsp_to_id)) &
	                     ~redirect_valid & ~take_intr & ~drain_intr;
	assign fetch_ar_fire = fetch_req_valid & Inst_Req_Ready;
	assign fetch_rsp_fire = fetch_busy & Inst_Valid;
	assign fetch_rsp_usable = fetch_rsp_fire & ~fetch_drop & ~fetch_flush;
	assign fetch_rsp_to_id = fetch_rsp_usable & ~if_buf_valid & id_allowin;
	assign fetch_flush = redirect_valid | take_intr;
	assign fetch_pending_after_flush = fetch_req_valid | (fetch_busy & ~fetch_rsp_fire);

	assign pipeline_empty = ~fetch_req_valid & ~fetch_busy & ~if_buf_valid &
	                        ~id_valid & ~ex_valid & ~mem_valid & ~wb_valid;
	assign drain_intr = intr_sample & ~in_exception;
	assign take_intr = drain_intr & pipeline_empty;

	wire id_jr_dec;
	wire id_jalr_dec;
	wire id_control;
	wire id_branch_taken;
	wire [15:0] id_imm;
	wire [25:0] id_target;
	wire [31:0] id_sign_imm;
	wire [31:0] id_pc_plus4;
	wire [31:0] id_branch_target;
	wire [31:0] id_jump_target;
	wire [31:0] id_actual_next_pc;
	wire        id_redirect_ready;

	assign id_jr_dec = id_special & (id_inst[5:0] == 6'h08);
	assign id_jalr_dec = id_special & (id_inst[5:0] == 6'h09);
	assign id_imm = id_inst[15:0];
	assign id_target = id_inst[25:0];
	assign id_sign_imm = {{16{id_imm[15]}}, id_imm};
	assign id_pc_plus4 = id_pc + 32'd4;
	assign id_branch_taken =
		((id_inst[31:26] == 6'h04) & (id_rs_value == id_rt_value)) |
		((id_inst[31:26] == 6'h05) & (id_rs_value != id_rt_value)) |
		((id_inst[31:26] == 6'h06) & (id_rs_value[31] | (id_rs_value == 32'b0))) |
		((id_inst[31:26] == 6'h07) & (~id_rs_value[31] & (id_rs_value != 32'b0))) |
		(id_regimm & (id_inst[20:16] == 5'h00) & id_rs_value[31]) |
		(id_regimm & (id_inst[20:16] == 5'h01) & ~id_rs_value[31]) |
		(id_regimm & (id_inst[20:16] == 5'h10) & id_rs_value[31]) |
		(id_regimm & (id_inst[20:16] == 5'h11) & ~id_rs_value[31]);
	assign id_branch_target = id_pc_plus4 + {id_sign_imm[29:0], 2'b00};
	assign id_jump_target = {id_pc_plus4[31:28], id_target, 2'b00};
	assign id_control = id_branch | id_jump | id_eret;
	assign id_actual_next_pc = id_eret ? cp0_epc :
	                           (id_jr_dec | id_jalr_dec) ? id_rs_value :
	                           (id_j | id_jal) ? id_jump_target :
	                           (id_branch & id_branch_taken) ? id_branch_target :
	                           id_pc_plus4;
	assign id_redirect_ready = id_valid & id_ready_go & id_control & ~id_dep_ex_gpr;

	wire [5:0] ex_opcode;
	wire [5:0] ex_func;
	wire [4:0] ex_rs;
	wire [4:0] ex_rt;
	wire [4:0] ex_rd;
	wire [15:0] ex_imm;
	wire [25:0] ex_target;
	wire [31:0] ex_sign_imm;
	wire [31:0] ex_zero_imm;
	wire [31:0] ex_pc_plus4;
	wire [31:0] ex_pc_plus8;

	assign ex_opcode = ex_inst[31:26];
	assign ex_func = ex_inst[5:0];
	assign ex_rs = ex_inst[25:21];
	assign ex_rt = ex_inst[20:16];
	assign ex_rd = ex_inst[15:11];
	assign ex_imm = ex_inst[15:0];
	assign ex_target = ex_inst[25:0];
	assign ex_sign_imm = {{16{ex_imm[15]}}, ex_imm};
	assign ex_zero_imm = {16'b0, ex_imm};
	assign ex_pc_plus4 = ex_pc + 32'd4;
	assign ex_pc_plus8 = ex_pc + 32'd8;

	wire [2:0] ex_aluop;
	wire [31:0] ex_alu_b;
	wire [31:0] ex_alu_result;
	wire ex_alu_zero;
	wire ex_alu_overflow;
	wire ex_alu_carryout;

	assign ex_aluop = ((ex_r_alu_dec & (ex_func == 6'h24)) |
	                   (ex_opcode == 6'h0c)) ? 3'b000 :
	                  ((ex_r_alu_dec & (ex_func == 6'h25)) |
	                   (ex_opcode == 6'h0d)) ? 3'b001 :
	                  ((ex_r_alu_dec & (ex_func == 6'h26)) |
	                   (ex_opcode == 6'h0e)) ? 3'b100 :
	                  (ex_r_alu_dec & (ex_func == 6'h27)) ? 3'b101 :
	                  ((ex_r_alu_dec &
	                    ((ex_func == 6'h22) | (ex_func == 6'h23))) |
	                   (ex_opcode == 6'h04) | (ex_opcode == 6'h05)) ? 3'b110 :
	                  ((ex_r_alu_dec & (ex_func == 6'h2a)) |
	                   (ex_opcode == 6'h0a)) ? 3'b111 :
	                  ((ex_r_alu_dec & (ex_func == 6'h2b)) |
	                   (ex_opcode == 6'h0b)) ? 3'b011 :
	                  3'b010;

	assign ex_alu_b = (ex_r_alu_dec | (ex_opcode == 6'h04) |
	                   (ex_opcode == 6'h05)) ? ex_src2_actual :
	                  ((ex_opcode == 6'h0c) | (ex_opcode == 6'h0d) |
	                   (ex_opcode == 6'h0e)) ? ex_zero_imm :
	                  ex_sign_imm;

	alu u_alu (
		.A        (ex_src1_actual),
		.B        (ex_alu_b),
		.ALUop    (ex_aluop),
		.Overflow (ex_alu_overflow),
		.CarryOut (ex_alu_carryout),
		.Zero     (ex_alu_zero),
		.Result   (ex_alu_result)
	);

	wire [1:0] ex_shiftop;
	wire [4:0] ex_shift_amount;
	wire [31:0] ex_shift_result;

	assign ex_shiftop = ((ex_func == 6'h00) | (ex_func == 6'h04)) ? 2'b00 :
	                    ((ex_func == 6'h02) | (ex_func == 6'h06)) ? 2'b10 :
	                    2'b11;
	assign ex_shift_amount = ex_shift_var_dec ? ex_src1_actual[4:0] : ex_inst[10:6];

	shifter u_shifter (
		.A       (ex_src2_actual),
		.B       (ex_shift_amount),
		.Shiftop (ex_shiftop),
		.Result  (ex_shift_result)
	);

	wire ex_mov_cond;
	wire ex_branch_taken;
	wire ex_control;
	wire [31:0] ex_branch_target;
	wire [31:0] ex_jump_target;
	wire [31:0] ex_actual_next_pc;
	wire ex_actual_taken;

	assign ex_mov_cond = ((ex_func == 6'h0a) & (ex_src2_actual == 32'b0)) |
	                     ((ex_func == 6'h0b) & (ex_src2_actual != 32'b0));

	assign ex_branch_taken =
		((ex_opcode == 6'h04) & (ex_src1_actual == ex_src2_actual)) |
		((ex_opcode == 6'h05) & (ex_src1_actual != ex_src2_actual)) |
		((ex_opcode == 6'h06) & (ex_src1_actual[31] | (ex_src1_actual == 32'b0))) |
		((ex_opcode == 6'h07) & (~ex_src1_actual[31] & (ex_src1_actual != 32'b0))) |
		(ex_regimm_dec & (ex_rt == 5'h00) & ex_src1_actual[31]) |
		(ex_regimm_dec & (ex_rt == 5'h01) & ~ex_src1_actual[31]) |
		(ex_regimm_dec & (ex_rt == 5'h10) & ex_src1_actual[31]) |
		(ex_regimm_dec & (ex_rt == 5'h11) & ~ex_src1_actual[31]);

	assign ex_branch_target = ex_pc_plus4 + {ex_sign_imm[29:0], 2'b00};
	assign ex_jump_target = {ex_pc_plus4[31:28], ex_target, 2'b00};
	assign ex_control = ex_branch_dec | ex_jump_dec | ex_eret_dec;
	assign ex_actual_taken = ex_eret_dec | ex_jr_dec | ex_jalr_dec |
	                         (ex_opcode == 6'h02) | (ex_opcode == 6'h03) |
	                         (ex_branch_dec & ex_branch_taken);
	assign ex_actual_next_pc = ex_eret_dec ? cp0_epc :
	                           (ex_jr_dec | ex_jalr_dec) ? ex_src1_actual :
	                           ((ex_opcode == 6'h02) | (ex_opcode == 6'h03)) ? ex_jump_target :
	                           (ex_branch_dec & ex_branch_taken) ? ex_branch_target :
	                           ex_pc_plus4;

	assign ex_redirect_valid = ex_valid & ex_control &
	                           (ex_actual_next_pc != ex_pred_pc);
	assign id_redirect_valid = id_redirect_ready &
	                           (id_actual_next_pc != id_pred_pc) &
	                           ~ex_redirect_valid;
	assign redirect_valid = ex_redirect_valid | id_redirect_valid;
	assign redirect_pc = ex_redirect_valid ? ex_actual_next_pc : id_actual_next_pc;

	wire ex_wen_actual;
	wire [4:0] ex_waddr;
	wire [31:0] ex_wdata_base;
	wire signed [31:0] ex_signed_src1;
	wire signed [31:0] ex_signed_src2;
	wire [63:0] ex_mult_unsigned;
	wire signed [63:0] ex_mult_signed;
	wire ex_hi_we;
	wire ex_lo_we;
	wire [31:0] ex_hi_data;
	wire [31:0] ex_lo_data;
	wire ex_cp0_we;
	wire [31:0] ex_cp0_data;

	assign ex_signed_src1 = ex_src1_actual;
	assign ex_signed_src2 = ex_src2_actual;
	assign ex_mult_signed = ex_signed_src1 * ex_signed_src2;
	assign ex_mult_unsigned = ex_src1_actual * ex_src2_actual;
	assign ex_waddr = ex_dest_gpr;
	assign ex_wen_actual = ex_valid & ~ex_nop_dec &
	                       (ex_load_dec | ex_r_alu_dec | ex_shift_dec |
	                        ex_i_alu_dec | ex_lui_dec | ex_jal_dec |
	                        ex_jalr_dec | (ex_regimm_link_dec & ex_branch_taken) |
	                        (ex_mov_dec & ex_mov_cond) | ex_mfhi_dec |
	                        ex_mflo_dec | ex_mul_dec | ex_mfc0_dec);

	assign ex_wdata_base = ex_lui_dec ? {ex_imm, 16'b0} :
	                       (ex_jal_dec | ex_jalr_dec |
	                        ex_regimm_link_dec) ? ex_pc_plus8 :
	                       ex_shift_dec ? ex_shift_result :
	                       ex_mov_dec ? ex_src1_actual :
	                       ex_mfhi_dec ? ex_hi_actual :
	                       ex_mflo_dec ? ex_lo_actual :
	                       ex_mfc0_dec ? ((ex_rd == 5'd14) ? cp0_epc : 32'b0) :
	                       ex_mul_dec ? ex_mult_signed[31:0] :
	                       ex_alu_result;

	assign ex_hi_we = ex_valid & ex_hilo_write_dec &
	                  ((ex_func == 6'h11) | (ex_func == 6'h18) |
	                   (ex_func == 6'h19) | (ex_func == 6'h1b));
	assign ex_lo_we = ex_valid & ex_hilo_write_dec &
	                  ((ex_func == 6'h13) | (ex_func == 6'h18) |
	                   (ex_func == 6'h19) | (ex_func == 6'h1b));
	assign ex_hi_data = (ex_func == 6'h11) ? ex_src1_actual :
	                    (ex_func == 6'h19) ? ex_mult_unsigned[63:32] :
	                    (ex_func == 6'h1b) ? div_remainder[31:0] :
	                    ex_mult_signed[63:32];
	assign ex_lo_data = (ex_func == 6'h13) ? ex_src1_actual :
	                    (ex_func == 6'h19) ? ex_mult_unsigned[31:0] :
	                    (ex_func == 6'h1b) ? div_quotient :
	                    ex_mult_signed[31:0];
	assign ex_cp0_we = ex_valid & ex_mtc0_dec & (ex_rd == 5'd14);
	assign ex_cp0_data = ex_rt_value_actual;

	wire [1:0] mem_byte_offset;
	wire mem_addr_0;
	wire mem_addr_1;
	wire mem_addr_2;
	wire mem_addr_3;
	wire [31:0] mem_raw_load_data;
	wire [31:0] mem_byte_load_data;
	wire [31:0] mem_half_load_data;
	wire [31:0] mem_lwl_load_data;
	wire [31:0] mem_lwr_load_data;
	wire [31:0] mem_load_result;
	wire [3:0] mem_sb_strb;
	wire [3:0] mem_sh_strb;
	wire [3:0] mem_swl_strb;
	wire [3:0] mem_swr_strb;
	wire [31:0] mem_sb_wdata;
	wire [31:0] mem_sh_wdata;
	wire [31:0] mem_swl_wdata;
	wire [31:0] mem_swr_wdata;
	wire [3:0] mem_write_strb;
	wire [31:0] mem_write_data;
	wire [31:0] mem_final_wdata;

	assign mem_byte_offset = mem_aluout[1:0];
	assign mem_addr_0 = (mem_byte_offset == 2'b00);
	assign mem_addr_1 = (mem_byte_offset == 2'b01);
	assign mem_addr_2 = (mem_byte_offset == 2'b10);
	assign mem_addr_3 = (mem_byte_offset == 2'b11);
	assign mem_raw_load_data = Read_data_Valid ? Read_data : mem_load_buf;

	assign mem_byte_load_data =
		({32{mem_addr_0}} & {{24{mem_raw_load_data[ 7] & (mem_inst[31:26] == 6'h20)}}, mem_raw_load_data[ 7: 0]}) |
		({32{mem_addr_1}} & {{24{mem_raw_load_data[15] & (mem_inst[31:26] == 6'h20)}}, mem_raw_load_data[15: 8]}) |
		({32{mem_addr_2}} & {{24{mem_raw_load_data[23] & (mem_inst[31:26] == 6'h20)}}, mem_raw_load_data[23:16]}) |
		({32{mem_addr_3}} & {{24{mem_raw_load_data[31] & (mem_inst[31:26] == 6'h20)}}, mem_raw_load_data[31:24]});

	assign mem_half_load_data =
		({32{mem_addr_0}} & {{16{mem_raw_load_data[15] & (mem_inst[31:26] == 6'h21)}}, mem_raw_load_data[15: 0]}) |
		({32{mem_addr_2}} & {{16{mem_raw_load_data[31] & (mem_inst[31:26] == 6'h21)}}, mem_raw_load_data[31:16]});

	assign mem_lwl_load_data =
		({32{mem_addr_0}} & {mem_raw_load_data[ 7:0], mem_rt_value[23:0]}) |
		({32{mem_addr_1}} & {mem_raw_load_data[15:0], mem_rt_value[15:0]}) |
		({32{mem_addr_2}} & {mem_raw_load_data[23:0], mem_rt_value[ 7:0]}) |
		({32{mem_addr_3}} & mem_raw_load_data);

	assign mem_lwr_load_data =
		({32{mem_addr_0}} & mem_raw_load_data) |
		({32{mem_addr_1}} & {mem_rt_value[31:24], mem_raw_load_data[31: 8]}) |
		({32{mem_addr_2}} & {mem_rt_value[31:16], mem_raw_load_data[31:16]}) |
		({32{mem_addr_3}} & {mem_rt_value[31: 8], mem_raw_load_data[31:24]});

	assign mem_load_result = ((mem_inst[31:26] == 6'h20) | (mem_inst[31:26] == 6'h24)) ? mem_byte_load_data :
	                         ((mem_inst[31:26] == 6'h21) | (mem_inst[31:26] == 6'h25)) ? mem_half_load_data :
	                         (mem_inst[31:26] == 6'h22) ? mem_lwl_load_data :
	                         (mem_inst[31:26] == 6'h26) ? mem_lwr_load_data :
	                         mem_raw_load_data;

	assign mem_sb_strb = mem_addr_0 ? 4'b0001 :
	                     mem_addr_1 ? 4'b0010 :
	                     mem_addr_2 ? 4'b0100 : 4'b1000;
	assign mem_sh_strb = mem_addr_0 ? 4'b0011 :
	                     mem_addr_2 ? 4'b1100 : 4'b0000;
	assign mem_swl_strb = mem_addr_0 ? 4'b0001 :
	                      mem_addr_1 ? 4'b0011 :
	                      mem_addr_2 ? 4'b0111 : 4'b1111;
	assign mem_swr_strb = mem_addr_0 ? 4'b1111 :
	                      mem_addr_1 ? 4'b1110 :
	                      mem_addr_2 ? 4'b1100 : 4'b1000;

	assign mem_sb_wdata =
		({32{mem_addr_0}} & {24'b0, mem_store_value[7:0]}) |
		({32{mem_addr_1}} & {16'b0, mem_store_value[7:0], 8'b0}) |
		({32{mem_addr_2}} & {8'b0, mem_store_value[7:0], 16'b0}) |
		({32{mem_addr_3}} & {mem_store_value[7:0], 24'b0});
	assign mem_sh_wdata =
		({32{mem_addr_0}} & {16'b0, mem_store_value[15:0]}) |
		({32{mem_addr_2}} & {mem_store_value[15:0], 16'b0});
	assign mem_swl_wdata =
		({32{mem_addr_0}} & {24'b0, mem_store_value[31:24]}) |
		({32{mem_addr_1}} & {16'b0, mem_store_value[31:16]}) |
		({32{mem_addr_2}} & {8'b0, mem_store_value[31:8]}) |
		({32{mem_addr_3}} & mem_store_value);
	assign mem_swr_wdata =
		({32{mem_addr_0}} & mem_store_value) |
		({32{mem_addr_1}} & {mem_store_value[23:0], 8'b0}) |
		({32{mem_addr_2}} & {mem_store_value[15:0], 16'b0}) |
		({32{mem_addr_3}} & {mem_store_value[7:0], 24'b0});

	assign mem_write_strb = (mem_inst[31:26] == 6'h28) ? mem_sb_strb :
	                        (mem_inst[31:26] == 6'h29) ? mem_sh_strb :
	                        (mem_inst[31:26] == 6'h2b) ? 4'b1111 :
	                        (mem_inst[31:26] == 6'h2a) ? mem_swl_strb :
	                        (mem_inst[31:26] == 6'h2e) ? mem_swr_strb :
	                        4'b0000;
	assign mem_write_data = (mem_inst[31:26] == 6'h28) ? mem_sb_wdata :
	                        (mem_inst[31:26] == 6'h29) ? mem_sh_wdata :
	                        (mem_inst[31:26] == 6'h2b) ? mem_store_value :
	                        (mem_inst[31:26] == 6'h2a) ? mem_swl_wdata :
	                        (mem_inst[31:26] == 6'h2e) ? mem_swr_wdata :
	                        32'b0;
	assign mem_final_wdata = mem_load_dec ? mem_load_result : mem_wdata;

	assign PC = (fetch_req_valid | fetch_busy) ? fetch_req_pc : fetch_pc;
	assign Inst_Req_Valid = ~rst & fetch_req_valid;
	assign Inst_Ready = fetch_busy;

	assign Address = {mem_aluout[31:2], 2'b00};
	assign MemRead = mem_valid & mem_load_dec & ~mem_req_done & ~mem_load_done;
	assign MemWrite = mem_valid & mem_store_dec & ~mem_req_done;
	assign Write_data = mem_write_data;
	assign Write_strb = mem_write_strb;
	assign Read_data_Ready = mem_valid & mem_load_dec;

	wire Mem_Req_Ack;
	assign Mem_Req_Ack = Mem_Req_Ready;
	assign inst_retire = {RF_wen, RF_waddr, RF_wdata, wb_pc};

	assign cpu_perf_cnt_0 = cycle_cnt;
	assign cpu_perf_cnt_1 = mem_wait_cycle_cnt;
	assign cpu_perf_cnt_2 = retired_inst_cnt;
	assign cpu_perf_cnt_3 = branch_inst_cnt;
	assign cpu_perf_cnt_4 = branch_miss_cnt;
	assign cpu_perf_cnt_5 = load_inst_cnt;
	assign cpu_perf_cnt_6 = store_inst_cnt;
	assign cpu_perf_cnt_7 = 32'b0;
	assign cpu_perf_cnt_8 = 32'b0;
	assign cpu_perf_cnt_9 = 32'b0;
	assign cpu_perf_cnt_10 = 32'b0;
	assign cpu_perf_cnt_11 = 32'b0;
	assign cpu_perf_cnt_12 = 32'b0;
	assign cpu_perf_cnt_13 = 32'b0;
	assign cpu_perf_cnt_14 = 32'b0;
	assign cpu_perf_cnt_15 = 32'b0;

	wire [32:0] div_remainder_shift;
	wire [32:0] div_sub_result;
	wire        div_sub_ge;

	assign div_remainder_shift = {div_remainder[31:0], div_dividend[31]};
	assign div_sub_result = div_remainder_shift - {1'b0, div_divisor};
	assign div_sub_ge = div_remainder_shift >= {1'b0, div_divisor};

	always @(posedge clk) begin
		if (rst) begin
			fetch_pc <= 32'b0;
			fetch_req_valid <= 1'b0;
			fetch_busy <= 1'b0;
			fetch_drop <= 1'b0;
			fetch_req_pc <= 32'b0;
			fetch_req_pred_pc <= 32'b0;
			fetch_req_pred_taken <= 1'b0;
			if_buf_valid <= 1'b0;
			if_buf_inst <= 32'b0;
			if_buf_pc <= 32'b0;
			if_buf_pred_pc <= 32'b0;
			if_buf_pred_taken <= 1'b0;
		end else begin
			if (if_buf_pop | fetch_flush)
				if_buf_valid <= 1'b0;

			if (fetch_rsp_fire) begin
				fetch_busy <= 1'b0;
				if (fetch_drop | fetch_flush) begin
					fetch_drop <= 1'b0;
				end else if (~fetch_rsp_to_id) begin
					if_buf_valid <= 1'b1;
					if_buf_inst <= Instruction;
					if_buf_pc <= fetch_req_pc;
					if_buf_pred_pc <= fetch_req_pred_pc;
					if_buf_pred_taken <= fetch_req_pred_taken;
				end
			end

			if (fetch_ar_fire) begin
				fetch_req_valid <= 1'b0;
				fetch_busy <= 1'b1;
				if (~fetch_drop & ~fetch_flush)
					fetch_pc <= fetch_req_pred_pc;
			end

			if (redirect_valid) begin
				fetch_pc <= redirect_pc;
				if_buf_valid <= 1'b0;
				fetch_drop <= fetch_pending_after_flush;
			end else if (take_intr) begin
				fetch_pc <= 32'h00000100;
				if_buf_valid <= 1'b0;
				fetch_drop <= fetch_pending_after_flush;
			end

			if (fetch_start) begin
				fetch_req_valid <= 1'b1;
				fetch_drop <= 1'b0;
				fetch_req_pc <= fetch_pc;
				fetch_req_pred_pc <= fetch_pred_pc;
				fetch_req_pred_taken <= fetch_pred_taken;
			end
		end
	end

	always @(posedge clk) begin
		if (rst | ex_redirect_valid | take_intr) begin
			id_valid <= 1'b0;
			id_inst <= 32'b0;
			id_pc <= 32'b0;
			id_pred_pc <= 32'b0;
			id_pred_taken <= 1'b0;
		end else if (id_allowin) begin
			if (if_buf_valid) begin
				id_valid <= 1'b1;
				id_inst <= if_buf_inst;
				id_pc <= if_buf_pc;
				id_pred_pc <= if_buf_pred_pc;
				id_pred_taken <= if_buf_pred_taken;
			end else if (fetch_rsp_to_id) begin
				id_valid <= 1'b1;
				id_inst <= Instruction;
				id_pc <= fetch_req_pc;
				id_pred_pc <= fetch_req_pred_pc;
				id_pred_taken <= fetch_req_pred_taken;
			end else begin
				id_valid <= 1'b0;
				id_inst <= 32'b0;
				id_pc <= 32'b0;
				id_pred_pc <= 32'b0;
				id_pred_taken <= 1'b0;
			end
		end
	end

	always @(posedge clk) begin
		if (rst | take_intr) begin
			ex_valid <= 1'b0;
			ex_inst <= 32'b0;
			ex_pc <= 32'b0;
			ex_pred_pc <= 32'b0;
			ex_pred_taken <= 1'b0;
			ex_src1 <= 32'b0;
			ex_src2 <= 32'b0;
			ex_rt_value <= 32'b0;
		end else if (ex_redirect_valid) begin
			if (ex_allowin) begin
				ex_valid <= 1'b0;
				ex_inst <= 32'b0;
				ex_pc <= 32'b0;
				ex_pred_pc <= 32'b0;
				ex_pred_taken <= 1'b0;
				ex_src1 <= 32'b0;
				ex_src2 <= 32'b0;
				ex_rt_value <= 32'b0;
			end
		end else if (ex_allowin) begin
			ex_valid <= id_valid & id_ready_go;
			ex_inst <= id_inst;
			ex_pc <= id_pc;
			ex_pred_pc <= id_redirect_valid ? id_actual_next_pc : id_pred_pc;
			ex_pred_taken <= id_pred_taken;
			ex_src1 <= id_rs_value;
			ex_src2 <= id_rt_value;
			ex_rt_value <= id_rt_value;
		end
	end

	always @(posedge clk) begin
		if (rst) begin
			mem_valid <= 1'b0;
			mem_inst <= 32'b0;
			mem_pc <= 32'b0;
			mem_aluout <= 32'b0;
			mem_store_value <= 32'b0;
			mem_rt_value <= 32'b0;
			mem_wen <= 1'b0;
			mem_waddr <= 5'b0;
			mem_wdata <= 32'b0;
			mem_hi_we <= 1'b0;
			mem_lo_we <= 1'b0;
			mem_hi_data <= 32'b0;
			mem_lo_data <= 32'b0;
			mem_cp0_we <= 1'b0;
			mem_cp0_data <= 32'b0;
			mem_req_done <= 1'b0;
			mem_load_done <= 1'b0;
			mem_load_buf <= 32'b0;
		end else if (mem_allowin) begin
			mem_valid <= ex_valid;
			mem_inst <= ex_inst;
			mem_pc <= ex_pc;
			mem_aluout <= ex_alu_result;
			mem_store_value <= ex_rt_value_actual;
			mem_rt_value <= ex_rt_value_actual;
			mem_wen <= ex_wen_actual;
			mem_waddr <= ex_waddr;
			mem_wdata <= ex_wdata_base;
			mem_hi_we <= ex_hi_we;
			mem_lo_we <= ex_lo_we;
			mem_hi_data <= ex_hi_data;
			mem_lo_data <= ex_lo_data;
			mem_cp0_we <= ex_cp0_we;
			mem_cp0_data <= ex_cp0_data;
			mem_req_done <= 1'b0;
			mem_load_done <= 1'b0;
			mem_load_buf <= 32'b0;
		end else begin
			if (mem_valid & (mem_load_dec | mem_store_dec) & Mem_Req_Ready)
				mem_req_done <= 1'b1;
			if (mem_valid & mem_load_dec & Read_data_Valid) begin
				mem_load_done <= 1'b1;
				mem_load_buf <= mem_load_result;
			end
		end
	end

	always @(posedge clk) begin
		if (rst) begin
			wb_valid <= 1'b0;
			wb_inst <= 32'b0;
			wb_pc <= 32'b0;
			wb_wen <= 1'b0;
			wb_waddr <= 5'b0;
			wb_wdata <= 32'b0;
			wb_hi_we <= 1'b0;
			wb_lo_we <= 1'b0;
			wb_hi_data <= 32'b0;
			wb_lo_data <= 32'b0;
			wb_cp0_we <= 1'b0;
			wb_cp0_data <= 32'b0;
		end else begin
			wb_valid <= mem_valid & mem_ready_go;
			wb_inst <= mem_inst;
			wb_pc <= mem_pc;
			wb_wen <= mem_wen;
			wb_waddr <= mem_waddr;
			wb_wdata <= mem_final_wdata;
			wb_hi_we <= mem_hi_we;
			wb_lo_we <= mem_lo_we;
			wb_hi_data <= mem_hi_data;
			wb_lo_data <= mem_lo_data;
			wb_cp0_we <= mem_cp0_we;
			wb_cp0_data <= mem_cp0_data;
		end
	end

	always @(posedge clk) begin
		if (rst) begin
			div_busy <= 1'b0;
			div_done <= 1'b0;
			div_count <= 6'b0;
			div_dividend <= 32'b0;
			div_divisor <= 32'b0;
			div_quotient <= 32'b0;
			div_remainder <= 33'b0;
		end else if (ex_valid & ex_divu_dec & ~div_busy & ~div_done) begin
			if (ex_src2_actual == 32'b0) begin
				div_busy <= 1'b0;
				div_done <= 1'b1;
				div_count <= 6'b0;
				div_dividend <= 32'b0;
				div_divisor <= 32'b0;
				div_quotient <= LO;
				div_remainder <= {1'b0, HI};
			end else begin
				div_busy <= 1'b1;
				div_done <= 1'b0;
				div_count <= 6'd32;
				div_dividend <= ex_src1_actual;
				div_divisor <= ex_src2_actual;
				div_quotient <= 32'b0;
				div_remainder <= 33'b0;
			end
		end else if (div_busy) begin
			div_dividend <= {div_dividend[30:0], 1'b0};
			div_quotient <= {div_quotient[30:0], div_sub_ge};
			div_remainder <= div_sub_ge ? div_sub_result : div_remainder_shift;
			div_count <= div_count - 6'b1;
			if (div_count == 6'd1) begin
				div_busy <= 1'b0;
				div_done <= 1'b1;
			end
		end else if (ex_allowin) begin
			div_done <= 1'b0;
		end
	end

	always @(posedge clk) begin
		if (rst) begin
			HI <= 32'b0;
			LO <= 32'b0;
			cp0_epc <= 32'b0;
			in_exception <= 1'b0;
			intr_sample <= 1'b0;
		end else begin
			if (wb_valid & wb_hi_we)
				HI <= wb_hi_data;
			if (wb_valid & wb_lo_we)
				LO <= wb_lo_data;
			if (wb_valid & wb_cp0_we)
				cp0_epc <= wb_cp0_data;
			if (ex_valid & ex_eret_dec)
				in_exception <= 1'b0;
			if (take_intr) begin
				cp0_epc <= fetch_pc;
				in_exception <= 1'b1;
				intr_sample <= 1'b0;
			end else if (~in_exception & intr) begin
				intr_sample <= 1'b1;
			end
		end
	end

	always @(posedge clk) begin
		if (rst) begin
			for (i = 0; i < BTB_ENTRIES; i = i + 1) begin
				btb_valid[i] <= 1'b0;
				btb_tag[i] <= 26'b0;
				btb_target[i] <= 32'b0;
			end
		end else if (ex_valid & ex_control & ~ex_eret_dec) begin
			if (ex_actual_taken) begin
				btb_valid[ex_pc[5:2]] <= 1'b1;
				btb_tag[ex_pc[5:2]] <= ex_pc[31:6];
				btb_target[ex_pc[5:2]] <= ex_actual_next_pc;
			end else begin
				btb_valid[ex_pc[5:2]] <= 1'b0;
			end
		end
	end

	always @(posedge clk) begin
		if (rst) begin
			cycle_cnt <= 32'b0;
			mem_wait_cycle_cnt <= 32'b0;
			retired_inst_cnt <= 32'b0;
			branch_inst_cnt <= 32'b0;
			branch_miss_cnt <= 32'b0;
			load_inst_cnt <= 32'b0;
			store_inst_cnt <= 32'b0;
		end else begin
			cycle_cnt <= cycle_cnt + 32'b1;
			if ((fetch_busy & ~Inst_Valid) |
			    (mem_valid & mem_load_dec & ~Read_data_Valid) |
			    (mem_valid & mem_store_dec & ~Mem_Req_Ready))
				mem_wait_cycle_cnt <= mem_wait_cycle_cnt + 32'b1;
			if (wb_valid & ~wb_nop_dec)
				retired_inst_cnt <= retired_inst_cnt + 32'b1;
			if (ex_valid & (ex_branch_dec | ex_jump_dec))
				branch_inst_cnt <= branch_inst_cnt + 32'b1;
			if (redirect_valid)
				branch_miss_cnt <= branch_miss_cnt + 32'b1;
			if (wb_valid & wb_load_dec)
				load_inst_cnt <= load_inst_cnt + 32'b1;
			if (wb_valid & wb_store_dec)
				store_inst_cnt <= store_inst_cnt + 32'b1;
		end
	end

endmodule
