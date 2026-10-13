`timescale 10ns / 1ns

module custom_cpu_golden(
	input         clk,
	input         rst,

	//Instruction request channel
	output [31:0] PC,
	output        Inst_Req_Valid,
	input         Inst_Req_Ready,

	//Instruction response channel
	input  [31:0] Instruction,
	input         Inst_Valid,
	output        Inst_Ready,

	//Memory request channel
	output [31:0] Address,
	output        MemWrite,
	output [31:0] Write_data,
	output [ 3:0] Write_strb,
	output        MemRead,
	input         Mem_Req_Ready,

	//Memory data response channel
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

/* The following signal is leveraged for behavioral simulation,
 * which is delivered to testbench.
 *
 * inst_retire (70-bit): detailed information of the retired instruction,
 * mainly including (in order)
 * {
 *   reg_file write-back enable  (69:69,  1-bit),
 *   reg_file write-back address (68:64,  5-bit),
 *   reg_file write-back data    (63:32, 32-bit),
 *   retired PC                  (31: 0, 32-bit)
 * }
 */

	localparam STATE_INIT = 9'b000000001;
	localparam STATE_WB   = 9'b000000010;
	localparam STATE_RDW  = 9'b000000100;
	localparam STATE_LD   = 9'b000001000;
	localparam STATE_ST   = 9'b000010000;
	localparam STATE_EX   = 9'b000100000;
	localparam STATE_ID   = 9'b001000000;
	localparam STATE_IW   = 9'b010000000;
	localparam STATE_IF   = 9'b100000000;

	reg  [8:0]  current_state;
	reg  [8:0]  next_state;
	wire        Mem_Req_Ack;

	reg  [31:0] pc;
	reg  [31:0] IR;
	reg  [31:0] data1;
	reg  [31:0] data2;
	reg  [31:0] ALUout;
	reg  [31:0] wb_data;
	reg  [31:0] retired_pc;
	reg  [ 4:0] wb_addr;
	reg         wb_en;
	reg  [31:0] HI;
	reg  [31:0] LO;

	reg  [31:0] cycle_cnt;
	reg  [31:0] mem_wait_cycle_cnt;
	reg  [31:0] rtype_inst_cnt;
	reg  [31:0] itype_inst_cnt;
	reg  [31:0] mem_write_inst_cnt;
	reg  [31:0] mem_read_inst_cnt;
	reg  [31:0] jump_branch_inst_cnt;
	reg  [31:0] retired_inst_cnt;

	wire [ 5:0] opcode;
	wire [ 4:0] rs;
	wire [ 4:0] rt;
	wire [ 4:0] rd;
	wire [ 4:0] shamt;
	wire [ 5:0] func;
	wire [15:0] imm;
	wire [25:0] target;
	wire [31:0] sign_ext_imm;
	wire [31:0] zero_ext_imm;
	wire [31:0] pc_plus4;
	wire [31:0] pc_plus8;

	assign opcode       = IR[31:26];
	assign rs           = IR[25:21];
	assign rt           = IR[20:16];
	assign rd           = IR[15:11];
	assign shamt        = IR[10: 6];
	assign func         = IR[ 5: 0];
	assign imm          = IR[15: 0];
	assign target       = IR[25: 0];
	assign sign_ext_imm = {{16{imm[15]}}, imm};
	assign zero_ext_imm = {16'b0, imm};
	assign pc_plus4     = pc + 32'd4;
	assign pc_plus8     = pc + 32'd8;

	wire op_special;
	wire op_regimm;
	wire op_special2;
	wire inst_nop;

	assign op_special  = (opcode == 6'b000000);
	assign op_regimm   = (opcode == 6'b000001);
	assign op_special2 = (opcode == 6'b011100);
	assign inst_nop    = (IR == 32'b0);

	wire inst_sll;
	wire inst_srl;
	wire inst_sra;
	wire inst_sllv;
	wire inst_srlv;
	wire inst_srav;
	wire inst_shift;

	assign inst_sll   = op_special & (func == 6'h00);
	assign inst_srl   = op_special & (func == 6'h02);
	assign inst_sra   = op_special & (func == 6'h03);
	assign inst_sllv  = op_special & (func == 6'h04);
	assign inst_srlv  = op_special & (func == 6'h06);
	assign inst_srav  = op_special & (func == 6'h07);
	assign inst_shift = inst_sll | inst_srl | inst_sra | inst_sllv | inst_srlv | inst_srav;

	wire inst_jr;
	wire inst_jalr;
	wire inst_movz;
	wire inst_movn;
	wire inst_mfhi;
	wire inst_mthi;
	wire inst_mflo;
	wire inst_mtlo;
	wire inst_mult;
	wire inst_multu;
	wire inst_divu;
	wire inst_mul;

	assign inst_jr    = op_special  & (func == 6'h08);
	assign inst_jalr  = op_special  & (func == 6'h09);
	assign inst_movz  = op_special  & (func == 6'h0a);
	assign inst_movn  = op_special  & (func == 6'h0b);
	assign inst_mfhi  = op_special  & (func == 6'h10);
	assign inst_mthi  = op_special  & (func == 6'h11);
	assign inst_mflo  = op_special  & (func == 6'h12);
	assign inst_mtlo  = op_special  & (func == 6'h13);
	assign inst_mult  = op_special  & (func == 6'h18);
	assign inst_multu = op_special  & (func == 6'h19);
	assign inst_divu  = op_special  & (func == 6'h1b);
	assign inst_mul   = op_special2 & (func == 6'h02);

	wire inst_addu;
	wire inst_subu;
	wire inst_and;
	wire inst_or;
	wire inst_xor;
	wire inst_nor;
	wire inst_slt;
	wire inst_sltu;
	wire inst_r_alu;

	assign inst_addu  = op_special & ((func == 6'h20) | (func == 6'h21));
	assign inst_subu  = op_special & ((func == 6'h22) | (func == 6'h23));
	assign inst_and   = op_special & (func == 6'h24);
	assign inst_or    = op_special & (func == 6'h25);
	assign inst_xor   = op_special & (func == 6'h26);
	assign inst_nor   = op_special & (func == 6'h27);
	assign inst_slt   = op_special & (func == 6'h2a);
	assign inst_sltu  = op_special & (func == 6'h2b);
	assign inst_r_alu = inst_addu | inst_subu | inst_and | inst_or |
	                    inst_xor | inst_nor | inst_slt | inst_sltu;

	wire inst_addiu;
	wire inst_slti;
	wire inst_sltiu;
	wire inst_andi;
	wire inst_ori;
	wire inst_xori;
	wire inst_lui;
	wire inst_i_alu;

	assign inst_addiu = (opcode == 6'h08) | (opcode == 6'h09);
	assign inst_slti  = (opcode == 6'h0a);
	assign inst_sltiu = (opcode == 6'h0b);
	assign inst_andi  = (opcode == 6'h0c);
	assign inst_ori   = (opcode == 6'h0d);
	assign inst_xori  = (opcode == 6'h0e);
	assign inst_lui   = (opcode == 6'h0f);
	assign inst_i_alu = inst_addiu | inst_slti | inst_sltiu |
	                    inst_andi | inst_ori | inst_xori;

	wire inst_lb;
	wire inst_lh;
	wire inst_lwl;
	wire inst_lw;
	wire inst_lbu;
	wire inst_lhu;
	wire inst_lwr;
	wire inst_sb;
	wire inst_sh;
	wire inst_swl;
	wire inst_sw;
	wire inst_swr;
	wire inst_load;
	wire inst_store;

	assign inst_lb    = (opcode == 6'h20);
	assign inst_lh    = (opcode == 6'h21);
	assign inst_lwl   = (opcode == 6'h22);
	assign inst_lw    = (opcode == 6'h23);
	assign inst_lbu   = (opcode == 6'h24);
	assign inst_lhu   = (opcode == 6'h25);
	assign inst_lwr   = (opcode == 6'h26);
	assign inst_sb    = (opcode == 6'h28);
	assign inst_sh    = (opcode == 6'h29);
	assign inst_swl   = (opcode == 6'h2a);
	assign inst_sw    = (opcode == 6'h2b);
	assign inst_swr   = (opcode == 6'h2e);
	assign inst_load  = inst_lb | inst_lh | inst_lwl | inst_lw |
	                    inst_lbu | inst_lhu | inst_lwr;
	assign inst_store = inst_sb | inst_sh | inst_swl | inst_sw | inst_swr;

	wire inst_beq;
	wire inst_bne;
	wire inst_blez;
	wire inst_bgtz;
	wire inst_bltz;
	wire inst_bgez;
	wire inst_bltzal;
	wire inst_bgezal;
	wire inst_j;
	wire inst_jal;
	wire inst_branch;
	wire inst_regimm_link;
	wire inst_jump;

	assign inst_beq        = (opcode == 6'h04);
	assign inst_bne        = (opcode == 6'h05);
	assign inst_blez       = (opcode == 6'h06);
	assign inst_bgtz       = (opcode == 6'h07);
	assign inst_bltz       = op_regimm & (rt == 5'h00);
	assign inst_bgez       = op_regimm & (rt == 5'h01);
	assign inst_bltzal     = op_regimm & (rt == 5'h10);
	assign inst_bgezal     = op_regimm & (rt == 5'h11);
	assign inst_j          = (opcode == 6'h02);
	assign inst_jal        = (opcode == 6'h03);
	assign inst_branch     = inst_beq | inst_bne | inst_blez | inst_bgtz |
	                         inst_bltz | inst_bgez | inst_bltzal | inst_bgezal;
	assign inst_regimm_link = inst_bltzal | inst_bgezal;
	assign inst_jump       = inst_j | inst_jal | inst_jr | inst_jalr;

	wire [4:0] RF_raddr1;
	wire [4:0] RF_raddr2;
	wire [4:0] RF_waddr;
	wire       RF_wen;
	wire [31:0] RF_wdata;
	wire [31:0] RF_rdata1;
	wire [31:0] RF_rdata2;

	assign RF_raddr1 = rs;
	assign RF_raddr2 = rt;
	assign RF_waddr  = wb_addr;
	assign RF_wdata  = wb_data;
	assign RF_wen    = current_state[1] & wb_en;

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

	wire [2:0]  ALUop;
	wire [31:0] alu_A;
	wire [31:0] alu_B;
	wire [31:0] alu_result;
	wire        alu_zero;
	wire        alu_overflow;
	wire        alu_carryout;

	assign ALUop = (inst_and  | inst_andi)  ? 3'b000 :
	               (inst_or   | inst_ori)   ? 3'b001 :
	               (inst_xor  | inst_xori)  ? 3'b100 :
	               (inst_nor)               ? 3'b101 :
	               (inst_subu | inst_beq | inst_bne) ? 3'b110 :
	               (inst_slt  | inst_slti)  ? 3'b111 :
	               (inst_sltu | inst_sltiu) ? 3'b011 :
	               3'b010;

	assign alu_A = data1;
	assign alu_B = (inst_r_alu | inst_beq | inst_bne) ? data2 :
	               (inst_andi | inst_ori | inst_xori) ? zero_ext_imm :
	               sign_ext_imm;

	alu u_alu (
		.A        (alu_A),
		.B        (alu_B),
		.ALUop    (ALUop),
		.Overflow (alu_overflow),
		.CarryOut (alu_carryout),
		.Zero     (alu_zero),
		.Result   (alu_result)
	);

	wire [1:0]  Shiftop;
	wire [4:0]  shift_amount;
	wire [31:0] shift_result;

	assign Shiftop      = (inst_sll | inst_sllv) ? 2'b00 :
	                      (inst_srl | inst_srlv) ? 2'b10 :
	                      2'b11;
	assign shift_amount = (inst_sllv | inst_srlv | inst_srav) ? data1[4:0] : shamt;

	shifter u_shifter (
		.A       (data2),
		.B       (shift_amount),
		.Shiftop (Shiftop),
		.Result  (shift_result)
	);

	wire move_cond;
	wire branch_taken;
	wire [31:0] branch_target;
	wire [31:0] jump_target;
	wire [31:0] next_pc_value;

	assign move_cond = (inst_movz & (data2 == 32'b0)) |
	                   (inst_movn & (data2 != 32'b0));

	assign branch_taken = (inst_beq    & (data1 == data2)) |
	                      (inst_bne    & (data1 != data2)) |
	                      (inst_blez   & (data1[31] | (data1 == 32'b0))) |
	                      (inst_bgtz   & (~data1[31] & (data1 != 32'b0))) |
	                      (inst_bltz   & data1[31]) |
	                      (inst_bgez   & ~data1[31]) |
	                      (inst_bltzal & data1[31]) |
	                      (inst_bgezal & ~data1[31]);

	assign branch_target = pc_plus4 + {sign_ext_imm[29:0], 2'b00};
	assign jump_target   = {pc_plus4[31:28], target, 2'b00};
	assign next_pc_value = (inst_jr | inst_jalr) ? data1 :
	                       (inst_j | inst_jal)   ? jump_target :
	                       (inst_branch & branch_taken) ? branch_target :
	                       pc_plus4;

	wire ex_wb_en;
	wire ex_has_wb_stage;
	wire [4:0] ex_wb_addr;
	wire signed [31:0] signed_data1;
	wire signed [31:0] signed_data2;
	wire [31:0] unsigned_data1;
	wire [31:0] unsigned_data2;
	wire signed [63:0] mult_signed_full;
	wire [63:0] mult_unsigned_full;
	wire [31:0] mult_lo;
	wire [31:0] mult_hi;
	wire [31:0] multu_lo;
	wire [31:0] multu_hi;
	wire [31:0] divu_lo;
	wire [31:0] divu_hi;
	wire [31:0] ex_wb_data;

	assign ex_wb_en = inst_load | inst_r_alu | inst_shift | inst_i_alu | inst_lui |
	                  inst_jal | inst_jalr | (inst_regimm_link & branch_taken) |
	                  (move_cond & (inst_movz | inst_movn)) |
	                  inst_mfhi | inst_mflo | inst_mul;

	assign ex_has_wb_stage = (op_special & ~inst_nop) | inst_i_alu |
	                         inst_lui | inst_jal | inst_mul |
	                         (inst_regimm_link & branch_taken);

	assign ex_wb_addr = inst_jal ? 5'd31 :
	                    inst_jalr ? rd :
	                    (inst_load | inst_i_alu | inst_lui) ? rt :
	                    (inst_regimm_link ? 5'd31 : rd);

	assign signed_data1        = data1;
	assign signed_data2        = data2;
	assign unsigned_data1      = data1;
	assign unsigned_data2      = data2;
	assign mult_signed_full    = signed_data1 * signed_data2;
	assign mult_unsigned_full  = unsigned_data1 * unsigned_data2;
	assign mult_lo  = mult_signed_full[31:0];
	assign mult_hi  = mult_signed_full[63:32];
	assign multu_lo = mult_unsigned_full[31:0];
	assign multu_hi = mult_unsigned_full[63:32];
	assign divu_lo  = (data2 == 32'b0) ? LO : (data1 / data2);
	assign divu_hi  = (data2 == 32'b0) ? HI : (data1 % data2);

	assign ex_wb_data = inst_lui ? {imm, 16'b0} :
	                    (inst_jal | inst_jalr | inst_regimm_link) ? pc_plus8 :
	                    (inst_shift ? shift_result :
	                    ((inst_movz | inst_movn) ? data1 :
	                    (inst_mfhi ? HI :
	                    (inst_mflo ? LO :
	                    (inst_mul ? mult_lo : alu_result)))));

	wire [1:0] byte_offset;
	wire addr_0;
	wire addr_1;
	wire addr_2;
	wire addr_3;
	wire [31:0] byte_load_data;
	wire [31:0] half_load_data;
	wire [31:0] lwl_load_data;
	wire [31:0] lwr_load_data;
	wire [31:0] load_data;

	assign byte_offset = ALUout[1:0];
	assign addr_0 = (byte_offset == 2'b00);
	assign addr_1 = (byte_offset == 2'b01);
	assign addr_2 = (byte_offset == 2'b10);
	assign addr_3 = (byte_offset == 2'b11);

	assign byte_load_data =
		({32{addr_0}} & {{24{Read_data[ 7] & inst_lb}}, Read_data[ 7: 0]}) |
		({32{addr_1}} & {{24{Read_data[15] & inst_lb}}, Read_data[15: 8]}) |
		({32{addr_2}} & {{24{Read_data[23] & inst_lb}}, Read_data[23:16]}) |
		({32{addr_3}} & {{24{Read_data[31] & inst_lb}}, Read_data[31:24]});

	assign half_load_data =
		({32{addr_0}} & {{16{Read_data[15] & inst_lh}}, Read_data[15: 0]}) |
		({32{addr_2}} & {{16{Read_data[31] & inst_lh}}, Read_data[31:16]});

	assign lwl_load_data =
		({32{addr_0}} & {Read_data[ 7:0], data2[23:0]}) |
		({32{addr_1}} & {Read_data[15:0], data2[15:0]}) |
		({32{addr_2}} & {Read_data[23:0], data2[ 7:0]}) |
		({32{addr_3}} & Read_data);

	assign lwr_load_data =
		({32{addr_0}} & Read_data) |
		({32{addr_1}} & {data2[31:24], Read_data[31: 8]}) |
		({32{addr_2}} & {data2[31:16], Read_data[31:16]}) |
		({32{addr_3}} & {data2[31: 8], Read_data[31:24]});

	assign load_data = (inst_lb | inst_lbu) ? byte_load_data :
	                   (inst_lh | inst_lhu) ? half_load_data :
	                   inst_lwl ? lwl_load_data :
	                   inst_lwr ? lwr_load_data :
	                   Read_data;

	wire [3:0] sb_strb;
	wire [3:0] sh_strb;
	wire [3:0] swl_strb;
	wire [3:0] swr_strb;
	wire [31:0] sb_wdata;
	wire [31:0] sh_wdata;
	wire [31:0] swl_wdata;
	wire [31:0] swr_wdata;

	assign sb_strb = addr_0 ? 4'b0001 :
	                 addr_1 ? 4'b0010 :
	                 addr_2 ? 4'b0100 : 4'b1000;
	assign sh_strb = addr_0 ? 4'b0011 :
	                 addr_2 ? 4'b1100 : 4'b0000;
	assign swl_strb = addr_0 ? 4'b0001 :
	                  addr_1 ? 4'b0011 :
	                  addr_2 ? 4'b0111 : 4'b1111;
	assign swr_strb = addr_0 ? 4'b1111 :
	                  addr_1 ? 4'b1110 :
	                  addr_2 ? 4'b1100 : 4'b1000;

	assign sb_wdata =
		({32{addr_0}} & {24'b0, data2[7:0]}) |
		({32{addr_1}} & {16'b0, data2[7:0], 8'b0}) |
		({32{addr_2}} & {8'b0, data2[7:0], 16'b0}) |
		({32{addr_3}} & {data2[7:0], 24'b0});

	assign sh_wdata =
		({32{addr_0}} & {16'b0, data2[15:0]}) |
		({32{addr_2}} & {data2[15:0], 16'b0});

	assign swl_wdata =
		({32{addr_0}} & {24'b0, data2[31:24]}) |
		({32{addr_1}} & {16'b0, data2[31:16]}) |
		({32{addr_2}} & {8'b0, data2[31:8]}) |
		({32{addr_3}} & data2);

	assign swr_wdata =
		({32{addr_0}} & data2) |
		({32{addr_1}} & {data2[23:0], 8'b0}) |
		({32{addr_2}} & {data2[15:0], 16'b0}) |
		({32{addr_3}} & {data2[7:0], 24'b0});

	assign Write_strb = inst_sb  ? sb_strb :
	                    inst_sh  ? sh_strb :
	                    inst_sw  ? 4'b1111 :
	                    inst_swl ? swl_strb :
	                    inst_swr ? swr_strb :
	                    4'b0000;

	assign Write_data = inst_sb  ? sb_wdata :
	                    inst_sh  ? sh_wdata :
	                    inst_sw  ? data2 :
	                    inst_swl ? swl_wdata :
	                    inst_swr ? swr_wdata :
	                    32'b0;

	assign PC              = pc;
	assign Address         = {ALUout[31:2], 2'b00};
	assign Inst_Req_Valid  = current_state[8];
	assign Inst_Ready      = current_state[7] | current_state[0];
	assign MemRead         = current_state[3];
	assign MemWrite        = current_state[4];
	assign Read_data_Ready = current_state[2] | current_state[0];

	// The provided testbench probes this historical internal name.
	assign Mem_Req_Ack = Mem_Req_Ready;

	assign inst_retire = {RF_wen, RF_waddr, RF_wdata, retired_pc};

	assign cpu_perf_cnt_0  = cycle_cnt;
	assign cpu_perf_cnt_1  = mem_wait_cycle_cnt;
	assign cpu_perf_cnt_2  = rtype_inst_cnt;
	assign cpu_perf_cnt_3  = itype_inst_cnt;
	assign cpu_perf_cnt_4  = mem_write_inst_cnt;
	assign cpu_perf_cnt_5  = mem_read_inst_cnt;
	assign cpu_perf_cnt_6  = jump_branch_inst_cnt;
	assign cpu_perf_cnt_7  = 32'b0;
	assign cpu_perf_cnt_8  = retired_inst_cnt;
	assign cpu_perf_cnt_9  = 32'b0;
	assign cpu_perf_cnt_10 = 32'b0;
	assign cpu_perf_cnt_11 = 32'b0;
	assign cpu_perf_cnt_12 = 32'b0;
	assign cpu_perf_cnt_13 = 32'b0;
	assign cpu_perf_cnt_14 = 32'b0;
	assign cpu_perf_cnt_15 = 32'b0;

	always @(posedge clk) begin
		if (rst) begin
			current_state <= STATE_INIT;
		end else begin
			current_state <= next_state;
		end
	end

	always @(*) begin
		case (current_state)
			STATE_INIT: begin
				next_state = STATE_IF;
			end
			STATE_IF: begin
				if (Inst_Req_Ready)
					next_state = STATE_IW;
				else
					next_state = STATE_IF;
			end
			STATE_IW: begin
				if (Inst_Valid)
					next_state = STATE_ID;
				else
					next_state = STATE_IW;
			end
			STATE_ID: begin
				if (inst_nop)
					next_state = STATE_IF;
				else
					next_state = STATE_EX;
			end
			STATE_EX: begin
				if (inst_load)
					next_state = STATE_LD;
				else if (inst_store)
					next_state = STATE_ST;
				else if (ex_has_wb_stage)
					next_state = STATE_WB;
				else
					next_state = STATE_IF;
			end
			STATE_LD: begin
				if (Mem_Req_Ready)
					next_state = STATE_RDW;
				else
					next_state = STATE_LD;
			end
			STATE_RDW: begin
				if (Read_data_Valid)
					next_state = STATE_WB;
				else
					next_state = STATE_RDW;
			end
			STATE_ST: begin
				if (Mem_Req_Ready)
					next_state = STATE_IF;
				else
					next_state = STATE_ST;
			end
			STATE_WB: begin
				next_state = STATE_IF;
			end
			default: begin
				next_state = STATE_INIT;
			end
		endcase
	end

	always @(posedge clk) begin
		if (rst)
			pc <= 32'b0;
		else if (current_state[6] & inst_nop)
			pc <= pc_plus4;
		else if (current_state[5])
			pc <= next_pc_value;
	end

	always @(posedge clk) begin
		if (rst)
			IR <= 32'b0;
		else if (current_state[7] & Inst_Valid)
			IR <= Instruction;
	end

	always @(posedge clk) begin
		if (rst)
			data1 <= 32'b0;
		else if (current_state[6])
			data1 <= RF_rdata1;
	end

	always @(posedge clk) begin
		if (rst)
			data2 <= 32'b0;
		else if (current_state[6])
			data2 <= RF_rdata2;
	end

	always @(posedge clk) begin
		if (rst)
			ALUout <= 32'b0;
		else if (current_state[5])
			ALUout <= alu_result;
	end

	always @(posedge clk) begin
		if (rst)
			wb_data <= 32'b0;
		else if (current_state[5])
			wb_data <= ex_wb_data;
		else if (current_state[2] & Read_data_Valid)
			wb_data <= load_data;
	end

	always @(posedge clk) begin
		if (rst)
			wb_addr <= 5'b0;
		else if (current_state[5])
			wb_addr <= ex_wb_addr;
	end

	always @(posedge clk) begin
		if (rst)
			wb_en <= 1'b0;
		else if (current_state[5])
			wb_en <= ex_wb_en;
	end

	always @(posedge clk) begin
		if (rst)
			retired_pc <= 32'b0;
		else if (current_state[5])
			retired_pc <= pc;
	end

	always @(posedge clk) begin
		if (rst)
			HI <= 32'b0;
		else if (current_state[5] & inst_mult)
			HI <= mult_hi;
		else if (current_state[5] & inst_multu)
			HI <= multu_hi;
		else if (current_state[5] & inst_divu)
			HI <= divu_hi;
		else if (current_state[5] & inst_mthi)
			HI <= data1;
	end

	always @(posedge clk) begin
		if (rst)
			LO <= 32'b0;
		else if (current_state[5] & inst_mult)
			LO <= mult_lo;
		else if (current_state[5] & inst_multu)
			LO <= multu_lo;
		else if (current_state[5] & inst_divu)
			LO <= divu_lo;
		else if (current_state[5] & inst_mtlo)
			LO <= data1;
	end

	always @(posedge clk) begin
		if (rst)
			cycle_cnt <= 32'b0;
		else
			cycle_cnt <= cycle_cnt + 32'b1;
	end

	always @(posedge clk) begin
		if (rst)
			mem_wait_cycle_cnt <= 32'b0;
		else if ((current_state[8] & ~Inst_Req_Ready) |
		         (current_state[7] & ~Inst_Valid) |
		         (current_state[3] & ~Mem_Req_Ready) |
		         (current_state[2] & ~Read_data_Valid) |
		         (current_state[4] & ~Mem_Req_Ready))
			mem_wait_cycle_cnt <= mem_wait_cycle_cnt + 32'b1;
	end

	always @(posedge clk) begin
		if (rst)
			rtype_inst_cnt <= 32'b0;
		else if (current_state[5] & (inst_r_alu | inst_shift | inst_movz | inst_movn |
		                             inst_mfhi | inst_mflo | inst_mthi | inst_mtlo |
		                             inst_mult | inst_multu | inst_divu | inst_mul))
			rtype_inst_cnt <= rtype_inst_cnt + 32'b1;
	end

	always @(posedge clk) begin
		if (rst)
			itype_inst_cnt <= 32'b0;
		else if (current_state[5] & (inst_i_alu | inst_lui))
			itype_inst_cnt <= itype_inst_cnt + 32'b1;
	end

	always @(posedge clk) begin
		if (rst)
			mem_write_inst_cnt <= 32'b0;
		else if (current_state[5] & inst_store)
			mem_write_inst_cnt <= mem_write_inst_cnt + 32'b1;
	end

	always @(posedge clk) begin
		if (rst)
			mem_read_inst_cnt <= 32'b0;
		else if (current_state[5] & inst_load)
			mem_read_inst_cnt <= mem_read_inst_cnt + 32'b1;
	end

	always @(posedge clk) begin
		if (rst)
			jump_branch_inst_cnt <= 32'b0;
		else if (current_state[5] & (inst_branch | inst_jump))
			jump_branch_inst_cnt <= jump_branch_inst_cnt + 32'b1;
	end

	always @(posedge clk) begin
		if (rst)
			retired_inst_cnt <= 32'b0;
		else if (current_state[6] & ~inst_nop)
			retired_inst_cnt <= retired_inst_cnt + 32'b1;
	end

endmodule
