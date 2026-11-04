// Imported from instrument_v1 on 2026-10-22; adapted for audio.gprj.
// ============================================================
//  instrument_v1 - 32 voice TDMA synthesis engine
//
//  One voice is processed per clk_sys cycle.  A frame is ~1057
//  cycles at 52.5 MHz, so 32 voices + pipeline take ~35 cycles
//  (about 3 % of the frame).
//
//  Per voice: 32-bit phase accumulator, 256-point single-cycle
//  wave table, independent 4-state ADSR envelope.
//
//  The MIDI-note -> phase-step lookup is registered one cycle
//  behind the voice pass (step for voice v-1 is written while
//  voice v is processed).  This keeps the 85-entry lookup out of
//  the phase-adder path and gives a healthy Fmax margin.
// ============================================================
`default_nettype none

module mig_voice_engine_ref #(
    parameter integer NV = 32
)(
    input  wire                clk,
    input  wire                rst_n,
    input  wire                frame_tick,

    input  wire [31:0]         v_gate,     // one bit per voice
    input  wire [255:0]        v_note,     // 32 x 8 bit MIDI note
    input  wire [95:0]         v_inst,     // 32 x 3 bit instrument

    input wire [17:0] pitch_scale_q16,
    input  wire [3:0]          a_param,
    input  wire [3:0]          d_param,
    input  wire [3:0]          s_param,
    input  wire [3:0]          r_param,

    input wire [15:0] guitar_attack, guitar_sustain,
    input wire [3:0] guitar_decay, guitar_release,
    output reg  signed [39:0]  mix_sum,
    output reg signed [39:0] panel_a_sum,panel_b_sum
);

    // ---------------------------------------------------------
    // per voice state
    // ---------------------------------------------------------
    reg [31:0] phase   [0:NV-1];
    reg [31:0] step    [0:NV-1];
    reg [16:0] gain    [0:NV-1];
    reg [2:0]  env_st  [0:NV-1];
    reg [11:0] div_cnt [0:NV-1];
    reg        gate_d  [0:NV-1];
    reg [7:0]  note_d  [0:NV-1];
    reg [2:0]  inst_d  [0:NV-1];

    localparam [2:0] ST_IDLE    = 3'd0;
    localparam [2:0] ST_ATTACK  = 3'd1;
    localparam [2:0] ST_DECAY   = 3'd2;
    localparam [2:0] ST_SUSTAIN = 3'd3;
    localparam [2:0] ST_RELEASE = 3'd4;

    // ---------------------------------------------------------
    // Original audio_drive requests at BCLK 0 and 16: two envelope ticks
    // per stereo frame. Update twice before starting the TDMA voice pass.
    // Constant sample_in=32768 exposes Q15 gain through the original module's
    // public sample_out; synthesis folds its constant multiply into wiring.
    // ---------------------------------------------------------
    reg guitar_tick_d;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) guitar_tick_d <= 1'b0;
        else guitar_tick_d <= frame_tick;
    wire signed [31:0] guitar_gain [0:NV-1];
    genvar gv;
    generate for(gv=0;gv<NV;gv=gv+1) begin: original_guitar
        wire is_guitar = v_inst[gv*3 +: 3] == 3'd1;
        instrument_envelope_volume envelope(
            .clk(clk),.rst_n(rst_n),.sample_enable(frame_tick | guitar_tick_d),
            .note_on(v_gate[gv] & is_guitar),.note_number(v_note[gv*8 +: 7]),
            .timbre_select(is_guitar ? 2'd3 : 2'd0),
            .attack_step(guitar_attack),.decay_divider_limit(guitar_decay),
            .sustain_level(guitar_sustain),.release_divider_limit(guitar_release),
            .sample_in(32'sd32768),.sample_out(guitar_gain[gv]));
    end endgenerate
    // scheduler
    // ---------------------------------------------------------
    reg        running;
    reg [5:0]  vidx;           // 0..31 voices, 32/33 = pipeline flush
    reg signed [39:0] sum_acc;
    reg signed [39:0] acc_a,acc_b;
    reg pipe_panel,rom_panel;

    // pipeline registers (stage A -> stage B)
    reg        pipe_valid;
    reg rom_valid;
    reg [16:0] rom_gain;
    reg [16:0] pipe_gain;
    reg [10:0] rom_addr;
    wire signed [15:0] rom_data;

    // signed pipeline multiply: the wave sample must stay signed, the
    // envelope gain is an unsigned Q16 factor (0..65535)
    wire signed [39:0] rom_ext   = {{24{rom_data[15]}}, rom_data};
    wire signed [39:0] gain_ext  = $signed({1'b0, rom_gain});
    wire signed [79:0] product   = rom_ext * gain_ext;
    wire signed [79:0] product_q = product >>> 16;


    mig_wave_rom u_wave (
        .clk(clk),
        .inst(rom_addr[10:8]),
        .idx(rom_addr[7:0]),
        .data(rom_data)
    );

    // ---------------------------------------------------------
    // current voice signals
    // ---------------------------------------------------------
    wire [4:0]  vi        = vidx[4:0];
    wire        cur_gate  = v_gate[vi];
    wire [7:0]  cur_note  = v_note[vi*8 +: 8];
    wire [2:0]  cur_inst  = v_inst[vi*3 +: 3];

    // voice whose note was registered on the previous cycle
    wire [4:0]  pv        = (vidx == 6'd0) ? 5'd0 : (vidx[4:0] - 5'd1);
    wire [7:0]  prev_note = note_d[pv];
    wire [31:0] step_lookup;
    mig_note_step u_note_step (
        .note(prev_note),
        .step(step_lookup)
    );

    wire [49:0] pitch_product = step_lookup * pitch_scale_q16;

    // ---------------------------------------------------------
    // envelope parameters, derived from the 4-bit controls
    // ---------------------------------------------------------
    reg [16:0] attack_step;
    reg [16:0] sustain_calc;
    reg [16:0] sustain_lvl;
    reg [3:0]  decay_div;
    reg [3:0]  release_div;
    // Instrument-specific approximate envelopes.  Piano keeps the original
    // ADSR controls; violin is slower and more sustained, while guzheng and
    // pipa are fast plucked voices with shorter tails.  Guitar remains on
    // the original envelope instance above.
    always @(*) begin
        case (cur_inst)
            3'd2: begin
                attack_step  = ({13'd0,a_param} + 17'd2) << 7;
                sustain_calc = ({13'd0,s_param} + 17'd2) << 12;
                decay_div = d_param + 4'd2;
                release_div = r_param + 4'd3;
            end
            3'd3: begin
                attack_step  = ({13'd0,a_param} + 17'd2) << 9;
                sustain_calc = ({13'd0,s_param} + 17'd1) << 11;
                decay_div = (d_param >> 1) + 4'd1;
                release_div = (r_param >> 1) + 4'd1;
            end
            3'd4: begin
                attack_step  = ({13'd0,a_param} + 17'd4) << 9;
                sustain_calc = ({13'd0,s_param} + 17'd1) << 10;
                decay_div = d_param >> 1;
                release_div = (r_param >> 1) + 4'd1;
            end
            default: begin
                attack_step  = ({13'd0,a_param} + 17'd1) << 8;
                sustain_calc = ({13'd0,s_param} + 17'd1) << 12;
                decay_div = d_param;
                release_div = r_param;
            end
        endcase
        sustain_lvl = (sustain_calc > 17'd65535) ? 17'd65535 : sustain_calc;
    end

    // ---------------------------------------------------------
    // combinational next values for the current voice
    // ---------------------------------------------------------
    reg [16:0] gain_nxt;
    reg [2:0]  st_nxt;
    reg [11:0] div_nxt;
    reg [31:0] phase_nxt;
    reg        restart;
    reg        timbre_change;

    always @(*) begin
        gain_nxt  = gain[vi];
        st_nxt    = env_st[vi];
        div_nxt   = div_cnt[vi];
        phase_nxt = phase[vi];
        timbre_change = (cur_inst != inst_d[vi]);
        restart   = cur_gate & ((~gate_d[vi]) | (cur_note != note_d[vi]));

        if (timbre_change && cur_gate) begin
            // Re-arm the individual voice on every timbre transition.  The
            // old gate is forced low for one scheduler pass so 4->0 cannot
            // inherit a stale sustain or guitar path.
            st_nxt    = ST_IDLE;
            gain_nxt  = 17'd0;
            div_nxt   = 12'd0;
            phase_nxt = 32'd0;
        end else if (restart) begin
            st_nxt   = ST_ATTACK;
            gain_nxt = 17'd0;
            div_nxt  = 12'd0;
        end else begin
            case (env_st[vi])
                ST_IDLE: begin
                    gain_nxt = 17'd0;
                end
                ST_ATTACK: begin
                    if (!cur_gate) begin
                        st_nxt  = ST_RELEASE;
                        div_nxt = 12'd0;
                    end else if (gain[vi] + attack_step >= 17'd65535) begin
                        gain_nxt = 17'd65535;
                        st_nxt   = ST_DECAY;
                        div_nxt  = 12'd0;
                    end else begin
                        gain_nxt = gain[vi] + attack_step;
                    end
                end
                ST_DECAY: begin
                    if (!cur_gate) begin
                        st_nxt  = ST_RELEASE;
                        div_nxt = 12'd0;
                    end else if (gain[vi] <= sustain_lvl) begin
                        gain_nxt = sustain_lvl;
                        st_nxt   = ST_SUSTAIN;
                        div_nxt  = 12'd0;
                    end else if (div_cnt[vi] >= {8'd0, decay_div}) begin
                        div_nxt  = 12'd0;
                        gain_nxt = gain[vi] - ((gain[vi] >> 8) + 17'd1);
                    end else begin
                        div_nxt = div_cnt[vi] + 12'd1;
                    end
                end
                ST_SUSTAIN: begin
                    if (!cur_gate) begin
                        st_nxt  = ST_RELEASE;
                        div_nxt = 12'd0;
                    end else begin
                        gain_nxt = sustain_lvl;
                    end
                end
                ST_RELEASE: begin
                    if (gain[vi] < 17'd256) begin
                        gain_nxt = 17'd0;
                        st_nxt   = ST_IDLE;
                        div_nxt  = 12'd0;
                    end else if (div_cnt[vi] >= {8'd0, release_div}) begin
                        div_nxt  = 12'd0;
                        gain_nxt = gain[vi] - ((gain[vi] >> 8) + 17'd1);
                    end else begin
                        div_nxt = div_cnt[vi] + 12'd1;
                    end
                end
                default: begin
                    gain_nxt = 17'd0;
                    st_nxt   = ST_IDLE;
                end
            endcase
        end

        if (cur_inst == 2'd1) begin
            // Q15 * 2 in the existing Q16 MAC is numerically identical.
            gain_nxt = {guitar_gain[vi][15:0],1'b0};
            st_nxt = ST_IDLE;
            div_nxt = 12'd0;
        end
        phase_nxt = phase[vi] + step[vi];
    end

    // ---------------------------------------------------------
    // sequential engine
    // ---------------------------------------------------------
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            running    <= 1'b0;
            vidx       <= 6'd0;
            sum_acc    <= 40'sd0;
            mix_sum    <= 40'sd0;
            panel_a_sum<=0; panel_b_sum<=0; acc_a<=0; acc_b<=0;
            pipe_panel<=0; rom_panel<=0;
            pipe_valid <= 1'b0;
            rom_valid <= 1'b0;
            rom_gain <= 17'd0;
            pipe_gain  <= 17'd0;
            rom_addr   <= 11'd0;
            for (i = 0; i < NV; i = i + 1) begin
                phase[i]   <= 32'd0;
                step[i]    <= 32'd0;
                gain[i]    <= 17'd0;
                env_st[i]  <= ST_IDLE;
                div_cnt[i] <= 12'd0;
                gate_d[i]  <= 1'b0;
                note_d[i]  <= 8'd0;
                inst_d[i]  <= 3'd0;
            end
        end else begin
            // ---- stage B: multiply-accumulate one voice sample
            if (rom_valid) begin
                sum_acc <= sum_acc + product_q[39:0];
                if(rom_panel) acc_b<=acc_b+product_q[39:0];
                else acc_a<=acc_a+product_q[39:0];
            end
            rom_valid <= pipe_valid;
            rom_panel <= pipe_panel;
            rom_gain <= pipe_gain;
            pipe_valid <= 1'b0;

            if (guitar_tick_d) begin
                running <= 1'b1;
                vidx    <= 6'd0;
                sum_acc <= 40'sd0;
                acc_a<=0;acc_b<=0;
            end else if (running) begin
                // ---- step table write for the voice processed last cycle
                if ((vidx != 6'd0) && (vidx <= NV)) begin
                    step[pv] <= pitch_product[47:16];
                end

                if (vidx < NV) begin
                    // ---- stage A: update one voice
                    phase[vi]   <= phase_nxt;
                    gain[vi]    <= gain_nxt;
                    env_st[vi]  <= st_nxt;
                    div_cnt[vi] <= div_nxt;
                    gate_d[vi]  <= (timbre_change && cur_gate) ? 1'b0 : cur_gate;
                    note_d[vi]  <= cur_note;
                    inst_d[vi]  <= cur_inst;

                    rom_addr   <= {cur_inst, phase_nxt[31:24]};
                    pipe_gain  <= gain_nxt;
                    pipe_valid <= 1'b1;
                    pipe_panel <= vi[4];

                    vidx <= vidx + 6'd1;
                end else if (vidx <= NV + 1) begin
                    // Flush synchronous ROM and delayed gain/valid before committing sum.
                    vidx <= vidx + 6'd1;
                end else begin
                    // ROM and MAC pipeline are now drained.
                    mix_sum <= sum_acc;
                    panel_a_sum<=acc_a;panel_b_sum<=acc_b;
                    running <= 1'b0;
                end
            end
        end
    end

endmodule

`default_nettype wire

