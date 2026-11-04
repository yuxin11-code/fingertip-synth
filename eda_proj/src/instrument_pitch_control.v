// C-major note table used by both the sixteen touch keys and auto-chords.
module instrument_pitch_control(
    input  wire [6:0] note_number,
    output reg  [31:0] phase_step
);
    always @* begin
        case (note_number)
            7'd60: phase_step = 32'd11312704;  // C4
            7'd62: phase_step = 32'd12698081;  // D4
            7'd64: phase_step = 32'd14253114;  // E4
            7'd65: phase_step = 32'd15100648;  // F4
            7'd67: phase_step = 32'd16949904;  // G4
            7'd69: phase_step = 32'd19025624;  // A4
            7'd71: phase_step = 32'd21355541;  // B4
            7'd72: phase_step = 32'd22625407;  // C5
            7'd74: phase_step = 32'd25396161;  // D5
            7'd76: phase_step = 32'd28506227;  // E5
            7'd77: phase_step = 32'd30201296;  // F5
            7'd79: phase_step = 32'd33899808;  // G5
            7'd81: phase_step = 32'd38051248;  // A5
            7'd83: phase_step = 32'd42711082;  // B5
            7'd84: phase_step = 32'd45250815;  // C6
            7'd86: phase_step = 32'd50792322;  // D6
            7'd88: phase_step = 32'd57012454;  // E6
            7'd89: phase_step = 32'd60402592;  // F6
            7'd91: phase_step = 32'd67799616;  // G6
            7'd93: phase_step = 32'd76102496;  // A6
            7'd95: phase_step = 32'd85422164;  // B6
            7'd96: phase_step = 32'd90501630;  // C7
            7'd98: phase_step = 32'd101584644; // D7
            default: phase_step = 32'd0;
        endcase
    end
endmodule
