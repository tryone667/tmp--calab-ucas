module clk_pll (
    input  wire clk_in1,
    output wire cpu_clk,
    output wire timer_clk
);
    assign cpu_clk   = clk_in1;
    assign timer_clk = clk_in1;
endmodule
