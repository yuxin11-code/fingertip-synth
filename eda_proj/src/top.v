module top #(
    parameter integer ENABLE_DUAL_PANEL = 1, // 0: original; 1: dual-panel 32 voices
    parameter integer SYNTH_MODE = 1, // 0: original 32 wavetable; 1: 512 additive
    parameter integer T_MIN=-4,
    parameter integer T_MAX=4,
    parameter integer RECORD_DEPTH=32768,
    parameter integer LOOP_PLAYBACK=0,GUIDE_PART=0,GUIDE_RIGHT_PANEL=0
)(
    input wire K_LEFT, K_RIGHT, K_AUX3, K_AUX4, TEST_MODE_KEY,
    input wire UART_RX,
    input wire BLE_RX,
    output wire BLE_TX,
    inout wire KNOB_SCL,KNOB_SDA,
    input wire OCT_A,OCT_B,OCT_SW_N,
    input wire TTP_R_SDO,
    output wire TTP_R_SCL, UART_TX,
    input  wire rst,
    input  wire KEY1,
    input  wire KEY2,
    input  wire TIMBRE_KEY,
    input  wire TTP229_SDO,
    input  wire ENC_A,
    input  wire ENC_B,
    input  wire ENC_C,
    input  wire PITCH_UP_KEY,
    input  wire PITCH_DOWN_KEY,

    inout  wire PAJ_SCL,
    inout  wire PAJ_SDA,

    output wire TTP229_SCL,
    output wire HP_BCK,
    output wire HP_WS,
    output wire HP_DIN,
    output wire PA_EN,
    output wire WS2812_DIN
);
    wire        score_receiving;
    wire        score_valid;
    wire        score_receive_error;
    wire [15:0] score_received_count;
    wire [15:0] score_note_count;
    wire [15:0] score_bpm;
    wire [15:0] score_ticks_per_beat;
    wire [31:0] score_length_ticks;
    wire [7:0] score_read_address;
    wire score_read_enable;
    wire [87:0] score_read_data;
    wire score_import_request;
    wire [48:0] screen_data;
    wire screen_clk;
    wire screen_rst_n = !rst;
    generate if (ENABLE_DUAL_PANEL == 0) begin : g_legacy
    assign score_import_request=1'b0;
    assign BLE_TX=1'b1; // The legacy UI has no score-request button.
    assign KNOB_SCL=1'bz;
    assign KNOB_SDA=1'bz;


    wire clk;
    wire rst_n = !rst;
    wire clk_6m_w;
    wire clk_1p5m_w;
    wire req_w;

    wire [15:0] touch_keys_raw;
    wire [15:0] touch_keys;

    wire [1:0] timbre_select;
    wire rotate_cw;
    wire rotate_ccw;
    wire select_pulse;
    wire [1:0] selected_stage;
    wire [15:0] attack_step;
    wire [15:0] sustain_level;
    wire [3:0] decay_divider_limit;
    wire [3:0] release_divider_limit;
    wire [17:0] pitch_scale_q16;

    wire paj_right_pulse;
    wire paj_left_pulse;
    wire paj_gesture_valid;
    wire [3:0] paj_gesture_code;
    wire paj_init_ok;
    wire paj_sensor_error;

    wire [3:0] direct_voice_gate;
    wire [6:0] direct_voice0_note;
    wire [6:0] direct_voice1_note;
    wire [6:0] direct_voice2_note;
    wire [6:0] direct_voice3_note;

    wire [3:0] strum_voice_gate;
    wire [6:0] strum_voice0_note;
    wire [6:0] strum_voice1_note;
    wire [6:0] strum_voice2_note;
    wire [6:0] strum_voice3_note;

    wire guitar_strum_mode = (timbre_select == 2'd3);
    wire [3:0] voice_gate = guitar_strum_mode
                          ? strum_voice_gate : direct_voice_gate;
    wire [6:0] voice0_note = guitar_strum_mode
                           ? strum_voice0_note : direct_voice0_note;
    wire [6:0] voice1_note = guitar_strum_mode
                           ? strum_voice1_note : direct_voice1_note;
    wire [6:0] voice2_note = guitar_strum_mode
                           ? strum_voice2_note : direct_voice2_note;
    wire [6:0] voice3_note = guitar_strum_mode
                           ? strum_voice3_note : direct_voice3_note;

    wire signed [31:0] voice_sum;
    wire signed [31:0] volume_sample;
    wire [16:0] volume_q16;
    wire signed [15:0] i2s_sample;

    Gowin_OSC osc50m(.oscout(clk));
    Gowin_PLL pll52p5_to_6m(.clkout0(clk_6m_w), .clkin(clk));
    Gowin_CLKDIV clk_div4(
        .clkout(clk_1p5m_w), .hclkin(clk_6m_w), .resetn(rst_n)
    );

    ttp229_serial16 #(
        .CLK_HZ(1500000), .SCL_HZ(20000), .ACTIVE_LOW(1)
    ) touch_reader(
        .clk(clk_1p5m_w), .rst_n(rst_n),
        .sdo(TTP229_SDO), .scl(TTP229_SCL),
        .touch_keys(touch_keys_raw), .frame_valid(), .busy()
    );

    assign touch_keys = touch_keys_raw;

    ws2812_status #(
        .CLK_HZ(52500000),
        .IDLE_COLOR(24'h000020),
        .ON_COLOR(24'h002000)
    ) touch16_status_led(
        .clk(clk), .rst_n(rst_n),
        .status_on(!PITCH_UP_KEY), .data_out(WS2812_DIN)
    );

    timbre_select_control timbre_control(
        .clk(clk_1p5m_w), .rst_n(rst_n),
        .key_n(TIMBRE_KEY), .timbre_select(timbre_select)
    );

    rotary_encoder_decoder #(.CLK_HZ(1500000)) encoder_decoder(
        .clk(clk_1p5m_w), .rst_n(rst_n),
        .enc_a(ENC_A), .enc_b(ENC_B), .enc_key_n(ENC_C),
        .rotate_cw(rotate_cw), .rotate_ccw(rotate_ccw),
        .select_pulse(select_pulse)
    );

    adsr_parameter_control adsr_control(
        .clk(clk_1p5m_w), .rst_n(rst_n),
        .timbre_select(timbre_select),
        .rotate_cw(rotate_cw), .rotate_ccw(rotate_ccw),
        .select_pulse(select_pulse), .selected_stage(selected_stage),
        .attack_step(attack_step),
        .decay_divider_limit(decay_divider_limit),
        .sustain_level(sustain_level),
        .release_divider_limit(release_divider_limit)
    );
    pitch_key_control #(
        .CLK_HZ(1500000),
        .DEBOUNCE_MS(5),
        .LONG_PRESS_MS(200),
        .RAMP_INTERVAL_MS(1),
        .RAMP_STEP(16)
    ) pitch_key_control_inst (
        .clk(clk_1p5m_w),
        .rst_n(rst_n),
        .key_up_n(PITCH_UP_KEY),
        .key_down_n(PITCH_DOWN_KEY),
        .pitch_scale_q16(pitch_scale_q16)
    );

    paj7620_controller #(.CLK_HZ(1500000)) paj_controller(
        .clk(clk_1p5m_w), .rst_n(rst_n),
        .paj_scl(PAJ_SCL), .paj_sda(PAJ_SDA),
        .right_pulse(paj_right_pulse),
        .left_pulse(paj_left_pulse),
        .gesture_valid(paj_gesture_valid),
        .gesture_code(paj_gesture_code),
        .init_ok(paj_init_ok), .sensor_error(paj_sensor_error)
    );

    // Sine, triangle and piano keep direct four-voice touch behavior.
    instrument_voice_allocator4 direct_allocator(
        .clk(clk_1p5m_w), .rst_n(rst_n), .touch_keys(touch_keys),
        .voice_gate(direct_voice_gate),
        .voice0_note(direct_voice0_note),
        .voice1_note(direct_voice1_note),
        .voice2_note(direct_voice2_note),
        .voice3_note(direct_voice3_note)
    );

    // In guitar timbre, held touch keys select the chord. Horizontal PAJ7620
    // gestures start its notes one after another.
    gesture_strum_control #(
    .CLK_HZ(1500000), .STRUM_GAP_MS(30), .NOTE_GATE_MS(220)
    ) strum_control(
        .clk(clk_1p5m_w), .rst_n(rst_n),
        .enable(guitar_strum_mode && paj_init_ok && !paj_sensor_error),
        .touch_keys(touch_keys),
        .strum_right(paj_right_pulse), .strum_left(paj_left_pulse),
        .voice_gate(strum_voice_gate),
        .voice0_note(strum_voice0_note),
        .voice1_note(strum_voice1_note),
        .voice2_note(strum_voice2_note),
        .voice3_note(strum_voice3_note)
    );

    instrument_four_voice_bank four_voice_bank(
        .clk(clk_1p5m_w), .rst_n(rst_n), .sample_enable(req_w),
        .voice_gate(voice_gate),
        .voice0_note(voice0_note), .voice1_note(voice1_note),
        .voice2_note(voice2_note), .voice3_note(voice3_note),
        .pitch_scale_q16(pitch_scale_q16),
        .timbre_select(timbre_select), .attack_step(attack_step),
        .decay_divider_limit(decay_divider_limit),
        .sustain_level(sustain_level),
        .release_divider_limit(release_divider_limit),
        .sample_sum(voice_sum)
    );

    volume_control volume_control_inst(
        .clk(clk_1p5m_w), .rst_n(rst_n),
        .key_up_n(KEY1), .key_down_n(KEY2), .volume_q16(volume_q16)
    );

    volume_scale volume_scale_inst(
        .sample_in(voice_sum), .gain_q16(volume_q16),
        .sample_out(volume_sample)
    );

    instrument_mixer_limiter mixer_limiter(
        .sample_in(volume_sample), .sample_out(i2s_sample)
    );

    assign PA_EN = 1'b0;

    audio_drive i2s_output(
        .clk_1p536m(clk_1p5m_w), .rst_n(rst_n), .idata(i2s_sample),
        .req(req_w), .HP_BCK(HP_BCK), .HP_WS(HP_WS), .HP_DIN(HP_DIN)
    );


    // Legacy sound/control RTL above is unchanged. Only observe its state.
    assign TTP_R_SCL = 1'b1;
    assign screen_clk = clk;
    wire [2:0] screen_inst = (timbre_select==0) ? 3'd2 :
                             (timbre_select==1) ? 3'd3 :
                             (timbre_select==2) ? 3'd0 : 3'd1;
    wire [5:0] screen_count = {5'd0,voice_gate[0]} + {5'd0,voice_gate[1]} +
                              {5'd0,voice_gate[2]} + {5'd0,voice_gate[3]};
    wire [3:0] screen_attack = (attack_step>=16'd4096) ? 4'd15 : attack_step[11:8];
    wire [48:0] legacy_status = {screen_inst,screen_inst,screen_count,volume_q16,
        screen_attack,decay_divider_limit,sustain_level[15:12],release_divider_limit,
        1'b0,(guitar_strum_mode && (|strum_voice_gate)),2'b00};
    mig_cdc_snapshot #(.WIDTH(49)) status_bridge(
        .src_clk(clk_1p5m_w),.dst_clk(clk),.rst_n(rst_n),
        .src_data(legacy_status),.dst_data(screen_data));
    end else begin : g_dual
        wire clk_sys,clk_6m,clk_aud;
        wire reset_button_n = !rst;
        reg [2:0] reset_release = 0;
        always @(posedge clk_sys or negedge reset_button_n) begin
            if(!reset_button_n) reset_release<=0;
            else reset_release<={reset_release[1:0],1'b1};
        end
        wire reset_n=reset_release[2];
        Gowin_OSC osc(.oscout(clk_sys));
        Gowin_PLL pll(.clkout0(clk_6m),.clkin(clk_sys));
        Gowin_CLKDIV div4(.clkout(clk_aud),.hclkin(clk_6m),.resetn(reset_n));
        assign screen_clk=clk_sys;
        mig_dual_instrument #(.SYNTH_MODE(SYNTH_MODE),.T_MIN(T_MIN),.T_MAX(T_MAX),.RECORD_DEPTH(RECORD_DEPTH),.LOOP_PLAYBACK(LOOP_PLAYBACK),.GUIDE_PART(GUIDE_PART),.GUIDE_RIGHT_PANEL(GUIDE_RIGHT_PANEL)) instrument(
            .score_valid(score_valid),.score_receiving(score_receiving),.score_receive_error(score_receive_error),
            .score_note_count(score_note_count),.score_received_count(score_received_count),.score_bpm(score_bpm),.score_ticks_per_beat(score_ticks_per_beat),
            .score_length_ticks(score_length_ticks),.score_read_data(score_read_data),.score_read_enable(score_read_enable),.score_read_address(score_read_address),
            .score_import_request(score_import_request),
            .UART_RX(UART_RX),.UART_TX(UART_TX),.BLE_TX(BLE_TX),
            .clk_sys(clk_sys),.clk_aud(clk_aud),.rst_n(reset_n),
            .KEY1(KEY1),.KEY2(KEY2),.TIMBRE_KEY(TIMBRE_KEY),.ENC_A(ENC_A),.ENC_B(ENC_B),.ENC_C(ENC_C),
            .OCT_A(OCT_A),.OCT_B(OCT_B),.OCT_SW_N(OCT_SW_N),
            .KNOB_SCL(KNOB_SCL),.KNOB_SDA(KNOB_SDA),
            .PITCH_UP_KEY(PITCH_UP_KEY),.PITCH_DOWN_KEY(PITCH_DOWN_KEY),
            .K_LEFT(K_LEFT),.K_RIGHT(K_RIGHT),.K_AUX3(K_AUX3),.K_AUX4(K_AUX4),.TEST_MODE_KEY(TEST_MODE_KEY),
            .TTP229_SDO(TTP229_SDO),.TTP_R_SDO(TTP_R_SDO),
            .PAJ_SCL(PAJ_SCL),.PAJ_SDA(PAJ_SDA),.TTP229_SCL(TTP229_SCL),.TTP_R_SCL(TTP_R_SCL),
            .HP_BCK(HP_BCK),.HP_WS(HP_WS),.HP_DIN(HP_DIN),.PA_EN(PA_EN),.WS2812_DIN(WS2812_DIN),
            .status_data(screen_data));
    end endgenerate

    wire [2:0] scr_l,scr_r;
    wire [5:0] scr_count;
    wire [16:0] scr_volume;
    wire [3:0] scr_a,scr_d,scr_s,scr_release;
    wire scr_test,scr_strum,scr_aux3,scr_aux4,scr_busy,scr_start;
    wire [7:0] scr_byte;
    assign {scr_l,scr_r,scr_count,scr_volume,scr_a,scr_d,scr_s,scr_release,scr_test,scr_strum,scr_aux3,scr_aux4}=screen_data;
    generate if(ENABLE_DUAL_PANEL==0)begin: legacy_screen_only
    mig_screen_status #(.LEGACY_MODE(ENABLE_DUAL_PANEL==0)) screen(
        .clk(screen_clk),.rst_n(screen_rst_n),.inst_l(scr_l),.inst_r(scr_r),.active_voices(scr_count),
        .volume_q16(scr_volume),.adsr_a(scr_a),.adsr_d(scr_d),.adsr_s(scr_s),.adsr_r(scr_release),
        .test_mode(scr_test),.strum_active(scr_strum),.aux3_stable(scr_aux3),.aux4_stable(scr_aux4),
        .uart_busy(scr_busy),.uart_start(scr_start),.uart_data(scr_byte));
    mig_uart_tx uart(.clk(screen_clk),.rst_n(screen_rst_n),.start(scr_start),.data(scr_byte),.tx(UART_TX),.busy(scr_busy));
    end endgenerate
    // --------------------------------------------------------
    // ESP32���״��ڽ���
    // screen_clk�ڵ�ǰ���������ӵ�52.5 MHzϵͳʱ�ӡ�
    // --------------------------------------------------------

    // �첽���븴λ��ͬ�������λ��
    // ��ֵ0ͬʱ�ý���ģ����FPGA����ʱ��������ʱ�ӵĸ�λ��
    reg [2:0] score_reset_release = 3'b000;
    reg [2:0] score_loader_reset_release = 3'b000;

    // Retain a previously validated score until the ESP32 starts a new one.
    // Request/retry resets only UART/framing, so a partial old packet cannot
    // consume the beginning of the new START response.
    always @(posedge screen_clk or posedge rst) begin
        if (rst)
            score_loader_reset_release <= 3'b000;
        else
            score_loader_reset_release <= {score_loader_reset_release[1:0], 1'b1};
    end

    always @(posedge screen_clk or posedge rst) begin
        if (rst)
            score_reset_release <= 3'b000;
        else if (score_import_request)
            // Import/retry clears partial UART packets, preserving metadata.
            // Release remains synchronized through the existing three stages.
            score_reset_release <= 3'b000;
        else
            score_reset_release <=
                {score_reset_release[1:0], 1'b1};
    end

    wire score_rst_n = score_reset_release[2];
    wire score_loader_rst_n = score_loader_reset_release[2];

    wire [7:0] score_rx_data;
    wire       score_rx_valid;
    wire       score_rx_error;

    score_uart_rx #(
        .CLK_HZ(52500000),
        .BAUD(115200)
    ) u_score_uart_rx (
        .clk(screen_clk),
        .rst_n(score_rst_n),
        .rx(BLE_RX),

        .rx_data(score_rx_data),
        .rx_valid(score_rx_valid),
        .frame_error(score_rx_error)
    );
    // ---------- �������ݰ� ----------
    wire        score_packet_valid;
    wire        score_packet_error;
    wire [7:0]  score_packet_type;
    wire [15:0] score_packet_seq;
    wire [7:0]  score_packet_len;
    wire [95:0] score_payload;

    score_frame_rx #(
        .CLK_HZ(52500000)
    ) u_score_frame_rx (
        .clk(screen_clk),
        .rst_n(score_rst_n),
        .rx_data(score_rx_data),
        .rx_valid(score_rx_valid),
        .rx_error(score_rx_error),

        .packet_valid(score_packet_valid),
        .packet_error(score_packet_error),
        .packet_type(score_packet_type),
        .packet_seq(score_packet_seq),
        .packet_len(score_packet_len),
        .payload(score_payload)
    );

    // ---------- ���׽���״̬��Ԫ���� ----------








    wire        score_ram_we;
    wire [7:0]  score_ram_waddr;
    wire [87:0] score_ram_wdata;

    score_loader #(
        .CLK_HZ(52500000)
    ) u_score_loader (
        .clk(screen_clk),
        .rst_n(score_loader_rst_n),
        .packet_valid(score_packet_valid),
        .packet_error(score_packet_error),
        .packet_type(score_packet_type),
        .packet_seq(score_packet_seq),
        .packet_len(score_packet_len),
        .payload(score_payload),

        .receiving(score_receiving),
        .score_valid(score_valid),
        .receive_error(score_receive_error),
        .received_count(score_received_count),

        .note_count(score_note_count),
        .bpm(score_bpm),
        .ticks_per_beat(score_ticks_per_beat),
        .length_ticks(score_length_ticks),

        .ram_we(score_ram_we),
        .ram_waddr(score_ram_waddr),
        .ram_wdata(score_ram_wdata)
    );

    // ---------- ���״洢 ----------
    // ��ʱ�̶���ȡ��0����������������۲졣
    // ������ϰģ�������ϰģ�������ַ�Ͷ�ʹ�ܡ�


    generate if(ENABLE_DUAL_PANEL==0)begin: legacy_score_read
      assign score_read_enable=1'b0;assign score_read_address=8'd0;
    end endgenerate

    score_ram u_score_ram (
        .clk(screen_clk),
        .we(score_ram_we),
        .waddr(score_ram_waddr),
        .wdata(score_ram_wdata),

        .rd_en(score_read_enable),
        .raddr(score_read_address),
        .rdata(score_read_data)
    );
endmodule
