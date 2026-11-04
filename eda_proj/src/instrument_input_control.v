// TTP229 key selector. Lowest numbered active key wins when several keys are held.
module instrument_input_control(
    input  wire [15:0] touch_keys,
    output wire       note_on,
    output wire [6:0] note_number
);
    reg        note_on_r;
    reg [6:0]  note_number_r;
    integer i;

    always @* begin
        note_on_r     = 1'b0;
        note_number_r = 7'd0;
        for (i = 0; i < 16; i = i + 1) begin
            if (!note_on_r && touch_keys[i]) begin
                note_on_r = 1'b1;
                case (i)
                    0:  note_number_r = 7'd60; // C4
                    1:  note_number_r = 7'd62; // D4
                    2:  note_number_r = 7'd64; // E4
                    3:  note_number_r = 7'd65; // F4
                    4:  note_number_r = 7'd67; // G4
                    5:  note_number_r = 7'd69; // A4
                    6:  note_number_r = 7'd71; // B4
                    7:  note_number_r = 7'd72; // C5
                    8:  note_number_r = 7'd74; // D5
                    9:  note_number_r = 7'd76; // E5
                    10: note_number_r = 7'd77; // F5
                    11: note_number_r = 7'd79; // G5
                    12: note_number_r = 7'd81; // A5
                    13: note_number_r = 7'd83; // B5
                    14: note_number_r = 7'd84; // C6
                    15: note_number_r = 7'd86; // D6
                    default: note_number_r = 7'd0;
                endcase
            end
        end
    end

    assign note_on     = note_on_r;
    assign note_number = note_number_r;
endmodule
