`timescale 10ns / 1ns

`define CACHE_SET 8
`define CACHE_WAY 4
`define TAG_LEN   24
`define LINE_LEN  256

module icache_top (
	input	      clk,
	input	      rst,

	// CPU interface
	input         from_cpu_inst_req_valid,
	input  [31:0] from_cpu_inst_req_addr,
	output        to_cpu_inst_req_ready,

	output        to_cpu_cache_rsp_valid,
	output [31:0] to_cpu_cache_rsp_data,
	input	      from_cpu_cache_rsp_ready,

	// Memory interface
	output        to_mem_rd_req_valid,
	output [31:0] to_mem_rd_req_addr,
	input         from_mem_rd_req_ready,

	input         from_mem_rd_rsp_valid,
	input  [31:0] from_mem_rd_rsp_data,
	input         from_mem_rd_rsp_last,
	output        to_mem_rd_rsp_ready
);

	localparam STATE_WAIT   = 3'd0;
	localparam STATE_TAG_RD = 3'd1;
	localparam STATE_MEM_RD = 3'd2;
	localparam STATE_RECV   = 3'd3;
	localparam STATE_REFILL = 3'd4;
	localparam STATE_RESP   = 3'd5;

	reg [2:0] state;

	reg [31:0] req_addr;
	reg [31:0] rsp_data;
	reg [255:0] refill_line;
	reg [2:0] refill_count;
	reg [1:0] refill_way;

	reg [7:0] valid0;
	reg [7:0] valid1;
	reg [7:0] valid2;
	reg [7:0] valid3;

	reg [23:0] tag0 [0:7];
	reg [23:0] tag1 [0:7];
	reg [23:0] tag2 [0:7];
	reg [23:0] tag3 [0:7];

	reg [255:0] data0 [0:7];
	reg [255:0] data1 [0:7];
	reg [255:0] data2 [0:7];
	reg [255:0] data3 [0:7];

	reg [1:0] replace_way [0:7];

	wire [23:0] req_tag;
	wire [2:0] req_index;
	wire [2:0] req_word;

	wire hit0;
	wire hit1;
	wire hit2;
	wire hit3;
	wire cache_hit;

	reg [1:0] hit_way;
	reg [1:0] victim_way;
	reg [255:0] hit_line;

	integer i;

	assign req_tag   = req_addr[31:8];
	assign req_index = req_addr[7:5];
	assign req_word  = req_addr[4:2];

	assign hit0 = valid0[req_index] & (tag0[req_index] == req_tag);
	assign hit1 = valid1[req_index] & (tag1[req_index] == req_tag);
	assign hit2 = valid2[req_index] & (tag2[req_index] == req_tag);
	assign hit3 = valid3[req_index] & (tag3[req_index] == req_tag);
	assign cache_hit = hit0 | hit1 | hit2 | hit3;

	assign to_cpu_inst_req_ready = (state == STATE_WAIT);
	assign to_cpu_cache_rsp_valid = (state == STATE_RESP);
	assign to_cpu_cache_rsp_data = rsp_data;

	assign to_mem_rd_req_valid = (state == STATE_MEM_RD);
	assign to_mem_rd_req_addr = {req_addr[31:5], 5'b0};
	assign to_mem_rd_rsp_ready = (state == STATE_RECV);

	function [31:0] get_word;
		input [255:0] line;
		input [2:0] word_index;
		begin
			case (word_index)
				3'd0: get_word = line[31:0];
				3'd1: get_word = line[63:32];
				3'd2: get_word = line[95:64];
				3'd3: get_word = line[127:96];
				3'd4: get_word = line[159:128];
				3'd5: get_word = line[191:160];
				3'd6: get_word = line[223:192];
				default: get_word = line[255:224];
			endcase
		end
	endfunction

	always @(*) begin
		if (hit0)
			hit_way = 2'd0;
		else if (hit1)
			hit_way = 2'd1;
		else if (hit2)
			hit_way = 2'd2;
		else
			hit_way = 2'd3;
	end

	always @(*) begin
		case (hit_way)
			2'd0: hit_line = data0[req_index];
			2'd1: hit_line = data1[req_index];
			2'd2: hit_line = data2[req_index];
			default: hit_line = data3[req_index];
		endcase
	end

	always @(*) begin
		if (!valid0[req_index])
			victim_way = 2'd0;
		else if (!valid1[req_index])
			victim_way = 2'd1;
		else if (!valid2[req_index])
			victim_way = 2'd2;
		else if (!valid3[req_index])
			victim_way = 2'd3;
		else
			victim_way = replace_way[req_index];
	end

	always @(posedge clk) begin
		if (rst) begin
			state <= STATE_WAIT;
			req_addr <= 32'b0;
			rsp_data <= 32'b0;
			refill_line <= 256'b0;
			refill_count <= 3'b0;
			refill_way <= 2'b0;
			valid0 <= 8'b0;
			valid1 <= 8'b0;
			valid2 <= 8'b0;
			valid3 <= 8'b0;
			for (i = 0; i < 8; i = i + 1)
				replace_way[i] <= 2'b0;
		end else begin
			case (state)
				STATE_WAIT: begin
					if (from_cpu_inst_req_valid) begin
						req_addr <= from_cpu_inst_req_addr;
						state <= STATE_TAG_RD;
					end
				end

				STATE_TAG_RD: begin
					if (cache_hit) begin
						rsp_data <= get_word(hit_line, req_word);
						state <= STATE_RESP;
					end else begin
						refill_way <= victim_way;
						refill_line <= 256'b0;
						refill_count <= 3'b0;
						state <= STATE_MEM_RD;
					end
				end

				STATE_MEM_RD: begin
					if (from_mem_rd_req_ready)
						state <= STATE_RECV;
				end

				STATE_RECV: begin
					if (from_mem_rd_rsp_valid) begin
						case (refill_count)
							3'd0: refill_line[31:0] <= from_mem_rd_rsp_data;
							3'd1: refill_line[63:32] <= from_mem_rd_rsp_data;
							3'd2: refill_line[95:64] <= from_mem_rd_rsp_data;
							3'd3: refill_line[127:96] <= from_mem_rd_rsp_data;
							3'd4: refill_line[159:128] <= from_mem_rd_rsp_data;
							3'd5: refill_line[191:160] <= from_mem_rd_rsp_data;
							3'd6: refill_line[223:192] <= from_mem_rd_rsp_data;
							default: refill_line[255:224] <= from_mem_rd_rsp_data;
						endcase
						refill_count <= refill_count + 3'd1;
						if (from_mem_rd_rsp_last)
							state <= STATE_REFILL;
					end
				end

				STATE_REFILL: begin
					case (refill_way)
						2'd0: begin
							valid0[req_index] <= 1'b1;
							tag0[req_index] <= req_tag;
							data0[req_index] <= refill_line;
						end
						2'd1: begin
							valid1[req_index] <= 1'b1;
							tag1[req_index] <= req_tag;
							data1[req_index] <= refill_line;
						end
						2'd2: begin
							valid2[req_index] <= 1'b1;
							tag2[req_index] <= req_tag;
							data2[req_index] <= refill_line;
						end
						default: begin
							valid3[req_index] <= 1'b1;
							tag3[req_index] <= req_tag;
							data3[req_index] <= refill_line;
						end
					endcase
					replace_way[req_index] <= refill_way + 2'd1;
					rsp_data <= get_word(refill_line, req_word);
					state <= STATE_RESP;
				end

				STATE_RESP: begin
					if (from_cpu_cache_rsp_ready)
						state <= STATE_WAIT;
				end

				default: begin
					state <= STATE_WAIT;
				end
			endcase
		end
	end

endmodule

