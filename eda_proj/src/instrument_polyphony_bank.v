// 32-voice summing bank. Stage 1 drives voice 0; the rest remain silent.
module instrument_polyphony_bank #(
    parameter VOICE_COUNT = 32
)(
    input wire [VOICE_COUNT-1:0] voice_enable,
    input wire [VOICE_COUNT*27-1:0] voices,
    output reg signed [31:0] sample_sum
);
    integer i;
    always @* begin
        sample_sum = 32'sd0;
        for (i = 0; i < VOICE_COUNT; i = i + 1)
            if (voice_enable[i])
                sample_sum = sample_sum + {{5{voices[i*27+26]}}, voices[i*27 +: 27]};
    end
endmodule
