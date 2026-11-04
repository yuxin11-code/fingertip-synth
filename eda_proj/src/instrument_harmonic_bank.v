// 32-term additive bank. Only the fundamental is populated in this first stage.
module instrument_harmonic_bank #(
    parameter HARMONIC_COUNT = 32
)(
    input wire [HARMONIC_COUNT*22-1:0] partials,
    output reg signed [26:0] sample_sum
);
    integer i;
    always @* begin
        sample_sum = 27'sd0;
        for (i = 0; i < HARMONIC_COUNT; i = i + 1)
            sample_sum = sample_sum + {{5{partials[i*22+21]}}, partials[i*22 +: 22]};
    end
endmodule
