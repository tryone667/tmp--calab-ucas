// ============================================================================
// ALU for LoongArch32R (course subset), exp10/exp11 extension
// one-hot alu_op[17:0]:
//   0 add  1 sub  2 slt  3 sltu  4 and  5 nor  6 or  7 xor
//   8 slli.w  9 srli.w  10 srai.w  11 lu12i.w
//   12 sll.w  13 srl.w  14 sra.w
//   15 mul.w  16 mulh.w  17 mulh.wu
// div/mod are not ALU operations - they run in the divider unit in EX.
// ============================================================================
module alu(
    input  wire [17:0] alu_op,
    input  wire [31:0] alu_src1,
    input  wire [31:0] alu_src2,
    output wire [31:0] alu_result
);
reg  [31:0] result;
wire [63:0] prod_u = {32'b0, alu_src1} * {32'b0, alu_src2};
wire signed [63:0] prod_s =
    $signed({{32{alu_src1[31]}}, alu_src1}) * $signed({{32{alu_src2[31]}}, alu_src2});

always @(*) begin
    case (1'b1)
        alu_op[ 0]: result = alu_src1 + alu_src2;                   // add
        alu_op[ 1]: result = alu_src1 - alu_src2;                   // sub.w
        alu_op[ 2]: result = $signed(alu_src1) < $signed(alu_src2); // slt / slti
        alu_op[ 3]: result = alu_src1 < alu_src2;                   // sltu / sltui
        alu_op[ 4]: result = alu_src1 & alu_src2;                   // and / andi
        alu_op[ 5]: result = ~(alu_src1 | alu_src2);                // nor
        alu_op[ 6]: result = alu_src1 | alu_src2;                   // or / ori
        alu_op[ 7]: result = alu_src1 ^ alu_src2;                   // xor / xori
        alu_op[ 8]: result = alu_src1 <<  alu_src2[4:0];            // slli.w
        alu_op[ 9]: result = alu_src1 >>  alu_src2[4:0];            // srli.w
        alu_op[10]: result = $signed(alu_src1) >>> alu_src2[4:0];   // srai.w
        alu_op[11]: result = alu_src2;                              // lu12i.w
        alu_op[12]: result = alu_src1 <<  alu_src2[4:0];            // sll.w
        alu_op[13]: result = alu_src1 >>  alu_src2[4:0];            // srl.w
        alu_op[14]: result = $signed(alu_src1) >>> alu_src2[4:0];   // sra.w
        alu_op[15]: result = prod_u[31:0];                          // mul.w
        alu_op[16]: result = prod_s[63:32];                         // mulh.w
        alu_op[17]: result = prod_u[63:32];                         // mulh.wu
        default   : result = alu_src1 + alu_src2;
    endcase
end

assign alu_result = result;
endmodule
