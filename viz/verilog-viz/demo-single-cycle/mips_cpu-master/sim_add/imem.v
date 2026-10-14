module imem (
	input  [ 5:0] addr,
	output [31:0] data
);
	reg [31:0] data;
	always @(addr) begin
		case (addr)
			6'd0 : data = 32'h00221820; // add $3, $1, $2   (rs=1, rt=2, rd=3)
			default: data = 32'h00000000; // nop
		endcase
	end
endmodule
