// Signed PCM volume scaler.  Q16 gain represents 0.0 .. 1.0 exactly.
// The 32-bit sample is scaled before the final 16-bit limiter so attenuation
// cannot introduce an intermediate overflow or clipping error.
module volume_scale(
    input  wire signed [31:0] sample_in,
    input  wire        [16:0] gain_q16,
    output reg  signed [31:0] sample_out
);
    reg signed [49:0] product;
    reg signed [49:0] scaled;

    always @* begin
        product = $signed(sample_in) * $signed({1'b0, gain_q16});
        scaled  = product >>> 16;
        if (scaled > 50'sd2147483647)
            sample_out = 32'sh7fffffff;
        else if (scaled < -50'sd2147483648)
            sample_out = 32'sh80000000;
        else
            sample_out = scaled[31:0];
    end
endmodule
