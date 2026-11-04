// Scalable oscillator bus. Stage 1 enables only oscillator 0.
module instrument_multi_oscillator #(
    parameter OSC_COUNT = 4
)(
    input wire signed [15:0] source_sample,
    output reg signed [21:0] sample_sum
);
    wire [OSC_COUNT*16-1:0] oscillator_samples;
    integer i;

    assign oscillator_samples[15:0] = source_sample;
    genvar g;
    generate for (g = 1; g < OSC_COUNT; g = g + 1) begin: disabled_oscillators
        assign oscillator_samples[g*16 +: 16] = 16'd0;
    end endgenerate

    always @* begin
        sample_sum = 22'sd0;
        for (i = 0; i < OSC_COUNT; i = i + 1)
            sample_sum = sample_sum + {{6{oscillator_samples[i*16+15]}}, oscillator_samples[i*16 +: 16]};
    end
endmodule
