`timescale 10ns / 1ns

`define CACHE_SET 8
`define CACHE_WAY 4
`define TAG_LEN   24
`define LINE_LEN  256

module dcache_top (
	input	      clk,
	input	      rst,

	// CPU interface
	input         from_cpu_mem_req_valid,
	input         from_cpu_mem_req,
	input  [31:0] from_cpu_mem_req_addr,
	input  [31:0] from_cpu_mem_req_wdata,
	input  [ 3:0] from_cpu_mem_req_wstrb,
	output        to_cpu_mem_req_ready,

	output        to_cpu_cache_rsp_valid,
	output [31:0] to_cpu_cache_rsp_data,
	input         from_cpu_cache_rsp_ready,

	// Memory/IO read interface
	output        to_mem_rd_req_valid,
	output [31:0] to_mem_rd_req_addr,
	output [ 7:0] to_mem_rd_req_len,
	input	      from_mem_rd_req_ready,

	input	      from_mem_rd_rsp_valid,
	input  [31:0] from_mem_rd_rsp_data,
	input	      from_mem_rd_rsp_last,
	output        to_mem_rd_rsp_ready,

	// Memory/IO write interface
	output        to_mem_wr_req_valid,
	output [31:0] to_mem_wr_req_addr,
	output [ 7:0] to_mem_wr_req_len,
	input         from_mem_wr_req_ready,

	output        to_mem_wr_data_valid,
	output [31:0] to_mem_wr_data,
	output [ 3:0] to_mem_wr_data_strb,
	output        to_mem_wr_data_last,
	input	      from_mem_wr_data_ready
);

	localparam STATE_WAIT        = 4'd0;
	localparam STATE_LOOKUP      = 4'd1;
	localparam STATE_BYP_RD_REQ  = 4'd2;
	localparam STATE_BYP_RD_RSP  = 4'd3;
	localparam STATE_BYP_WR_REQ  = 4'd4;
	localparam STATE_BYP_WR_DATA = 4'd5;
	localparam STATE_WB_REQ      = 4'd6;
	localparam STATE_WB_DATA     = 4'd7;
	localparam STATE_REFILL_REQ  = 4'd8;
	localparam STATE_REFILL_RECV = 4'd9;
	localparam STATE_REFILL_UPD  = 4'd10;
	localparam STATE_RESP        = 4'd11;
	localparam STATE_DONE        = 4'd12;

	reg [3:0] state;

	reg        req_write;
	reg [31:0] req_addr;
	reg [31:0] req_wdata;
	reg [ 3:0] req_wstrb;
	reg [31:0] rsp_data;

	reg [255:0] refill_line;
	reg [255:0] victim_line_buf;
	reg [31:0]  victim_addr_buf;
	reg [2:0]   burst_count;
	reg [1:0]   victim_way_reg;

	reg [7:0] valid0;
	reg [7:0] valid1;
	reg [7:0] valid2;
	reg [7:0] valid3;
	reg [7:0] dirty0;
	reg [7:0] dirty1;
	reg [7:0] dirty2;
	reg [7:0] dirty3;

	reg [23:0] tag0 [0:7];
	reg [23:0] tag1 [0:7];
	reg [23:0] tag2 [0:7];
	reg [23:0] tag3 [0:7];

	reg [255:0] data0 [0:7];
	reg [255:0] data1 [0:7];
	reg [255:0] data2 [0:7];
	reg [255:0] data3 [0:7];

	reg [1:0] replace_way [0:7];

	wire cpu_req_uncached;
	wire req_uncached;
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
	reg [255:0] victim_line;
	reg [23:0] victim_tag;
	reg victim_valid;
	reg victim_dirty;

	wire [255:0] hit_write_line;
	wire [255:0] refill_final_line;

	integer i;

	assign cpu_req_uncached = (from_cpu_mem_req_addr < 32'h00000020) |
	                          (from_cpu_mem_req_addr[31:30] != 2'b00);
	assign req_uncached = (req_addr < 32'h00000020) |
	                      (req_addr[31:30] != 2'b00);

	assign req_tag   = req_addr[31:8];
	assign req_index = req_addr[7:5];
	assign req_word  = req_addr[4:2];

	assign hit0 = valid0[req_index] & (tag0[req_index] == req_tag);
	assign hit1 = valid1[req_index] & (tag1[req_index] == req_tag);
	assign hit2 = valid2[req_index] & (tag2[req_index] == req_tag);
	assign hit3 = valid3[req_index] & (tag3[req_index] == req_tag);
	assign cache_hit = hit0 | hit1 | hit2 | hit3;

	assign hit_write_line = put_word(hit_line, req_word, req_wdata, req_wstrb);
	assign refill_final_line = req_write ? put_word(refill_line, req_word, req_wdata, req_wstrb) :
	                                      refill_line;

	assign to_cpu_mem_req_ready = (state == STATE_RESP) | (state == STATE_DONE);
	assign to_cpu_cache_rsp_valid = (state == STATE_RESP) & ~req_write;
	assign to_cpu_cache_rsp_data = rsp_data;

	assign to_mem_rd_req_valid = (state == STATE_BYP_RD_REQ) | (state == STATE_REFILL_REQ);
	assign to_mem_rd_req_addr = (state == STATE_BYP_RD_REQ) ? {req_addr[31:2], 2'b0} :
	                                                        {req_addr[31:5], 5'b0};
	assign to_mem_rd_req_len = (state == STATE_BYP_RD_REQ) ? 8'd0 : 8'd7;
	assign to_mem_rd_rsp_ready = (state == STATE_BYP_RD_RSP) | (state == STATE_REFILL_RECV);

	assign to_mem_wr_req_valid = (state == STATE_BYP_WR_REQ) | (state == STATE_WB_REQ);
	assign to_mem_wr_req_addr = (state == STATE_BYP_WR_REQ) ? {req_addr[31:2], 2'b0} :
	                                                        victim_addr_buf;
	assign to_mem_wr_req_len = (state == STATE_BYP_WR_REQ) ? 8'd0 : 8'd7;

	assign to_mem_wr_data_valid = (state == STATE_BYP_WR_DATA) | (state == STATE_WB_DATA);
	assign to_mem_wr_data = (state == STATE_BYP_WR_DATA) ? req_wdata :
	                                                     get_word(victim_line_buf, burst_count);
	assign to_mem_wr_data_strb = (state == STATE_BYP_WR_DATA) ? req_wstrb : 4'b1111;
	assign to_mem_wr_data_last = (state == STATE_BYP_WR_DATA) ? 1'b1 : (burst_count == 3'd7);

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

	function [31:0] merge_word;
		input [31:0] old_word;
		input [31:0] new_word;
		input [3:0] strb;
		begin
			merge_word[7:0]   = strb[0] ? new_word[7:0]   : old_word[7:0];
			merge_word[15:8]  = strb[1] ? new_word[15:8]  : old_word[15:8];
			merge_word[23:16] = strb[2] ? new_word[23:16] : old_word[23:16];
			merge_word[31:24] = strb[3] ? new_word[31:24] : old_word[31:24];
		end
	endfunction

	function [255:0] put_word;
		input [255:0] line;
		input [2:0] word_index;
		input [31:0] wdata;
		input [3:0] wstrb;
		reg [255:0] tmp;
		begin
			tmp = line;
			case (word_index)
				3'd0: tmp[31:0] = merge_word(line[31:0], wdata, wstrb);
				3'd1: tmp[63:32] = merge_word(line[63:32], wdata, wstrb);
				3'd2: tmp[95:64] = merge_word(line[95:64], wdata, wstrb);
				3'd3: tmp[127:96] = merge_word(line[127:96], wdata, wstrb);
				3'd4: tmp[159:128] = merge_word(line[159:128], wdata, wstrb);
				3'd5: tmp[191:160] = merge_word(line[191:160], wdata, wstrb);
				3'd6: tmp[223:192] = merge_word(line[223:192], wdata, wstrb);
				default: tmp[255:224] = merge_word(line[255:224], wdata, wstrb);
			endcase
			put_word = tmp;
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

	always @(*) begin
		case (victim_way)
			2'd0: begin
				victim_line = data0[req_index];
				victim_tag = tag0[req_index];
				victim_valid = valid0[req_index];
				victim_dirty = dirty0[req_index];
			end
			2'd1: begin
				victim_line = data1[req_index];
				victim_tag = tag1[req_index];
				victim_valid = valid1[req_index];
				victim_dirty = dirty1[req_index];
			end
			2'd2: begin
				victim_line = data2[req_index];
				victim_tag = tag2[req_index];
				victim_valid = valid2[req_index];
				victim_dirty = dirty2[req_index];
			end
			default: begin
				victim_line = data3[req_index];
				victim_tag = tag3[req_index];
				victim_valid = valid3[req_index];
				victim_dirty = dirty3[req_index];
			end
		endcase
	end

	always @(posedge clk) begin
		if (rst) begin
			state <= STATE_WAIT;
			req_write <= 1'b0;
			req_addr <= 32'b0;
			req_wdata <= 32'b0;
			req_wstrb <= 4'b0;
			rsp_data <= 32'b0;
			refill_line <= 256'b0;
			victim_line_buf <= 256'b0;
			victim_addr_buf <= 32'b0;
			burst_count <= 3'b0;
			victim_way_reg <= 2'b0;
			valid0 <= 8'b0;
			valid1 <= 8'b0;
			valid2 <= 8'b0;
			valid3 <= 8'b0;
			dirty0 <= 8'b0;
			dirty1 <= 8'b0;
			dirty2 <= 8'b0;
			dirty3 <= 8'b0;
			for (i = 0; i < 8; i = i + 1)
				replace_way[i] <= 2'b0;
		end else begin
			case (state)
				STATE_WAIT: begin
					if (from_cpu_mem_req_valid) begin
						req_write <= from_cpu_mem_req;
						req_addr <= from_cpu_mem_req_addr;
						req_wdata <= from_cpu_mem_req_wdata;
						req_wstrb <= from_cpu_mem_req_wstrb;
						if (cpu_req_uncached)
							state <= from_cpu_mem_req ? STATE_BYP_WR_REQ : STATE_BYP_RD_REQ;
						else
							state <= STATE_LOOKUP;
					end
				end

				STATE_LOOKUP: begin
					if (req_uncached) begin
						state <= req_write ? STATE_BYP_WR_REQ : STATE_BYP_RD_REQ;
					end else if (cache_hit) begin
						if (req_write) begin
							case (hit_way)
								2'd0: begin data0[req_index] <= hit_write_line; dirty0[req_index] <= 1'b1; end
								2'd1: begin data1[req_index] <= hit_write_line; dirty1[req_index] <= 1'b1; end
								2'd2: begin data2[req_index] <= hit_write_line; dirty2[req_index] <= 1'b1; end
								default: begin data3[req_index] <= hit_write_line; dirty3[req_index] <= 1'b1; end
							endcase
							state <= STATE_DONE;
						end else begin
							rsp_data <= get_word(hit_line, req_word);
							state <= STATE_RESP;
						end
					end else begin
						victim_way_reg <= victim_way;
						victim_line_buf <= victim_line;
						victim_addr_buf <= {victim_tag, req_index, 5'b0};
						refill_line <= 256'b0;
						burst_count <= 3'b0;
						if (victim_valid & victim_dirty)
							state <= STATE_WB_REQ;
						else
							state <= STATE_REFILL_REQ;
					end
				end

				STATE_BYP_RD_REQ: begin
					if (from_mem_rd_req_ready)
						state <= STATE_BYP_RD_RSP;
				end

				STATE_BYP_RD_RSP: begin
					if (from_mem_rd_rsp_valid) begin
						rsp_data <= from_mem_rd_rsp_data;
						state <= STATE_RESP;
					end
				end

				STATE_BYP_WR_REQ: begin
					if (from_mem_wr_req_ready)
						state <= STATE_BYP_WR_DATA;
				end

				STATE_BYP_WR_DATA: begin
					if (from_mem_wr_data_ready)
						state <= STATE_DONE;
				end

				STATE_WB_REQ: begin
					if (from_mem_wr_req_ready) begin
						burst_count <= 3'b0;
						state <= STATE_WB_DATA;
					end
				end

				STATE_WB_DATA: begin
					if (from_mem_wr_data_ready) begin
						if (burst_count == 3'd7) begin
							burst_count <= 3'b0;
							state <= STATE_REFILL_REQ;
						end else begin
							burst_count <= burst_count + 3'd1;
						end
					end
				end

				STATE_REFILL_REQ: begin
					if (from_mem_rd_req_ready) begin
						burst_count <= 3'b0;
						state <= STATE_REFILL_RECV;
					end
				end

				STATE_REFILL_RECV: begin
					if (from_mem_rd_rsp_valid) begin
						case (burst_count)
							3'd0: refill_line[31:0] <= from_mem_rd_rsp_data;
							3'd1: refill_line[63:32] <= from_mem_rd_rsp_data;
							3'd2: refill_line[95:64] <= from_mem_rd_rsp_data;
							3'd3: refill_line[127:96] <= from_mem_rd_rsp_data;
							3'd4: refill_line[159:128] <= from_mem_rd_rsp_data;
							3'd5: refill_line[191:160] <= from_mem_rd_rsp_data;
							3'd6: refill_line[223:192] <= from_mem_rd_rsp_data;
							default: refill_line[255:224] <= from_mem_rd_rsp_data;
						endcase
						burst_count <= burst_count + 3'd1;
						if (from_mem_rd_rsp_last)
							state <= STATE_REFILL_UPD;
					end
				end

				STATE_REFILL_UPD: begin
					case (victim_way_reg)
						2'd0: begin
							valid0[req_index] <= 1'b1;
							dirty0[req_index] <= req_write;
							tag0[req_index] <= req_tag;
							data0[req_index] <= refill_final_line;
						end
						2'd1: begin
							valid1[req_index] <= 1'b1;
							dirty1[req_index] <= req_write;
							tag1[req_index] <= req_tag;
							data1[req_index] <= refill_final_line;
						end
						2'd2: begin
							valid2[req_index] <= 1'b1;
							dirty2[req_index] <= req_write;
							tag2[req_index] <= req_tag;
							data2[req_index] <= refill_final_line;
						end
						default: begin
							valid3[req_index] <= 1'b1;
							dirty3[req_index] <= req_write;
							tag3[req_index] <= req_tag;
							data3[req_index] <= refill_final_line;
						end
					endcase
					replace_way[req_index] <= victim_way_reg + 2'd1;
					rsp_data <= get_word(refill_final_line, req_word);
					state <= req_write ? STATE_DONE : STATE_RESP;
				end

				STATE_RESP: begin
					if (req_write | from_cpu_cache_rsp_ready)
						state <= STATE_WAIT;
				end

				STATE_DONE: begin
					state <= STATE_WAIT;
				end

				default: begin
					state <= STATE_WAIT;
				end
			endcase
		end
	end

endmodule

