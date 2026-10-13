`timescale 1ns/10ps

module tb_add;
	reg clock = 0;
	reg reset = 1;
	integer i;
	reg [31:0] pc_now;
	reg [31:0] instr_now;

	top uut (.clk(clock), .reset(reset));

	always #5 clock = ~clock;

	initial begin
		$dumpfile("dump.vcd");
		$dumpvars(0, uut);
	end

	initial begin
		// ????????????? add?$1=5?$2=3 ??????
		uut.mips_inst.datapath_inst.regfile_inst.regmem[1] = 32'd5;
		uut.mips_inst.datapath_inst.regfile_inst.regmem[2] = 32'd3;

		@(negedge clock);
		reset = 0;

		for (i = 0; i < 4; i = i + 1) begin
			// ????????????????????????
			pc_now    = uut.mips_inst.datapath_inst.pc;
			instr_now = uut.imem_inst.data;
			@(posedge clock);
			#1;
			$display("cycle %0d | exec pc=%0d instr=%h | $1=%0d $2=%0d $3=%0d",
				i, pc_now, instr_now,
				uut.mips_inst.datapath_inst.regfile_inst.regmem[1],
				uut.mips_inst.datapath_inst.regfile_inst.regmem[2],
				uut.mips_inst.datapath_inst.regfile_inst.regmem[3]);
		end

		if (uut.mips_inst.datapath_inst.regfile_inst.regmem[3] === 32'd8)
			$display("PASS: $3 = $1 + $2 = 5 + 3 = 8");
		else
			$display("FAIL: $3 = %0d", uut.mips_inst.datapath_inst.regfile_inst.regmem[3]);
		$finish;
	end
endmodule
