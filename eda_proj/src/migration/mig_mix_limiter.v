// Imported from instrument_v1 on 2026-10-22; adapted for audio.gprj.
// ============================================================
//  instrument_v1 - mix scaling, volume and saturation
//
//  sum_in is the raw 32-voice accumulator.  SHIFT sets the fixed
//  voice-count headroom; test_atten shifts three more bits when
//  the 32-voice test pattern is running.
// ============================================================
`default_nettype none

module mig_mix_limiter #(
    parameter integer SHIFT = 2          // divide by 4 before limiting
)(
    input  wire                clk,
    input  wire                rst_n,
    input  wire signed [39:0]  sum_in,
    input  wire [16:0]         vol_q16,  // 0 .. 65536
    input  wire                test_atten,
    output reg  signed [15:0]  sample_out
);

    wire [16:0] vol_eff  = test_atten ? {3'd0, vol_q16[16:3]} : vol_q16;
    wire signed [39:0] scaled = sum_in >>> SHIFT;
    wire signed [63:0] prod   = scaled * $signed({1'b0, vol_eff});
    wire signed [63:0] mixed  = prod >>> 16;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)                   sample_out <= 16'sd0;
        else if (mixed >  63'sd32767) sample_out <= 16'sd32767;
        else if (mixed < -63'sd32768) sample_out <= -16'sd32768;
        else                          sample_out <= mixed[15:0];
    end

endmodule

`default_nettype wire
