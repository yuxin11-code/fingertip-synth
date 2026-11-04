// Signed 32-bit mix to signed 16-bit audio with saturation.
module instrument_mixer_limiter(
    input wire signed [31:0] sample_in,
    output reg signed [15:0] sample_out
);
    always @* begin
        if (sample_in > 32'sd32767)
            sample_out = 16'sd32767;
        else if (sample_in < -32'sd32768)
            sample_out = -16'sd32768;
        else
            sample_out = sample_in[15:0];
    end
endmodule
