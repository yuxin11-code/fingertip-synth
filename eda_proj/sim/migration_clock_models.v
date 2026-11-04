// Behavioural stand-ins for the Gowin clock primitives (simulation only).
`timescale 1ns/1ps

module Gowin_OSC (
    output wire oscout
);
    reg clk = 1'b0;
    initial begin
        forever #9.5238 clk = ~clk;      // 52.5 MHz
    end
    assign oscout = clk;
endmodule

module Gowin_PLL (
    output wire clkout0,
    input  wire clkin
);
    reg clk = 1'b0;
    initial begin
        forever #78.648 clk = ~clk;      // 6.357 MHz
    end
    assign clkout0 = clk;
endmodule

module Gowin_CLKDIV (
    output wire clkout,
    input  wire hclkin,
    input  wire resetn
);
    reg [1:0] div = 2'd0;
    reg clk = 1'b0;
    always @(posedge hclkin or negedge resetn) begin
        if (!resetn) begin
            div <= 2'd0;
            clk <= 1'b0;
        end else begin
            div <= div + 2'd1;
            clk <= div[1];          // 0,0,1,1 -> divide by 4
        end
    end
    assign clkout = clk;
endmodule
