module gesture_strum_control #(
    parameter integer CLK_HZ        = 1500000,
    parameter integer STRUM_GAP_MS  = 30,
    parameter integer NOTE_GATE_MS  = 220
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,
    input  wire [15:0] touch_keys,
    input  wire        strum_right,
    input  wire        strum_left,

    output reg  [3:0]  voice_gate,
    output reg  [6:0]  voice0_note,
    output reg  [6:0]  voice1_note,
    output reg  [6:0]  voice2_note,
    output reg  [6:0]  voice3_note
);

    localparam integer GAP_TICKS  = (CLK_HZ / 1000) * STRUM_GAP_MS;
    localparam integer NOTE_TICKS = (CLK_HZ / 1000) * NOTE_GATE_MS;

    reg [6:0] selected_note0;
    reg [6:0] selected_note1;
    reg [6:0] selected_note2;
    reg [6:0] selected_note3;
    reg [2:0] selected_count;
    reg [2:0] active_count;
    reg [31:0] elapsed_ticks;
    reg active;
    reg found0;
    reg found1;
    reg found2;
    reg found3;
    integer i;
    // C-major scale notes.  The first sixteen entries match the sixteen
    // touch keys.  The remaining seven entries allow every root key to form
    // root/third/fifth/octave without falling outside the pitch table.
    function [6:0] scale_index_to_note;
        input [4:0] scale_index;
        begin
            case (scale_index)
                5'd0:  scale_index_to_note = 7'd60; // C4
                5'd1:  scale_index_to_note = 7'd62; // D4
                5'd2:  scale_index_to_note = 7'd64; // E4
                5'd3:  scale_index_to_note = 7'd65; // F4
                5'd4:  scale_index_to_note = 7'd67; // G4
                5'd5:  scale_index_to_note = 7'd69; // A4
                5'd6:  scale_index_to_note = 7'd71; // B4
                5'd7:  scale_index_to_note = 7'd72; // C5
                5'd8:  scale_index_to_note = 7'd74; // D5
                5'd9:  scale_index_to_note = 7'd76; // E5
                5'd10: scale_index_to_note = 7'd77; // F5
                5'd11: scale_index_to_note = 7'd79; // G5
                5'd12: scale_index_to_note = 7'd81; // A5
                5'd13: scale_index_to_note = 7'd83; // B5
                5'd14: scale_index_to_note = 7'd84; // C6
                5'd15: scale_index_to_note = 7'd86; // D6
                5'd16: scale_index_to_note = 7'd88; // E6
                5'd17: scale_index_to_note = 7'd89; // F6
                5'd18: scale_index_to_note = 7'd91; // G6
                5'd19: scale_index_to_note = 7'd93; // A6
                5'd20: scale_index_to_note = 7'd95; // B6
                5'd21: scale_index_to_note = 7'd96; // C7
                5'd22: scale_index_to_note = 7'd98; // D7
                default: scale_index_to_note = 7'd60;
            endcase
        end
    endfunction

// 从当前按下的触摸键中，按照音高从低到高选择最多四个音。
always @* begin
    selected_note0 = 7'd60;
    selected_note1 = 7'd60;
    selected_note2 = 7'd60;
    selected_note3 = 7'd60;

    found0 = 1'b0;
    found1 = 1'b0;
    found2 = 1'b0;
    found3 = 1'b0;

    for (i = 0; i < 16; i = i + 1) begin
        if (touch_keys[i]) begin
            if (!found0) begin
                selected_note0 = scale_index_to_note(i[4:0]);
                found0 = 1'b1;
            end else if (!found1) begin
                selected_note1 = scale_index_to_note(i[4:0]);
                found1 = 1'b1;
            end else if (!found2) begin
                selected_note2 = scale_index_to_note(i[4:0]);
                found2 = 1'b1;
            end else if (!found3) begin
                selected_note3 = scale_index_to_note(i[4:0]);
                found3 = 1'b1;
            end
        end
    end

    selected_count = {2'd0, found0}
                   + {2'd0, found1}
                   + {2'd0, found2}
                   + {2'd0, found3};
end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            voice_gate    <= 4'b0000;
            voice0_note   <= 7'd60;
            voice1_note   <= 7'd60;
            voice2_note   <= 7'd60;
            voice3_note   <= 7'd60;
            active_count  <= 3'd0;
            elapsed_ticks <= 32'd0;
            active        <= 1'b0;
        end else if (!enable) begin
            voice_gate    <= 4'b0000;
            active_count  <= 3'd0;
            elapsed_ticks <= 32'd0;
            active        <= 1'b0;
        end else if ((strum_right || strum_left) && selected_count != 3'd0) begin
            active_count  <= selected_count;
            elapsed_ticks <= 32'd0;
            active        <= 1'b1;
            voice_gate    <= 4'b0001;

        if (strum_left) begin
            // 左扫：根据实际按键数量，从高音到低音排列。
            case (selected_count)
                3'd1: begin
                    voice0_note <= selected_note0;
                    voice1_note <= selected_note0;
                    voice2_note <= selected_note0;
                    voice3_note <= selected_note0;
                end

                3'd2: begin
                    voice0_note <= selected_note1;
                    voice1_note <= selected_note0;
                    voice2_note <= selected_note0;
                    voice3_note <= selected_note0;
                end

                3'd3: begin
                    voice0_note <= selected_note2;
                    voice1_note <= selected_note1;
                    voice2_note <= selected_note0;
                    voice3_note <= selected_note0;
                end

                default: begin
                    voice0_note <= selected_note3;
                    voice1_note <= selected_note2;
                    voice2_note <= selected_note1;
                    voice3_note <= selected_note0;
                end
            endcase
        end else begin
            // 右扫：从低音到高音排列。
            voice0_note <= selected_note0;
            voice1_note <= selected_note1;
            voice2_note <= selected_note2;
            voice3_note <= selected_note3;
        end
        end else if (active) begin
            elapsed_ticks <= elapsed_ticks + 1'b1;

            if (active_count > 3'd1 && elapsed_ticks == GAP_TICKS - 1)
                voice_gate[1] <= 1'b1;
            if (active_count > 3'd2 && elapsed_ticks == (2 * GAP_TICKS) - 1)
                voice_gate[2] <= 1'b1;
            if (active_count > 3'd3 && elapsed_ticks == (3 * GAP_TICKS) - 1)
                voice_gate[3] <= 1'b1;

            if (elapsed_ticks == NOTE_TICKS - 1)
                voice_gate[0] <= 1'b0;
            if (elapsed_ticks == GAP_TICKS + NOTE_TICKS - 1)
                voice_gate[1] <= 1'b0;
            if (elapsed_ticks == (2 * GAP_TICKS) + NOTE_TICKS - 1)
                voice_gate[2] <= 1'b0;
            if (elapsed_ticks == (3 * GAP_TICKS) + NOTE_TICKS - 1) begin
                voice_gate[3] <= 1'b0;
                active        <= 1'b0;
            end
        end else begin
            voice_gate <= 4'b0000;
        end
    end

endmodule
