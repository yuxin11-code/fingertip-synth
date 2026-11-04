// Imported from instrument_v1 on 2026-10-22; adapted for audio.gprj.
// ============================================================
//  instrument_v1 - input control
//
//  Both panels: every timbre supports direct touch and gesture plucking.
//  Each panel owns an independent 16-note strum sequencer.
//  Encoder       : A/D/S/R parameter selection and value edit
//  KEY1/KEY2     : reserved; master volume belongs to RP108 knob 1 only
//  TIMBRE_KEY    : direct touch / gesture-only pluck mode
//  K1 / K2       : left / right instrument selection
//  TEST_MODE_KEY : test mode toggle (32 fixed frequencies)
//
//  Strum timing is counted in audio frames (~20.135 us each).
// ============================================================
`default_nettype none

module mig_input_ctrl #(
    parameter integer CLK_HZ = 52500000,
    parameter integer GAP_FRAMES   = 1490,    // 30 ms  @ 49.66 kHz
    parameter integer HOLD_FRAMES  = 10930,   // 220 ms @ 49.66 kHz
    parameter integer DB_TICKS     = CLK_HZ / 50 // 20 ms @ 52.5 MHz
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         frame_tick,
    input wire hmi_valid,
    input wire [7:0] hmi_cmd,
    input wire [15:0] hmi_value,
    input wire selected_panel,
    input wire test_suspend,
    output wire volume_up_event,volume_down_event,

    input  wire [15:0]  keys_left,
    input  wire [15:0]  keys_right,

    input  wire         strum_right,
    input  wire         strum_left,

    input  wire         key_up_n,
    input  wire         key_dn_n,
    input  wire         inst_left_n,
    input  wire         inst_right_n,
    input  wire         aux3_n,
    input  wire         aux4_n,
    input  wire         test_toggle_n,
    input  wire         pluck_toggle_n,

    input  wire         enc_a,
    input  wire         enc_b,
    input  wire         enc_c_n,
    input  wire signed [7:0] transpose_left,
    input  wire signed [7:0] transpose_right,

    output reg  [31:0]  voice_gate,
    output reg  [255:0] voice_note,
    output reg  [95:0]  voice_inst,
    output wire [16:0]  volume_q16,
    output reg  [3:0]   adsr_a,
    output reg  [3:0]   adsr_d,
    output reg  [3:0]   adsr_s,
    output reg  [3:0]   adsr_r,
    output reg  [5:0]   active_voices,
    output reg          test_mode,
    output reg          strum_active,
    output reg          pluck_mode,
    output reg  [2:0]   inst_l,
    output reg  [2:0]   inst_r,
    output wire         aux3_stable,
    output wire         aux4_stable,
    output wire [15:0] guitar_attack, guitar_sustain,
    output wire [3:0] guitar_decay, guitar_release
);
    // Game freezes the requested test state but keeps the physical debounce
    // running. Held test keys therefore cannot create a false edge on exit.
    wire test_enabled=test_mode && !(test_suspend===1'b1);
    wire pluck_enabled=pluck_mode && !(test_suspend===1'b1);

    // ---------------------------------------------------------
    // synchronisers for signals coming from the audio domain
    // ---------------------------------------------------------
    reg [15:0] kl_meta, kl_sync;
    reg [15:0] kr_meta, kr_sync;
    reg        sr_meta,  sr_sync;
    reg        sl_meta,  sl_sync;
    reg        sa_meta,  sa_sync;
    reg        sb_meta,  sb_sync;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            kl_meta <= 16'd0; kl_sync <= 16'd0;
            kr_meta <= 16'd0; kr_sync <= 16'd0;
            sr_meta <= 1'b0;  sr_sync <= 1'b0;
            sl_meta <= 1'b0;  sl_sync <= 1'b0;
            sa_meta <= 1'b0;  sa_sync <= 1'b0;
            sb_meta <= 1'b0;  sb_sync <= 1'b0;
        end else begin
            kl_meta <= keys_left;   kl_sync <= kl_meta;
            kr_meta <= keys_right;  kr_sync <= kr_meta;
            sr_meta <= strum_right; sr_sync <= sr_meta;
            sl_meta <= strum_left;  sl_sync <= sl_meta;
            sa_meta <= enc_a;       sa_sync <= sa_meta;
            sb_meta <= enc_b;       sb_sync <= sb_meta;
        end
    end

    // ---------------------------------------------------------
    // active-low button debounce (~20 ms), one pulse per press
    // ---------------------------------------------------------
    // Bit 8 is the board's third key (TIMBRE_KEY / AA13). Unconnected
    // legacy simulation instances leave this optional input inactive.
    wire pluck_key_n=(pluck_toggle_n===1'b0)?1'b0:1'b1;
    wire [8:0] btn_raw = {pluck_key_n, aux4_n, aux3_n, test_toggle_n, inst_right_n,
                          inst_left_n, key_dn_n, key_up_n, enc_c_n};

    reg [8:0] btn_meta, btn_sample;
    reg [8:0]  btn_sync;
    reg [8:0]  btn_prev;
    reg [24:0] db_cnt [0:8];
    integer    b;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            btn_meta <= 9'h1FF; btn_sample <= 9'h1FF;
            btn_sync <= 9'h1FF;
            btn_prev <= 9'h1FF;
            for (b = 0; b < 9; b = b + 1) db_cnt[b] <= 25'd0;
        end else begin
            btn_meta <= btn_raw; btn_sample <= btn_meta;
            btn_prev <= btn_sync;
            for (b = 0; b < 9; b = b + 1) begin
                if (btn_sample[b] != btn_sync[b]) begin
                    if (db_cnt[b] >= DB_TICKS - 1) begin
                        btn_sync[b] <= btn_sample[b];
                        db_cnt[b]   <= 25'd0;
                    end else begin
                        db_cnt[b] <= db_cnt[b] + 25'd1;
                    end
                end else begin
                    db_cnt[b] <= 25'd0;
                end
            end
        end
    end

    // Compatibility outputs cannot make KEY1/KEY2 seize the volume pot.
    assign volume_up_event=1'b0;
    assign volume_down_event=1'b0;
    assign volume_q16=17'd32768;
    wire il_evt     = btn_prev[3] & ~btn_sync[3];
    wire ir_evt     = btn_prev[4] & ~btn_sync[4];
    wire test_evt   = btn_prev[5] & ~btn_sync[5];
    wire pluck_evt  = btn_prev[8] & ~btn_sync[8];
    assign aux3_stable = ~btn_sync[6];
    assign aux4_stable = ~btn_sync[7];
    wire enc_evt, enc_inc, enc_dec;
    rotary_encoder_decoder #(.CLK_HZ(CLK_HZ)) encoder (
        .clk(clk), .rst_n(rst_n), .enc_a(enc_a), .enc_b(enc_b),
        .enc_key_n(enc_c_n), .rotate_cw(enc_inc), .rotate_ccw(enc_dec),
        .select_pulse(enc_evt));

    // ---------------------------------------------------------
    // Guitar reuses the user's original parameter bank and encoder semantics.
    // The same encoder also edits the existing piano/sine parameter bank.
    // ---------------------------------------------------------
    wire [2:0] selected_instrument_hmi = selected_panel ? inst_r : inst_l;
    wire guitar_adsr_hmi = hmi_valid &&
                           ((selected_instrument_hmi==3'd1 && hmi_cmd>=8'h0b && hmi_cmd<=8'h0e) ||
                            (hmi_cmd>=8'h21 && hmi_cmd<=8'h24));
    wire [7:0] guitar_adsr_cmd = (hmi_cmd>=8'h0b && hmi_cmd<=8'h0e) ? hmi_cmd + 8'h16 : hmi_cmd;
    adsr_parameter_control guitar_parameters(
        .hmi_valid(guitar_adsr_hmi),.hmi_cmd(guitar_adsr_cmd),.hmi_value(hmi_value),
        .clk(clk),.rst_n(rst_n),.timbre_select(2'd3),
        .rotate_cw(enc_inc),.rotate_ccw(enc_dec),.select_pulse(enc_evt),
        .selected_stage(),.attack_step(guitar_attack),
        .decay_divider_limit(guitar_decay),.sustain_level(guitar_sustain),
        .release_divider_limit(guitar_release));
    // One debounced press toggles the global mode for both panels/timbres.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) pluck_mode <= 1'b0;
        else if (!(test_suspend===1'b1) && pluck_evt) pluck_mode <= ~pluck_mode;
    end

    // ---------------------------------------------------------
    // instrument selection (0 piano, 1 guitar, 2 sine)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            inst_l <= 3'd0;
            inst_r <= 3'd0;
        end else begin
            if (hmi_valid && hmi_cmd==8'h01) inst_l <= (hmi_value>4)?3'd4:hmi_value[2:0];
            else if (il_evt) inst_l <= (inst_l == 3'd4) ? 3'd0 : inst_l + 3'd1;
            if (hmi_valid && hmi_cmd==8'h02) inst_r <= (hmi_value>4)?3'd4:hmi_value[2:0];
            else if (ir_evt) inst_r <= (inst_r == 3'd4) ? 3'd0 : inst_r + 3'd1;
        end
    end

    // ---------------------------------------------------------
    // rotary encoder: quadrature decode + ADSR parameter select
    // ---------------------------------------------------------
    reg [1:0] enc_stage;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) enc_stage <= 2'd0;
        else if (enc_evt) enc_stage <= enc_stage + 2'd1;
    end

    // ---------------------------------------------------------
    // ADSR parameters (0..15 each, default A6 D4 S12 R5)
    // ---------------------------------------------------------
    reg [3:0] p_a, p_d, p_s, p_r;
    wire [15:0] limited_slider=(hmi_value>1000)?16'd1000:hmi_value;
    wire [16:0] slider_scaled;
    hmi_scale_exact #(.KIND(3)) exact_adsr(.slider(limited_slider),.scaled(slider_scaled));
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p_a <= 4'd6; p_d <= 4'd4; p_s <= 4'd12; p_r <= 4'd5;
        end else if (hmi_valid && !guitar_adsr_hmi && hmi_cmd>=8'h0b && hmi_cmd<=8'h0e) begin
            case(hmi_cmd)
                8'h0b:p_a<=slider_scaled;
                8'h0c:p_d<=slider_scaled;
                8'h0d:p_s<=slider_scaled;
                8'h0e:p_r<=slider_scaled;
            endcase
        end else if (enc_inc || enc_dec) begin
            case (enc_stage)
                2'd0: p_a <= enc_inc ? ((p_a == 4'd15) ? p_a : p_a + 4'd1)
                                     : ((p_a == 4'd0) ? p_a : p_a - 4'd1);
                2'd1: p_d <= enc_inc ? ((p_d == 4'd15) ? p_d : p_d + 4'd1)
                                     : ((p_d == 4'd0) ? p_d : p_d - 4'd1);
                2'd2: p_s <= enc_inc ? ((p_s == 4'd15) ? p_s : p_s + 4'd1)
                                     : ((p_s == 4'd0) ? p_s : p_s - 4'd1);
                default: p_r <= enc_inc ? ((p_r == 4'd15) ? p_r : p_r + 4'd1)
                                        : ((p_r == 4'd0) ? p_r : p_r - 4'd1);
            endcase
        end
    end
    always @(*) begin
        adsr_a = p_a;
        adsr_d = p_d;
        adsr_s = p_s;
        adsr_r = p_r;
    end

    // ---------------------------------------------------------
    // test mode
    // ---------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)        test_mode <= 1'b0;
        else if (test_suspend===1'b1) test_mode <= test_mode;
        else if (hmi_valid && hmi_cmd==8'h12) test_mode <= (hmi_value!=0);
        else if (test_evt) test_mode <= ~test_mode;
    end

    // ---------------------------------------------------------
    // Gesture pluck sequencer (frame based). The selected timbre only changes
    // oscillator/envelope parameters; it no longer gates this trigger path.
    // ---------------------------------------------------------
    reg        sr_sync_d, sl_sync_d;
    wire [31:0] guitar_gate;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin sr_sync_d<=0; sl_sync_d<=0; end
        else begin sr_sync_d<=sr_sync; sl_sync_d<=sl_sync; end
    end

    wire strum_right_evt = sr_sync & ~sr_sync_d;
    wire strum_left_evt  = sl_sync & ~sl_sync_d;

    function [3:0] lowest_bit;
        input [15:0] v;
        integer i;
        begin
            lowest_bit = 4'd0;
            for (i = 15; i >= 0; i = i - 1)
                if (v[i]) lowest_bit = i[3:0];
        end
    endfunction

    function [3:0] highest_bit;
        input [15:0] v;
        integer i;
        begin
            highest_bit = 4'd0;
            for (i = 0; i < 16; i = i + 1)
                if (v[i]) highest_bit = i[3:0];
        end
    endfunction

    genvar panel;
    generate for (panel=0; panel<2; panel=panel+1) begin: strum_panel
    wire [2:0] instrument = (panel==0) ? inst_l : inst_r;
    wire [15:0] keys = (panel==0) ? kl_sync : kr_sync;
    reg [2:0] instrument_d;
    reg pluck_mode_d;
    reg [15:0] pending;
    reg [10:0] gap_cnt;
    reg seq_active,seq_desc;
    reg [13:0] hold_cnt [0:15];
    reg [15:0] gate_bits;
    integer k;
    assign guitar_gate[panel*16 +: 16] = gate_bits;
    wire [3:0] next_key = seq_desc ? highest_bit(pending) : lowest_bit(pending);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            instrument_d <= 3'd0;
            pluck_mode_d <= 1'b0;
            pending     <= 16'd0;
            gap_cnt     <= 11'd0;
            seq_active  <= 1'b0;
            seq_desc    <= 1'b0;
            gate_bits <= 16'd0;
            for (k = 0; k < 16; k = k + 1) hold_cnt[k] <= 14'd0;
        end else begin
            instrument_d <= instrument;
            pluck_mode_d <= pluck_enabled;
            if (test_enabled || instrument != instrument_d || pluck_enabled != pluck_mode_d) begin
                pending <= 16'd0;
                gap_cnt <= 11'd0;
                seq_active <= 1'b0;
                gate_bits <= 16'd0;
                for (k=0;k<16;k=k+1) hold_cnt[k] <= 14'd0;
            end else if (strum_right_evt || strum_left_evt) begin
                pending    <= keys;
                seq_active <= (|keys);
                seq_desc   <= strum_left_evt;
                gap_cnt    <= 11'd0;
            end else if (frame_tick) begin
                for (k = 0; k < 16; k = k + 1) begin
                    if (hold_cnt[k] != 14'd0) hold_cnt[k] <= hold_cnt[k] - 14'd1;
                    gate_bits[k] <= (hold_cnt[k] > 14'd1);
                end

                if (seq_active) begin
                    if (gap_cnt < GAP_FRAMES[10:0]) begin
                        gap_cnt <= gap_cnt + 11'd1;
                    end else if (|pending) begin
                        hold_cnt[next_key] <= HOLD_FRAMES[13:0];
                        // One full audio frame low makes a repeated swipe restart
                        // this voice's envelope even before its previous hold ends.
                        gate_bits[next_key] <= 1'b0;
                        pending[next_key]  <= 1'b0;
                        gap_cnt            <= 11'd0;
                    end else begin
                        seq_active <= 1'b0;
                    end
                end
            end
        end
    end
    end endgenerate

    // ---------------------------------------------------------
    // key -> MIDI note map: C4 major scale, two octaves
    // ---------------------------------------------------------
    function [7:0] note_of;
        input [3:0] idx;
        begin
            case (idx)
                4'd0:  note_of = 8'd60;  4'd1:  note_of = 8'd62;
                4'd2:  note_of = 8'd64;  4'd3:  note_of = 8'd65;
                4'd4:  note_of = 8'd67;  4'd5:  note_of = 8'd69;
                4'd6:  note_of = 8'd71;  4'd7:  note_of = 8'd72;
                4'd8:  note_of = 8'd74;  4'd9:  note_of = 8'd76;
                4'd10: note_of = 8'd77;  4'd11: note_of = 8'd79;
                4'd12: note_of = 8'd81;  4'd13: note_of = 8'd83;
                4'd14: note_of = 8'd84;  default: note_of = 8'd86;
            endcase
        end
    endfunction

    // ---------------------------------------------------------
    // output vectors
    // ---------------------------------------------------------
    // Shared signed octave offsets: x12 = (x << 3) + (x << 2).
    // Register once per board so no transpose multiplier feeds the voice pass.
    wire signed [15:0] transpose_left_ext = {{8{transpose_left[7]}},transpose_left};
    wire signed [15:0] transpose_right_ext = {{8{transpose_right[7]}},transpose_right};
    reg signed [15:0] octave_offset_left,octave_offset_right;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            octave_offset_left <= 16'sd0;
            octave_offset_right <= 16'sd0;
        end else begin
            octave_offset_left <= (transpose_left_ext <<< 3) + (transpose_left_ext <<< 2);
            octave_offset_right <= (transpose_right_ext <<< 3) + (transpose_right_ext <<< 2);
        end
    end
    function [7:0] transposed_note;
        input [7:0] base_note;
        input signed [15:0] octave_offset;
        reg signed [15:0] result_note;
        begin
            result_note=$signed({1'b0,base_note})+octave_offset;
            // Protect future expanded limits from MIDI wrap and Nyquist alias.
            // Default +/-4 octaves keeps C4..D6 within MIDI 12..134.
            if(result_note<0) transposed_note=0;
            else if(result_note>135) transposed_note=135;
            else transposed_note=result_note[7:0];
        end
    endfunction
    reg [31:0] voice_gate_next;
    reg [255:0] voice_note_next;
    reg [95:0] voice_inst_next;
    integer j;
    always @(*) begin
        active_voices = 6'd0;
        strum_active  = !test_enabled && ((|guitar_gate[15:0]) || (|guitar_gate[31:16]));
        for (j = 0; j < 16; j = j + 1) begin
            // Pluck mode uses touch only to select strings; gestures trigger.
            voice_gate_next[j]        = test_enabled ? 1'b1 : ((!pluck_enabled && kl_sync[j]) | guitar_gate[j]);
            voice_note_next[j*8 +: 8] = test_enabled ? (8'd36 + j[7:0]) : transposed_note(note_of(j[3:0]),octave_offset_left);
            voice_inst_next[j*3 +: 3] = test_enabled ? 3'd2 : inst_l;
            if (voice_gate_next[j]) active_voices = active_voices + 6'd1;

            voice_gate_next[16+j]          = test_enabled ? 1'b1 : ((!pluck_enabled && kr_sync[j]) | guitar_gate[16+j]);
            voice_note_next[(16+j)*8 +: 8] = test_enabled ? (8'd52 + j[7:0])
                                                  : transposed_note(note_of(j[3:0]),octave_offset_right);
            voice_inst_next[(16+j)*3 +: 3] = test_enabled ? 3'd2 : inst_r;
            if (voice_gate_next[16+j]) active_voices = active_voices + 6'd1;
        end
    end

    // Gate, note and instrument (including test mode) cross the same register.
    integer reset_voice;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            voice_gate <= 32'd0;
            voice_inst <= 96'd0;
            for(reset_voice=0;reset_voice<32;reset_voice=reset_voice+1)
                voice_note[reset_voice*8 +: 8] <= note_of(reset_voice[3:0]);
        end else begin
            voice_gate <= voice_gate_next;
            voice_note <= voice_note_next;
            voice_inst <= voice_inst_next;
        end
    end

endmodule

`default_nettype wire

