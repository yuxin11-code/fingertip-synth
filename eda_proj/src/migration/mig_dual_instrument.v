// New dual-panel path; existing four-voice path stays in top.g_legacy.
module mig_dual_instrument #(
 parameter integer CLK_HZ=52500000,
 parameter integer SYNTH_MODE=1,
 parameter integer T_MIN=-4,
 parameter integer T_MAX=4,
 parameter integer RECORD_DEPTH=32768,LOOP_PLAYBACK=0,GUIDE_PART=0,GUIDE_RIGHT_PANEL=0
)(
 input wire clk_sys,clk_aud,rst_n,
 input wire UART_RX,output wire UART_TX,output wire BLE_TX,
 input wire score_valid,score_receiving,score_receive_error,
 input wire [15:0] score_note_count,score_received_count,score_bpm,score_ticks_per_beat,
 input wire [31:0] score_length_ticks,input wire [87:0] score_read_data,
 output wire score_read_enable,output wire [7:0] score_read_address,
 output wire score_import_request,
 inout wire KNOB_SCL,KNOB_SDA,
 input wire OCT_A,OCT_B,OCT_SW_N,
 input wire KEY1,KEY2,TIMBRE_KEY,ENC_A,ENC_B,ENC_C,PITCH_UP_KEY,PITCH_DOWN_KEY,
 input wire K_LEFT,K_RIGHT,K_AUX3,K_AUX4,TEST_MODE_KEY,TTP229_SDO,TTP_R_SDO,
 inout wire PAJ_SCL,PAJ_SDA,
 output wire TTP229_SCL,TTP_R_SCL,HP_BCK,HP_WS,HP_DIN,PA_EN,WS2812_DIN,
 output wire [48:0] status_data
);
 `include "hmi_defs.vh"
 wire [15:0] keys_left,keys_right;
 wire [7:0] rx_byte,cmd;
 wire rx_valid,rx_error,cmd_valid;
 wire hmi_frame_valid,hmi_frame_invalid,hmi_page_valid,hmi_screen_reset;wire [15:0] hmi_page_id;
 wire hmi_link_online,hmi_link_lost;
 wire [15:0] cmd_value;
 wire score_request_busy;
 reg score_import_pending,score_import_started;
 // An accepted request hides any old score until a new START/END transfer
 // commits.  The loader retains its old metadata until START arrives.
 always @(posedge clk_sys or negedge rst_n)begin
  if(!rst_n)begin score_import_pending<=0;score_import_started<=0;end
  else if(score_import_request)begin
   score_import_pending<=1;score_import_started<=0;
  end else if(score_import_pending)begin
   if(score_receiving)score_import_started<=1;
   if(score_import_started && score_valid && !score_receiving)begin
    score_import_pending<=0;score_import_started<=0;
   end
  end
 end
 hmi_uart_rx #(.CLK_HZ(CLK_HZ)) receiver(.clk(clk_sys),.rst_n(rst_n),.rx(UART_RX),.data(rx_byte),.valid(rx_valid),.frame_error(rx_error));
 hmi_rx #(.CLK_HZ(CLK_HZ)) parser(.selected_panel(selected_panel),.clear_keys(hmi_link_lost),.clk(clk_sys),.rst_n(rst_n),.byte_valid(rx_valid),.frame_error(rx_error),.byte_data(rx_byte),.cmd_valid(cmd_valid),.cmd(cmd),.value(cmd_value),.frame_valid(hmi_frame_valid),.frame_invalid(hmi_frame_invalid),.page_valid(hmi_page_valid),.page_id(hmi_page_id),.screen_reset(hmi_screen_reset));
 mig_hmi_link #(.CLK_HZ(CLK_HZ)) hmi_link(.clk(clk_sys),.rst_n(rst_n),
  .screen_reset(hmi_screen_reset),.response_valid(hmi_page_valid),
  .online(hmi_link_online),.lost(hmi_link_lost));
 wire game_active,game_ctrl_valid;wire [7:0] game_ctrl_cmd;wire [15:0] game_ctrl_value;
 wire [47:0] game_lamps;wire [15:0] game_score,game_combo;wire [6:0] game_accuracy,game_progress,game_state;
 reg [15:0] screen_left,screen_right;
 reg selected_panel_q;
 always @(posedge clk_sys or negedge rst_n)begin
  if(!rst_n)begin screen_left<=0;screen_right<=0;selected_panel_q<=0;end
  else begin
   selected_panel_q<=selected_panel;
   if(hmi_screen_reset || hmi_link_lost || selected_panel_q!=selected_panel || game_active)begin screen_left<=0;screen_right<=0;end
  else if(cmd_valid)begin
   if(cmd==8'h30)screen_left<=cmd_value;
   if(cmd==8'h31)screen_right<=cmd_value;
   if((cmd==8'h1f && cmd_value!=1) || cmd==8'h15)begin screen_left<=0;screen_right<=0;end
  end
  end
 end
 wire paj_right,paj_left,paj_ok,paj_error,paj_gesture_valid;
 wire [3:0] paj_gesture_code;
 wire frame_tick;
 wire [31:0] voice_gate;
 wire aux3_stable,aux4_stable;
 wire [31:0] replay_keys;
 wire [31:0] combined_gate=voice_gate | (game_active?32'd0:replay_keys);
 wire recording,playing,record_full;
 wire RECORD_LED,PLAY_LED;
 wire [$clog2(RECORD_DEPTH):0] record_length;
 wire loop_enabled;
 wire [31:0] duration_ms,elapsed_ms;
 mig_action_recorder #(.CLK_HZ(CLK_HZ),.DEPTH(RECORD_DEPTH),.LOOP_PLAYBACK(LOOP_PLAYBACK)) recorder(
  .hmi_valid(cmd_valid),.hmi_cmd(cmd),.hmi_value(cmd_value),.loop_enabled(loop_enabled),.duration_ms(duration_ms),.elapsed_ms(elapsed_ms),
  .clk(clk_sys),.rst_n(rst_n),.suspend(game_active),.record_n(K_AUX3),.play_n(K_AUX4),.live_keys(voice_gate),
  .replay_keys(replay_keys),.record_stable(aux3_stable),.play_stable(aux4_stable),
  .recording(recording),.playing(playing),.record_led(RECORD_LED),.play_led(PLAY_LED),
  .full(record_full),.length(record_length));
 wire [255:0] voice_note;
 wire [95:0] voice_inst;
 wire [16:0] volume_q16;
 wire [17:0] pitch_scale_q16;
 wire [3:0] adsr_a,adsr_d,adsr_s,adsr_r;
 wire [15:0] guitar_attack,guitar_sustain;
 wire [3:0] guitar_decay,guitar_release;
 wire [5:0] active_voices;
 wire test_mode,strum_active,pluck_mode;
 wire [2:0] inst_l,inst_r;
 wire signed [7:0] transpose_left,transpose_right;
 wire selected_panel;
 wire [2:0] adsr_edit_instrument=selected_panel?inst_r:inst_l;
 wire adsr_edit_allowed=(SYNTH_MODE==0) ||
  ((cmd!=8'h0b && cmd!=8'h0d) || adsr_edit_instrument==2) &&
  (cmd!=8'h0c || adsr_edit_instrument!=2);
 mig_octave_control #(.CLK_HZ(CLK_HZ),.T_MIN(T_MIN),.T_MAX(T_MAX)) octave_control(
  .hmi_valid(cmd_valid),.hmi_cmd(cmd),.hmi_value(cmd_value),
  .clk(clk_sys),.rst_n(rst_n),.enc_a(OCT_A),.enc_b(OCT_B),.enc_sw_n(OCT_SW_N),
  .selected_panel(selected_panel),.transpose_left(transpose_left),.transpose_right(transpose_right));
 wire signed [39:0] mix_sum;
 wire signed [15:0] pcm;
 wire signed [15:0] pcm_right;
 wire signed [39:0] panel_a_sum,panel_b_sum;
 wire [39:0] env_observe;
 wire [16:0] master,blend,balance;
 wire [17:0] modulated_pitch;
 wire [5:0] knob_write_mask;
 wire [101:0] knob_write_values;
 wire [127:0] knob_raw_values;
 wire [95:0] calibration_low,calibration_high;
 wire [84:0] knob_targets,knob_actual;
 wire volume_up_event,volume_down_event;
 wire knob_snapshot_valid,knob_online;
 wire [15:0] knob_error_count;
 mig_rp108_reader #(.CLK_HZ(CLK_HZ)) rp108(
  .clk(clk_sys),.rst_n(rst_n),.scl(KNOB_SCL),.sda(KNOB_SDA),
  .raw_values(knob_raw_values),.snapshot_valid(knob_snapshot_valid),
  .online(knob_online),.error_count(knob_error_count));
 mig_knob_normalize normalize(.clk(clk_sys),.rst_n(rst_n),
  .calibration_low(calibration_low),.calibration_high(calibration_high),
  .raw_values(knob_raw_values),.snapshot_valid(knob_snapshot_valid),
  .write_mask(knob_write_mask),.write_values(knob_write_values));
 mig_six_knobs knobs(.clk(clk_sys),.rst_n(rst_n),.frame_tick(frame_tick),
  .hmi_valid(cmd_valid),.hmi_cmd(cmd),.hmi_value(cmd_value),
  .volume_up_event(volume_up_event),.volume_down_event(volume_down_event),
  .raw_values(knob_raw_values[95:0]),.calibration_low(calibration_low),.calibration_high(calibration_high),
  .targets(knob_targets),.actual_values(knob_actual),
  .write_mask(knob_write_mask),.write_values(knob_write_values),
  .fallback_volume(volume_q16),.base_pitch(pitch_scale_q16),
  .master(master),.blend(blend),.balance(balance),.modulated_pitch(modulated_pitch));

 // Both complete touch vectors and gestures are produced in clk_sys.
 ttp229_serial16 #(.CLK_HZ(CLK_HZ),.SCL_HZ(20000),.ACTIVE_LOW(1)) left_touch(
  .clk(clk_sys),.rst_n(rst_n),.sdo(TTP229_SDO),.scl(TTP229_SCL),
  .touch_keys(keys_left),.frame_valid(),.busy());
 ttp229_serial16 #(.CLK_HZ(CLK_HZ),.SCL_HZ(20000),.ACTIVE_LOW(1)) right_touch(
  .clk(clk_sys),.rst_n(rst_n),.sdo(TTP_R_SDO),.scl(TTP_R_SCL),
  .touch_keys(keys_right),.frame_valid(),.busy());
 paj7620_controller #(.CLK_HZ(CLK_HZ)) gesture(
  .clk(clk_sys),.rst_n(rst_n),.paj_scl(PAJ_SCL),.paj_sda(PAJ_SDA),
  .right_pulse(paj_right),.left_pulse(paj_left),.gesture_valid(paj_gesture_valid),.gesture_code(paj_gesture_code),
  .init_ok(paj_ok),.sensor_error(paj_error));
 reg [3:0] last_gesture_code;
 reg [1:0] last_gesture_panels;
 always @(posedge clk_sys or negedge rst_n)begin
  if(!rst_n)begin last_gesture_code<=0;last_gesture_panels<=0;end
  else if(paj_gesture_valid)begin
   last_gesture_code<=paj_gesture_code;
   last_gesture_panels<={|keys_right,|keys_left};
  end
 end
 mig_input_ctrl #(.CLK_HZ(CLK_HZ)) controls(
  .test_suspend(game_active),.hmi_valid(game_ctrl_valid && adsr_edit_allowed),.hmi_cmd(game_ctrl_cmd),.hmi_value(game_ctrl_value),
  .volume_up_event(volume_up_event),.volume_down_event(volume_down_event),
  .selected_panel(selected_panel),
  .clk(clk_sys),.rst_n(rst_n),.frame_tick(frame_tick),
  .keys_left(keys_left | (game_active?16'd0:screen_left)),.keys_right(keys_right | (game_active?16'd0:screen_right)),
  .strum_right(paj_right && paj_ok && !paj_error),
  .strum_left(paj_left && paj_ok && !paj_error),
  .key_up_n(KEY1),.key_dn_n(KEY2),.inst_left_n(K_LEFT),.inst_right_n(K_RIGHT),
  .test_toggle_n(TEST_MODE_KEY),.aux3_n(1'b1),.aux4_n(1'b1),
  .pluck_toggle_n(TIMBRE_KEY),.pluck_mode(pluck_mode),
  .enc_a(ENC_A),.enc_b(ENC_B),.enc_c_n(ENC_C),
  .transpose_left(transpose_left),.transpose_right(transpose_right),
  .voice_gate(voice_gate),.voice_note(voice_note),.voice_inst(voice_inst),
  .volume_q16(volume_q16),.adsr_a(adsr_a),.adsr_d(adsr_d),.adsr_s(adsr_s),.adsr_r(adsr_r),
  .active_voices(),.test_mode(test_mode),.strum_active(strum_active),
  .inst_l(inst_l),.inst_r(inst_r),.aux3_stable(),.aux4_stable(),
  .guitar_attack(guitar_attack),.guitar_sustain(guitar_sustain),
  .guitar_decay(guitar_decay),.guitar_release(guitar_release));
 wire signed [4:0] semitone;
 wire pitch_approximate;
 pitch_key_control #(.CLK_HZ(CLK_HZ),.DEBOUNCE_MS(5),.LONG_PRESS_MS(200),
  .RAMP_INTERVAL_MS(1),.RAMP_STEP(16)) pitch(
  .hmi_valid(cmd_valid),.hmi_cmd(cmd),.hmi_value(cmd_value),.semitone(semitone),.approximate(pitch_approximate),
  .clk(clk_sys),.rst_n(rst_n),.key_up_n(PITCH_UP_KEY),.key_down_n(PITCH_DOWN_KEY),
  .pitch_scale_q16(pitch_scale_q16));
 wire [9:0] active_osc;
 wire [5:0] sounding_voices;
 wire engine_sample_valid;
 wire engine_busy,engine_ready,engine_deadline_error;
 wire [11:0] last_frame_cycles;
 wire [31:0] deadline_count,sample_count;
 mig_engine_diagnostics diagnostics(.clk(clk_sys),.rst_n(rst_n),.frame_tick(frame_tick),
  .busy(engine_busy),.sample_valid(engine_sample_valid),
  .last_frame_cycles(last_frame_cycles),.deadline_count(deadline_count),.sample_count(sample_count));
 reg [15:0] legacy_tick_delay;
 always @(posedge clk_sys or negedge rst_n)begin
  if(!rst_n)legacy_tick_delay<=0;
  else legacy_tick_delay<={legacy_tick_delay[14:0],frame_tick};
 end
 reg [2:0] ui_fx_enable;
 reg [9:0] ui_fx_param[0:8];
 generate if(SYNTH_MODE==1)begin:g_additive
  // UI retains its 16 detents. Replicate the nibble to cover exactly 0..255.
  mig_additive_engine voices(.clk(clk_sys),.rst_n(rst_n),.frame_tick(frame_tick),
   .v_gate(combined_gate),.v_note(voice_note),.v_inst(voice_inst),.pitch_scale_q16(modulated_pitch),
   .a_param({adsr_a,adsr_a}),.d_param({adsr_d,adsr_d}),
   .s_param({adsr_s,adsr_s}),.r_param({adsr_r,adsr_r}),
   .guitar_d_param({guitar_decay,guitar_decay}),.guitar_r_param({guitar_release,guitar_release}),
   .mix_sum(mix_sum),.panel_a_sum(panel_a_sum),.panel_b_sum(panel_b_sum),
   .env_observe(env_observe),.active_osc(active_osc),.sounding_voices(sounding_voices),
   .busy(engine_busy),.ready(engine_ready),
   .sample_valid(engine_sample_valid),.deadline_error(engine_deadline_error));
 end else begin:g_wavetable
 mig_voice_engine voices(.clk(clk_sys),.rst_n(rst_n),.frame_tick(frame_tick),
  .v_gate(combined_gate),.v_note(voice_note),.v_inst(voice_inst),.pitch_scale_q16(modulated_pitch),
  .guitar_attack(guitar_attack),.guitar_sustain(guitar_sustain),
  .guitar_decay(guitar_decay),.guitar_release(guitar_release),
  .a_param(adsr_a),.d_param(adsr_d),.s_param(adsr_s),.r_param(adsr_r),.mix_sum(mix_sum),
  .panel_a_sum(panel_a_sum),.panel_b_sum(panel_b_sum),.env_observe(env_observe));
  assign active_osc={4'd0,active_voices};
  assign sounding_voices=active_voices;
  assign engine_sample_valid=legacy_tick_delay[15];
  assign engine_busy=1'b0;
  assign engine_ready=1'b1;
  assign engine_deadline_error=1'b0;
 end endgenerate
 function signed [15:0] fx_input;
  input signed [39:0] value;
  reg signed [39:0] shifted;
  begin
   shifted=value>>>2;
   fx_input=(shifted>32767)?16'sd32767:(shifted< -32768)?-16'sd32768:shifted[15:0];
  end
 endfunction
 function [1:0] fx_detent;
  input [9:0] value;
  begin fx_detent=(value<250)?2'd0:(value<500)?2'd1:(value<750)?2'd2:2'd3;end
 endfunction
 wire signed [15:0] fx_left,fx_right;
 wire fx_ready,fx_busy,fx_sample_valid,fx_active;
 reg fx_has_sample;
 always @(posedge clk_sys or negedge rst_n)begin
  if(!rst_n)fx_has_sample<=0;
  else if(fx_sample_valid)fx_has_sample<=1;
 end
 fx_chain #(.CLK_HZ(CLK_HZ)) effects(
  .clk(clk_sys),.rst_n(rst_n),.frame_tick(engine_sample_valid),
  .dry_l(fx_input(panel_a_sum)),.dry_r(fx_input(panel_b_sum)),
  .rev_en(ui_fx_enable[0]),.rev_decay(fx_detent(ui_fx_param[0])),
  .rev_damp(fx_detent(ui_fx_param[1])),.rev_mix(fx_detent(ui_fx_param[6])),
  .dly_en(ui_fx_enable[1]),.dly_time(fx_detent(ui_fx_param[2])),
  .dly_fb(fx_detent(ui_fx_param[3])),.dly_mix(fx_detent(ui_fx_param[7])),
  .cho_en(ui_fx_enable[2]),.cho_rate(fx_detent(ui_fx_param[4])),
  .cho_depth(fx_detent(ui_fx_param[5])),.cho_mix(fx_detent(ui_fx_param[8])),
  .wet_l(fx_left),.wet_r(fx_right),.fx_active(fx_active),
  .ready(fx_ready),.busy(fx_busy),.sample_valid(fx_sample_valid));
 wire signed [39:0] mixed_panel_a=(fx_active && fx_has_sample)?{{22{fx_left[15]}},fx_left,2'b00}:panel_a_sum;
 wire signed [39:0] mixed_panel_b=(fx_active && fx_has_sample)?{{22{fx_right[15]}},fx_right,2'b00}:panel_b_sum;
 mig_stereo_mixer #(.EQUAL_POWER(1),.BOOST_MASTER(1)) mixer(.clk(clk_sys),.rst_n(rst_n),.panel_a(mixed_panel_a),.panel_b(mixed_panel_b),
  .master(master),.blend(blend),.balance(balance),.test_atten(test_mode && !game_active),
  .pcm_left(pcm),.pcm_right(pcm_right));
 mig_audio_bridge #(.STEREO(1)) audio(.clk_sys(clk_sys),.clk_aud(clk_aud),.rst_n(rst_n),
  .pcm_sys(pcm),.pcm_right_sys(pcm_right),.frame_tick(frame_tick),.HP_BCK(HP_BCK),.HP_WS(HP_WS),.HP_DIN(HP_DIN));
 assign PA_EN=1'b0;
 // Balanced population count includes playback without changing UART framing.
 wire [2:0] count4[0:7];
 genvar q;
 generate for(q=0;q<8;q=q+1)begin: count_keys
  assign count4[q]={2'd0,combined_gate[q*4]}+{2'd0,combined_gate[q*4+1]}+
   {2'd0,combined_gate[q*4+2]}+{2'd0,combined_gate[q*4+3]};
 end endgenerate
 wire [3:0] count8a={1'b0,count4[0]}+{1'b0,count4[1]},count8b={1'b0,count4[2]}+{1'b0,count4[3]};
 wire [3:0] count8c={1'b0,count4[4]}+{1'b0,count4[5]},count8d={1'b0,count4[6]}+{1'b0,count4[7]};
 wire [4:0] count16a={1'b0,count8a}+{1'b0,count8b},count16b={1'b0,count8c}+{1'b0,count8d};
 assign active_voices={1'b0,count16a}+{1'b0,count16b};
 // User selected the existing RGB pixel, no new LED GPIOs.
 wire [23:0] recorder_color=playing?24'h200000:
  ((recording || record_full)?(RECORD_LED?24'h002000:24'd0):
  (!PITCH_UP_KEY?24'h002000:24'h000020));
 reg [23:0] hmi_flash_timer;reg hmi_flash_bad;
 always @(posedge clk_sys or negedge rst_n)begin
  if(!rst_n)begin hmi_flash_timer<=0;hmi_flash_bad<=0;end
  else if(hmi_frame_invalid)begin hmi_flash_timer<=CLK_HZ/10;hmi_flash_bad<=1;end
  else if(hmi_frame_valid)begin hmi_flash_timer<=CLK_HZ/10;hmi_flash_bad<=0;end
  else if(hmi_flash_timer!=0)hmi_flash_timer<=hmi_flash_timer-1'b1;
 end
 // Purple means a validated c75/c48 import command reached the FPGA.
 // It is independent of request acceptance (cooldown/game/RX can inhibit TX).
 // This does not mean the ESP32 received bytes or that a score passed CRC.
 localparam integer SCORE_LED_CLKS=CLK_HZ*2;
 localparam integer SCORE_LED_W=$clog2(SCORE_LED_CLKS+1);
 reg [SCORE_LED_W-1:0] score_request_led_timer;
 always @(posedge clk_sys or negedge rst_n)begin
  if(!rst_n)score_request_led_timer<=0;
  else if(cmd_valid && cmd==8'h57 && cmd_value==16'd1)
   score_request_led_timer<=SCORE_LED_CLKS;
  else if(score_request_led_timer!=0)
   score_request_led_timer<=score_request_led_timer-1'b1;
 end
 // GRB order: G=0, R=0x60, B=0x60. Purple is held for two seconds.
 // Afterwards all existing recorder and HMI status indications resume.
 wire [23:0] link_color=(score_request_led_timer!=0)?24'h006060:
  (recording || playing || record_full)?recorder_color:
  (hmi_flash_timer!=0?(hmi_flash_bad?24'h606000:24'h0000ff):recorder_color);
 mig_ws2812_color #(.CLK_HZ(CLK_HZ)) led(
  .clk(clk_sys),.rst_n(rst_n),.color(link_color),.data_out(WS2812_DIN));
 assign status_data={inst_l,inst_r,active_voices,master,adsr_a,adsr_d,adsr_s,adsr_r,test_mode,strum_active,aux3_stable,aux4_stable};

 // HMI effect settings are sampled by fx_chain at each audio frame.
 reg [1:0] ui_timebase,ui_follow_speed;
 reg [31:0] ui_rx_frames,ui_bad_frames;
 wire [31:0] ui_tx_frames;
 integer ui_i;
 always @(posedge clk_sys or negedge rst_n)begin
  if(!rst_n)begin
   ui_fx_enable<=0;ui_timebase<=0;ui_follow_speed<=0;ui_rx_frames<=0;ui_bad_frames<=0;
   for(ui_i=0;ui_i<9;ui_i=ui_i+1)ui_fx_param[ui_i]<=10'd500;
  end else begin
   if(hmi_frame_valid)ui_rx_frames<=ui_rx_frames+1'b1;
   if(hmi_frame_invalid)ui_bad_frames<=ui_bad_frames+1'b1;
   if(cmd_valid)begin
    if(cmd==8'h40)ui_timebase<=cmd_value[1:0];
    if(cmd==8'h5a)ui_follow_speed<=(cmd_value>2)?0:cmd_value[1:0];
    for(ui_i=0;ui_i<3;ui_i=ui_i+1)if(cmd==8'h60+ui_i)ui_fx_enable[ui_i]<=cmd_value[0];
    for(ui_i=0;ui_i<9;ui_i=ui_i+1)if(cmd==8'h68+ui_i)ui_fx_param[ui_i]<=(cmd_value>1000)?10'd1000:cmd_value[9:0];
   end
  end
 end
 wire [31:0] scope_frequency;wire [15:0] scope_peak;
 hmi_scope_metrics #(.CLK_HZ(CLK_HZ)) scope_metrics(.clk(clk_sys),.rst_n(rst_n),.tick(frame_tick),.sample(pcm),.frequency(scope_frequency),.peak(scope_peak));

 // UI state is exported from authoritative registers, never touch requests.
 wire [2:0] selected_instrument=selected_panel?inst_r:inst_l;
 wire selected_guitar=(selected_instrument==1);
 wire [6:0] record_percent;
 hmi_percent progress(.clk(clk_sys),.rst_n(rst_n),
  .numerator(playing?elapsed_ms:record_length),
  .denominator(playing?duration_ms:RECORD_DEPTH),.percent(record_percent));
 function [31:0] qslider;input [16:0] v;reg [47:0] p;begin p=v*32'd1000+32'd32768;qslider=p>>16;end endfunction
 function [31:0] pslider;input [3:0] v;begin case(v)
  0:pslider=0;1:pslider=67;2:pslider=133;3:pslider=200;
  4:pslider=267;5:pslider=333;6:pslider=400;7:pslider=467;
  8:pslider=533;9:pslider=600;10:pslider=667;11:pslider=733;
  12:pslider=800;13:pslider=867;14:pslider=933;default:pslider=1000;
 endcase end endfunction
 wire [31:0] attack_slider,sustain_slider;
 wire [15:0] attack_offset=guitar_attack-16'd1;
 hmi_readback_scale #(.DIVISOR(4095)) attack_readback(.clk(clk_sys),.rst_n(rst_n),.value(attack_offset),.scaled(attack_slider));
 hmi_readback_scale #(.DIVISOR(32767)) sustain_readback(.clk(clk_sys),.rst_n(rst_n),.value(guitar_sustain),.scaled(sustain_slider));
 wire [5:0] calibration_valid;
 genvar cv;
 generate for(cv=0;cv<6;cv=cv+1)begin: hmi_calibration_valid
  assign calibration_valid[cv]=(calibration_high[cv*16+:16]-calibration_low[cv*16+:16])>=16'd32;
 end endgenerate
 wire [HMI_TX_FIELD_COUNT*32-1:0] ui_fields;
 genvar hk;
 generate for(hk=0;hk<16;hk=hk+1)begin: hmi_home_keys
  assign ui_fields[(HMI_FIELD_P0_C80_HOME_KEY_0+hk)*32+:32]={31'd0,selected_panel?combined_gate[16+hk]:combined_gate[hk]};
  assign ui_fields[(HMI_FIELD_P1_C100_PLAY_KEY_0+hk)*32+:32]={31'd0,selected_panel?(keys_right[hk]|screen_right[hk]):(keys_left[hk]|screen_left[hk])};
 end endgenerate
 assign ui_fields[HMI_FIELD_P0_C1_READY*32+:32]=32'd1;
 assign ui_fields[HMI_FIELD_P0_C2_BLE*32+:32]={31'd0,(score_receiving===1'b1)||(score_valid===1'b1)};
 assign ui_fields[HMI_FIELD_P0_C3_INSTRUMENTS*32+:32]={24'd0,1'b0,inst_l,1'b0,inst_r};
 assign ui_fields[HMI_FIELD_P0_C4_MASTER*32+:32]=qslider(master);
 // Existing numeric home field now reports measured partial population, 0..512.
 assign ui_fields[HMI_FIELD_P0_C5_ACTIVE_OSC*32+:32]={22'd0,active_osc};
 assign ui_fields[HMI_FIELD_P1_C90_PANEL_LEFT*32+:32]={31'd0,!selected_panel};
 assign ui_fields[HMI_FIELD_P1_C91_PANEL_RIGHT*32+:32]={31'd0,selected_panel};
 genvar ti;
 generate for(ti=0;ti<5;ti=ti+1)begin: hmi_timbre_buttons
  assign ui_fields[(HMI_FIELD_P5_C40_INSTRUMENT_40+ti)*32+:32]={31'd0,inst_l==ti};
  assign ui_fields[(HMI_FIELD_P5_C45_INSTRUMENT_45+ti)*32+:32]={31'd0,inst_r==ti};
 end endgenerate
 assign ui_fields[HMI_FIELD_P5_C90_OCTAVE_LEFT*32+:32]={{24{transpose_left[7]}},transpose_left};
 assign ui_fields[HMI_FIELD_P5_C91_OCTAVE_RIGHT*32+:32]={{24{transpose_right[7]}},transpose_right};
 assign ui_fields[HMI_FIELD_P5_C92_SEMITONE*32+:32]={{27{semitone[4]}},semitone};
 assign ui_fields[HMI_FIELD_P5_C94_SEMITONE_APPROX*32+:32]={31'd0,pitch_approximate};
 assign ui_fields[HMI_FIELD_P5_C96_PANEL_LEFT*32+:32]={31'd0,!selected_panel};
 assign ui_fields[HMI_FIELD_P5_C97_PANEL_RIGHT*32+:32]={31'd0,selected_panel};
 assign ui_fields[HMI_FIELD_P5_C95_SELECTED_INSTRUMENT*32+:32]={29'd0,selected_instrument};
 assign ui_fields[HMI_FIELD_P5_C62_ADSR_0*32+:32]=(SYNTH_MODE==0 && selected_guitar)?attack_slider:pslider(adsr_a);
 assign ui_fields[HMI_FIELD_P5_C63_ADSR_1*32+:32]=selected_guitar?pslider(guitar_decay):pslider(adsr_d);
 assign ui_fields[HMI_FIELD_P5_C64_ADSR_2*32+:32]=(SYNTH_MODE==0 && selected_guitar)?sustain_slider:pslider(adsr_s);
 assign ui_fields[HMI_FIELD_P5_C65_ADSR_3*32+:32]=selected_guitar?pslider(guitar_release):pslider(adsr_r);
 assign ui_fields[HMI_FIELD_P6_C81_KNOB_0*32+:32]=qslider(knob_targets[0+:17]);
 assign ui_fields[HMI_FIELD_P6_C82_KNOB_1*32+:32]=qslider(knob_targets[17+:17]);
 assign ui_fields[HMI_FIELD_P6_C83_KNOB_2*32+:32]=qslider(knob_targets[34+:17]);
 assign ui_fields[HMI_FIELD_P6_C84_KNOB_3*32+:32]=qslider(knob_targets[51+:17]);
 assign ui_fields[HMI_FIELD_P6_C85_KNOB_4*32+:32]=qslider(knob_targets[68+:17]);
 assign ui_fields[HMI_FIELD_P6_C86_KNOB_5*32+:32]=$signed(knobs.bend_value_q8) >>> 8;
 assign ui_fields[HMI_FIELD_P6_C91_CALIBRATION_0*32+:32]={31'd0,calibration_valid[0]};
 assign ui_fields[HMI_FIELD_P6_C92_CALIBRATION_1*32+:32]={31'd0,calibration_valid[1]};
 assign ui_fields[HMI_FIELD_P6_C93_CALIBRATION_2*32+:32]={31'd0,calibration_valid[2]};
 assign ui_fields[HMI_FIELD_P6_C94_CALIBRATION_3*32+:32]={31'd0,calibration_valid[3]};
 assign ui_fields[HMI_FIELD_P6_C95_CALIBRATION_4*32+:32]={31'd0,calibration_valid[4]};
 assign ui_fields[HMI_FIELD_P6_C96_CALIBRATION_5*32+:32]={31'd0,calibration_valid[5]};
 assign ui_fields[HMI_FIELD_P9_C50_RECORD_STATE*32+:32]={29'd0,record_full,playing,recording};
 assign ui_fields[HMI_FIELD_P9_C51_RECORD_LENGTH*32+:32]=record_length;
 assign ui_fields[HMI_FIELD_P9_C52_DURATION_MS*32+:32]=duration_ms;
 assign ui_fields[HMI_FIELD_P9_C53_RECORD_PERCENT*32+:32]={25'd0,record_percent};
 assign ui_fields[HMI_FIELD_P9_C54_LOOP_ENABLED*32+:32]={31'd0,loop_enabled};
 assign ui_fields[HMI_FIELD_P9_C55_RECORD_FULL*32+:32]={31'd0,record_full};
 assign ui_fields[HMI_FIELD_P10_C31_TEST_MODE*32+:32]={31'd0,test_mode&&!game_active};
 assign ui_fields[HMI_FIELD_P10_C70_GESTURE_ONLINE*32+:32]={31'd0,paj_ok&&!paj_error};
 assign ui_fields[HMI_FIELD_P10_C71_GESTURE_DIRECTION*32+:32]={28'd0,last_gesture_code};
 assign ui_fields[HMI_FIELD_P10_C72_GESTURE_PANELS*32+:32]={30'd0,last_gesture_panels};
 assign ui_fields[HMI_FIELD_P10_C73_BAUD*32+:32]=32'd115200;
 wire [31:0] hmi_tx_bytes;
 assign ui_fields[HMI_FIELD_P10_C74_HMI_LINK*32+:32]={31'd0,hmi_link_online};
 assign ui_fields[HMI_FIELD_P10_C75_RP108_ONLINE*32+:32]={31'd0,knob_online};
 assign ui_fields[HMI_FIELD_P10_C76_PAJ_STATUS*32+:32]={30'd0,paj_error,paj_ok};
 wire [6:0] score_receive_percent;
 hmi_percent score_progress(.clk(clk_sys),.rst_n(rst_n),.numerator({16'd0,score_received_count}),.denominator({16'd0,score_note_count}),.percent(score_receive_percent));
 assign ui_fields[HMI_FIELD_P8_C50_SCORE_VALID*32+:32]={31'd0,score_valid===1'b1};
 assign ui_fields[HMI_FIELD_P8_C51_SCORE_NOTE_COUNT*32+:32]={16'd0,score_note_count};
 assign ui_fields[HMI_FIELD_P8_C52_SCORE_BPM*32+:32]={16'd0,score_bpm};
 assign ui_fields[HMI_FIELD_P8_C55_SCORE_RECEIVE_PERCENT*32+:32]={25'd0,score_receive_percent};
 assign ui_fields[HMI_FIELD_P8_C56_SCORE_RECEIVE_STATE*32+:32]=(score_receive_error===1'b1)?32'd3:(score_receiving===1'b1)?32'd1:(score_valid===1'b1)?32'd2:32'd0;
 wire liss_mode;
 assign ui_fields[HMI_FIELD_P4_C65_LISS_MODE_0*32+:32]={31'd0,!liss_mode};
 assign ui_fields[HMI_FIELD_P4_C66_LISS_MODE_1*32+:32]={31'd0,liss_mode};
 genvar gl;
 generate for(gl=0;gl<16;gl=gl+1)begin: game_fields
  assign ui_fields[(HMI_FIELD_P7_C133_GAME_LANE_0+gl)*32+:32]={29'd0,game_lamps[gl*3+:3]};
 end endgenerate
 assign ui_fields[HMI_FIELD_P7_C70_GAME_NOTE_COUNT*32+:32]={16'd0,score_note_count};
 assign ui_fields[HMI_FIELD_P7_C71_GAME_SCORE*32+:32]={16'd0,game_score};
 assign ui_fields[HMI_FIELD_P7_C72_GAME_COMBO*32+:32]={16'd0,game_combo};
 assign ui_fields[HMI_FIELD_P7_C73_GAME_ACCURACY*32+:32]={25'd0,game_accuracy};
 assign ui_fields[HMI_FIELD_P7_C74_GAME_PROGRESS*32+:32]={25'd0,game_progress};
 // Keep field/control index 123/c75. State 1 is the red selected image;
 // a press selects red locally, and only a validated score permits green (0).
 assign ui_fields[HMI_FIELD_P7_C75_GAME_STATE*32+:32]={31'd0,!(score_valid===1'b1) || score_import_pending || score_import_request || score_receiving};
 `include "hmi_extra_fields.vh"
 mig_game_control #(.CLK_HZ(CLK_HZ),.PART(GUIDE_PART),.RIGHT_PANEL(GUIDE_RIGHT_PANEL)) game(
  .clk(clk_sys),.rst_n(rst_n),.cmd_valid(cmd_valid),.cmd(cmd),.value(cmd_value),.keys_left(keys_left),.keys_right(keys_right),
  .score_valid(score_valid && !score_import_pending && !score_import_request),.note_count(score_note_count),.bpm(score_bpm),.ticks_per_beat(score_ticks_per_beat),.length_ticks(score_length_ticks),
  .ram_data(score_read_data),.ram_rd(score_read_enable),.ram_addr(score_read_address),.active(game_active),
  .ctrl_valid(game_ctrl_valid),.ctrl_cmd(game_ctrl_cmd),.ctrl_value(game_ctrl_value),.lane_frames(game_lamps),
  .game_score(game_score),.combo(game_combo),.accuracy(game_accuracy),.progress(game_progress),.game_state(game_state));
 // One SCORE?\n request to the ESP32 for each accepted c75/c48 press.
 // The return stream remains AA 55 START/NOTE/END on the existing BLE_RX.
 score_request_tx #(.CLK_HZ(CLK_HZ)) score_request(
  .clk(clk_sys),.rst_n(rst_n),
  .request(cmd_valid && cmd==8'h57 && cmd_value==16'd1),
  .inhibit(score_receiving || game_active),.tx(BLE_TX),
  .busy(score_request_busy),.accepted(score_import_request));
 // Decouple the wide UI field formatter from hmi_tx's field scan and UART
 // CE logic. This is a status-only one-system-clock latency, not an audio path.
 reg [HMI_TX_FIELD_COUNT*32-1:0] ui_fields_q;
 always @(posedge clk_sys or negedge rst_n) begin
  if(!rst_n) ui_fields_q<=0;
  else ui_fields_q<=ui_fields;
 end
 wire [3:0] hmi_page;
 wire viz_valid,viz_last,viz_ready,viz_frame_end;wire [7:0] viz_data;
 mig_visualization #(.CLK_HZ(CLK_HZ),.REAL_ADSR(SYNTH_MODE==1)) visualization(.clk(clk_sys),.rst_n(rst_n),.frame_tick(frame_tick),.page(hmi_page),
  .pcm_left(pcm),.pcm_right(pcm_right),.panel_a(panel_a_sum),.panel_b(panel_b_sum),
  .env_observe(selected_panel?env_observe[39:20]:env_observe[19:0]),
  .a(selected_guitar?((guitar_attack==4096)?4'd15:guitar_attack[11:8]):adsr_a),
  .d(selected_guitar?guitar_decay:adsr_d),.s(selected_guitar?guitar_sustain[14:11]:adsr_s),.r(selected_guitar?guitar_release:adsr_r),
  .cmd_valid(cmd_valid),.cmd(cmd),.value(cmd_value),.aux_valid(viz_valid),.aux_last(viz_last),.aux_frame_end(viz_frame_end),.aux_data(viz_data),.aux_ready(viz_ready),.liss_mode(liss_mode));
 hmi_tx #(.CLK_HZ(CLK_HZ),.FIELD_COUNT(HMI_TX_FIELD_COUNT),.LINK_DIAGNOSTICS(1),.SYNTH_MODE(SYNTH_MODE)) transmitter(
  .page_valid(hmi_page_valid),.page_id(hmi_page_id),.screen_reset(hmi_screen_reset | hmi_link_lost),.clk(clk_sys),.rst_n(rst_n),
  .cmd_valid(cmd_valid),.cmd(cmd),.value(cmd_value),.fields(ui_fields_q),
  .aux_valid(viz_valid),.aux_last(viz_last),.aux_frame_end(viz_frame_end),.aux_data(viz_data),.aux_ready(viz_ready),
  .tx(UART_TX),.current_page(hmi_page),.byte_count(hmi_tx_bytes));

 assign ui_tx_frames=transmitter.frame_count;
endmodule
