module instrument_voice(
    input wire clk,input wire rst_n,input wire sample_enable,
    input wire note_on,
    input wire [6:0] note_number,
    input wire [17:0] pitch_scale_q16,
    input wire [1:0] timbre_select,input wire [15:0] attack_step,
    input wire [3:0] decay_divider_limit,input wire [15:0] sustain_level,
    input wire [3:0] release_divider_limit,
    output wire signed [31:0] sample_out
);
    wire [31:0] phase_step;

    wire [49:0] scaled_phase_product;
    wire [33:0] scaled_phase_step_full;
    wire [31:0] scaled_phase_step;

    reg [31:0] held_phase_step;    wire signed [15:0] dds_sample;
    wire signed [31:0] dds_sample_wide;
    instrument_pitch_control pitch_control(.note_number(note_number),.phase_step(phase_step));
    assign scaled_phase_product =
        phase_step * pitch_scale_q16;

    assign scaled_phase_step_full =
        scaled_phase_product[49:16];

    assign scaled_phase_step =
        |scaled_phase_step_full[33:32]
        ? 32'hFFFFFFFF
        : scaled_phase_step_full[31:0];
    always @(posedge clk or negedge rst_n)
        if(!rst_n) held_phase_step<=0;
        else if(note_on)
            held_phase_step <= scaled_phase_step;
    instrument_dds_nco dds_nco(.clk(clk),.rst_n(rst_n),.sample_enable(sample_enable),
        .phase_step(held_phase_step),.timbre_select(timbre_select),.sample(dds_sample));
    assign dds_sample_wide={{16{dds_sample[15]}},dds_sample};
    instrument_envelope_volume envelope(.clk(clk),.rst_n(rst_n),.sample_enable(sample_enable),
        .note_on(note_on),.note_number(note_number),.timbre_select(timbre_select),
        .attack_step(attack_step),.decay_divider_limit(decay_divider_limit),
        .sustain_level(sustain_level),.release_divider_limit(release_divider_limit),
        .sample_in(dds_sample_wide),.sample_out(sample_out));
endmodule
