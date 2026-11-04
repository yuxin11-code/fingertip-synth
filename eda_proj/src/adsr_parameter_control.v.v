module adsr_parameter_control (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [1:0]  timbre_select,
    input  wire        rotate_cw,
    input  wire        rotate_ccw,
    input  wire        select_pulse,
    input wire hmi_valid,
    input wire [7:0] hmi_cmd,
    input wire [15:0] hmi_value,

    output reg  [1:0]  selected_stage,
    output wire [15:0] attack_step,
    output wire [3:0]  decay_divider_limit,
    output wire [15:0] sustain_level,
    output wire [3:0]  release_divider_limit
);

    localparam [1:0] STAGE_ATTACK  = 2'd0;
    localparam [1:0] STAGE_DECAY   = 2'd1;
    localparam [1:0] STAGE_SUSTAIN = 2'd2;
    localparam [1:0] STAGE_RELEASE = 2'd3;

    // Each timbre owns one editable ADSR bank.  Switching timbre does not
    // erase edits; all four banks return to these presets after reset.
    reg [15:0] attack_mem  [0:3];
    reg [3:0]  decay_mem   [0:3];
    reg [15:0] sustain_mem [0:3];
    reg [3:0]  release_mem [0:3];
    wire [15:0] slider=(hmi_value>1000)?16'd1000:hmi_value;
    wire [16:0] scaled_a,scaled_s,scaled_dr;
    hmi_scale_exact #(.KIND(1)) exact_a(.slider(slider),.scaled(scaled_a));
    hmi_scale_exact #(.KIND(2)) exact_s(.slider(slider),.scaled(scaled_s));
    hmi_scale_exact #(.KIND(3)) exact_dr(.slider(slider),.scaled(scaled_dr));

    assign attack_step           = attack_mem[timbre_select];
    assign decay_divider_limit   = decay_mem[timbre_select];
    assign sustain_level         = sustain_mem[timbre_select];
    assign release_divider_limit = release_mem[timbre_select];

    // Attack uses a step rather than a time counter:
    // smaller step = longer attack, larger step = shorter attack.
    function [15:0] make_attack_slower;
        input [15:0] value;
        reg   [15:0] delta;
        begin
            delta = value >> 3;
            if (delta == 16'd0)
                delta = 16'd1;

            if (value <= delta || value <= 16'd1)
                make_attack_slower = 16'd1;
            else
                make_attack_slower = value - delta;
        end
    endfunction

    function [15:0] make_attack_faster;
        input [15:0] value;
        reg   [15:0] delta;
        begin
            delta = value >> 3;
            if (delta == 16'd0)
                delta = 16'd1;

            if (value >= 16'd3640)
                make_attack_faster = 16'd4096;
            else
                make_attack_faster = value + delta;
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            selected_stage <= STAGE_ATTACK;

            // Timbre 0: sine
            attack_mem[0]  <= 16'd1024;
            decay_mem[0]   <= 4'd1;
            sustain_mem[0] <= 16'd26214;
            release_mem[0] <= 4'd2;

            // Timbre 1: triangle
            attack_mem[1]  <= 16'd768;
            decay_mem[1]   <= 4'd2;
            sustain_mem[1] <= 16'd22937;
            release_mem[1] <= 4'd3;

            // Timbre 2: piano.  Sustain is 20% of its 20480 peak.
            attack_mem[2]  <= 16'd26;
            decay_mem[2]   <= 4'd7;
            sustain_mem[2] <= 16'd4096;
            release_mem[2] <= 4'd5;

            // Timbre 3: guitar
            attack_mem[3]  <= 16'd256;
            decay_mem[3]   <= 4'd3;
            sustain_mem[3] <= 16'd2048;
            release_mem[3] <= 4'd3;
        end else if(hmi_valid && hmi_cmd>=8'h21 && hmi_cmd<=8'h24)begin
            case(hmi_cmd)
                8'h21:attack_mem[3]<=scaled_a[15:0];
                8'h22:decay_mem[3]<=scaled_dr[3:0];
                8'h23:sustain_mem[3]<=scaled_s[15:0];
                8'h24:release_mem[3]<=scaled_dr[3:0];
            endcase
        end else begin
            // One press selects A, D, S, R in a loop.
            if (select_pulse) begin
                selected_stage <= selected_stage + 2'd1;
            end else if (rotate_cw) begin
                case (selected_stage)
                    STAGE_ATTACK: begin
                        attack_mem[timbre_select] <=
                            make_attack_slower(attack_mem[timbre_select]);
                    end

                    STAGE_DECAY: begin
                        if (decay_mem[timbre_select] < 4'd15)
                            decay_mem[timbre_select] <=
                                decay_mem[timbre_select] + 1'b1;
                    end

                    STAGE_SUSTAIN: begin
                        if (sustain_mem[timbre_select] >= 16'd32255)
                            sustain_mem[timbre_select] <= 16'd32767;
                        else
                            sustain_mem[timbre_select] <=
                                sustain_mem[timbre_select] + 16'd512;
                    end

                    STAGE_RELEASE: begin
                        if (release_mem[timbre_select] < 4'd15)
                            release_mem[timbre_select] <=
                                release_mem[timbre_select] + 1'b1;
                    end
                endcase
            end else if (rotate_ccw) begin
                case (selected_stage)
                    STAGE_ATTACK: begin
                        attack_mem[timbre_select] <=
                            make_attack_faster(attack_mem[timbre_select]);
                    end

                    STAGE_DECAY: begin
                        if (decay_mem[timbre_select] > 4'd0)
                            decay_mem[timbre_select] <=
                                decay_mem[timbre_select] - 1'b1;
                    end

                    STAGE_SUSTAIN: begin
                        if (sustain_mem[timbre_select] <= 16'd512)
                            sustain_mem[timbre_select] <= 16'd0;
                        else
                            sustain_mem[timbre_select] <=
                                sustain_mem[timbre_select] - 16'd512;
                    end

                    STAGE_RELEASE: begin
                        if (release_mem[timbre_select] > 4'd0)
                            release_mem[timbre_select] <=
                                release_mem[timbre_select] - 1'b1;
                    end
                endcase
            end
        end
    end

endmodule
