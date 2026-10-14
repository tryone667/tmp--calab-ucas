`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer: Xu Zhang (zhangxu415@mails.ucas.ac.cn)
//
// Create Date: 06/14/2018 11:39:09 AM
// Design Name:
// Module Name: dma_core
// Project Name:
// Target Devices:
// Tool Versions:
// Description:
//
// Dependencies:
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////


module engine_core #(
	parameter integer  DATA_WIDTH       = 32
)
(
	input    clk,
	input    rst,

	output [31:0]       src_base,
	output [31:0]       dest_base,
	output [31:0]       tail_ptr,
	output [31:0]       head_ptr,
	output [31:0]       dma_size,
	output [31:0]       ctrl_stat,

	input  [31:0]	    reg_wr_data,
	input  [ 5:0]       reg_wr_en,

	output              intr,

	output [31:0]       rd_req_addr,
	output [ 4:0]       rd_req_len,
	output              rd_req_valid,

	input               rd_req_ready,
	input  [31:0]       rd_rdata,
	input               rd_last,
	input               rd_valid,
	output              rd_ready,

	output [31:0]       wr_req_addr,
	output [ 4:0]       wr_req_len,
	output              wr_req_valid,
	input               wr_req_ready,
	output [31:0]       wr_data,
	output              wr_valid,
	input               wr_ready,
	output              wr_last,

	output              fifo_rden,
	output [31:0]       fifo_wdata,
	output              fifo_wen,

	input  [31:0]       fifo_rdata,
	input               fifo_is_empty,
	input               fifo_is_full
);
	localparam STATE_IDLE       = 4'd0;
	localparam STATE_RD_REQ     = 4'd1;
	localparam STATE_RD_DATA    = 4'd2;
	localparam STATE_WR_REQ     = 4'd3;
	localparam STATE_WR_DATA    = 4'd4;

	reg [3:0] state;

	reg [31:0] src_base_reg;
	reg [31:0] dest_base_reg;
	reg [31:0] tail_ptr_reg;
	reg [31:0] head_ptr_reg;
	reg [31:0] dma_size_reg;
	reg        dma_en;
	reg        intr_reg;

	reg [29:0] words_done;
	reg [4:0]  chunk_words;
	reg [4:0]  rd_count;
	reg [4:0]  wr_count;
	reg [31:0] data_buf [0:7];

	wire        dma_busy;
	wire [31:0] ctrl_stat_value;
	wire [29:0] dma_words;
	wire [29:0] words_left;
	wire [29:0] words_done_after;
	wire [29:0] words_left_after;
	wire [4:0]  next_chunk_words;
	wire [31:0] chunk_offset;
	wire        block_done_after_chunk;

	assign dma_busy = (state != STATE_IDLE);
	assign ctrl_stat_value = {intr_reg, 29'b0, dma_busy, dma_en};
	assign dma_words = dma_size_reg[31:2];
	assign words_left = dma_words - words_done;
	assign words_done_after = words_done + {25'b0, chunk_words};
	assign words_left_after = dma_words - words_done_after;
	assign next_chunk_words = (words_left_after > 30'd8) ? 5'd8 : words_left_after[4:0];
	assign chunk_offset = {words_done, 2'b00};
	assign block_done_after_chunk = (words_done_after >= dma_words);

	assign src_base = src_base_reg;
	assign dest_base = dest_base_reg;
	assign tail_ptr = tail_ptr_reg;
	assign head_ptr = head_ptr_reg;
	assign dma_size = dma_size_reg;
	assign ctrl_stat = ctrl_stat_value;
	assign intr = intr_reg;

	assign rd_req_addr = src_base_reg + tail_ptr_reg + chunk_offset;
	assign rd_req_len = chunk_words - 5'd1;
	assign rd_req_valid = (state == STATE_RD_REQ);
	assign rd_ready = (state == STATE_RD_DATA);

	assign wr_req_addr = dest_base_reg + tail_ptr_reg + chunk_offset;
	assign wr_req_len = chunk_words - 5'd1;
	assign wr_req_valid = (state == STATE_WR_REQ);
	assign wr_data = data_buf[wr_count[2:0]];
	assign wr_valid = (state == STATE_WR_DATA);
	assign wr_last = (wr_count == (chunk_words - 5'd1));

	assign fifo_rden = 1'b0;
	assign fifo_wdata = 32'b0;
	assign fifo_wen = 1'b0;

	always @(posedge clk) begin
		if (rst) begin
			state <= STATE_IDLE;
			src_base_reg <= 32'b0;
			dest_base_reg <= 32'b0;
			tail_ptr_reg <= 32'b0;
			head_ptr_reg <= 32'b0;
			dma_size_reg <= 32'b0;
			dma_en <= 1'b0;
			intr_reg <= 1'b0;
			words_done <= 30'b0;
			chunk_words <= 5'b0;
			rd_count <= 5'b0;
			wr_count <= 5'b0;
		end else begin
			if (reg_wr_en[0])
				src_base_reg <= reg_wr_data;
			if (reg_wr_en[1])
				dest_base_reg <= reg_wr_data;
			if (reg_wr_en[2])
				tail_ptr_reg <= reg_wr_data;
			if (reg_wr_en[3])
				head_ptr_reg <= reg_wr_data;
			if (reg_wr_en[4])
				dma_size_reg <= reg_wr_data;
			if (reg_wr_en[5]) begin
				dma_en <= reg_wr_data[0];
				if (!reg_wr_data[31])
					intr_reg <= 1'b0;
			end

			case (state)
				STATE_IDLE: begin
					rd_count <= 5'b0;
					wr_count <= 5'b0;
					if (dma_en & !intr_reg & (tail_ptr_reg != head_ptr_reg) & (dma_words != 30'b0)) begin
						words_done <= 30'b0;
						chunk_words <= (dma_words > 30'd8) ? 5'd8 : dma_words[4:0];
						state <= STATE_RD_REQ;
					end
				end

				STATE_RD_REQ: begin
					if (rd_req_ready) begin
						rd_count <= 5'b0;
						state <= STATE_RD_DATA;
					end
				end

				STATE_RD_DATA: begin
					if (rd_valid) begin
						data_buf[rd_count[2:0]] <= rd_rdata;
						if (rd_last | (rd_count == (chunk_words - 5'd1))) begin
							rd_count <= 5'b0;
							state <= STATE_WR_REQ;
						end else begin
							rd_count <= rd_count + 5'd1;
						end
					end
				end

				STATE_WR_REQ: begin
					if (wr_req_ready) begin
						wr_count <= 5'b0;
						state <= STATE_WR_DATA;
					end
				end

				STATE_WR_DATA: begin
					if (wr_ready) begin
						if (wr_count == (chunk_words - 5'd1)) begin
							if (block_done_after_chunk) begin
								tail_ptr_reg <= tail_ptr_reg + dma_size_reg;
								intr_reg <= 1'b1;
								state <= STATE_IDLE;
							end else begin
								words_done <= words_done_after;
								chunk_words <= next_chunk_words;
								wr_count <= 5'b0;
								state <= STATE_RD_REQ;
							end
						end else begin
							wr_count <= wr_count + 5'd1;
						end
					end
				end

				default: begin
					state <= STATE_IDLE;
				end
			endcase
		end
	end

endmodule
