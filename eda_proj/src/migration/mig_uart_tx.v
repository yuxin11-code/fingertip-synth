// Imported from instrument_v1 on 2026-10-22; adapted for audio.gprj.
// ============================================================
//  instrument_v1 - simple UART transmitter (8N1)
//
//  DIV = round(CLK_HZ / BAUD); at 52.5 MHz / 115200 this gives
//  456 -> 115131 baud, about 0.06 % error.
// ============================================================
`default_nettype none

module mig_uart_tx #(
    parameter integer CLK_HZ = 52500000,
    parameter integer BAUD   = 115200
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,     // one clk pulse
    input  wire [7:0] data,
    output reg        tx,
    output reg        busy
);

    localparam integer DIV = (CLK_HZ + BAUD/2) / BAUD;

    reg [15:0] div_cnt;
    reg [3:0]  bit_idx;
    reg [9:0]  shifter;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx      <= 1'b1;
            busy    <= 1'b0;
            div_cnt <= 16'd0;
            bit_idx <= 4'd0;
            shifter <= 10'h3FF;
        end else if (!busy) begin
            tx <= 1'b1;
            if (start) begin
                shifter <= {1'b1, data, 1'b0};   // stop, data[7:0], start
                busy    <= 1'b1;
                div_cnt <= 16'd0;
                bit_idx <= 4'd0;
                tx      <= 1'b0;                 // start bit
            end
        end else begin
            if (div_cnt >= DIV - 1) begin
                div_cnt <= 16'd0;
                if (bit_idx == 4'd9) begin
                    busy <= 1'b0;
                    tx   <= 1'b1;
                end else begin
                    bit_idx <= bit_idx + 4'd1;
                    tx      <= shifter[bit_idx + 4'd1];
                end
            end else begin
                div_cnt <= div_cnt + 16'd1;
            end
        end
    end

endmodule

`default_nettype wire
