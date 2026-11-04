`timescale 1ns/1ps
module tb_recorder_top;
 wire BLE_RX=1'b1;
 reg rst=0,KEY1=1,KEY2=1,TIMBRE_KEY=1,ENC_A=1,ENC_B=1,ENC_C=1,PITCH_UP_KEY=1,PITCH_DOWN_KEY=1;
 reg K_LEFT=1,K_RIGHT=1,K_AUX3=1,K_AUX4=1,TEST_MODE_KEY=1,OCT_A=1,OCT_B=1,OCT_SW_N=1,UART_RX=1;
 wire TTP229_SDO,TTP_R_SDO;
 tri1 PAJ_SCL,PAJ_SDA,KNOB_SCL,KNOB_SDA;
 wire TTP229_SCL,TTP_R_SCL,HP_BCK,HP_WS,HP_DIN,PA_EN,WS2812_DIN,UART_TX;
 reg [15:0] left_keys=0,right_keys=0;
 top #(.RECORD_DEPTH(64)) dut(.*);
 defparam dut.g_dual.instrument.left_touch.CLK_HZ=20000;
 defparam dut.g_dual.instrument.right_touch.CLK_HZ=20000;
 defparam dut.g_dual.instrument.left_touch.SCL_HZ=2000;
 defparam dut.g_dual.instrument.right_touch.SCL_HZ=2000;
 // Accelerate only recorder milliseconds/debounce, retain real audio clocks.
 defparam dut.g_dual.instrument.recorder.CLK_HZ=1000000;
 defparam dut.g_dual.instrument.octave_control.CLK_HZ=20000;
 poweron_touch lm(TTP229_SCL,left_keys,TTP229_SDO);
 poweron_touch rm(TTP_R_SCL,right_keys,TTP_R_SDO);
 // Independent no-playback engine, to distinguish re-synthesis from old tails.
 wire signed [39:0] ref_a,ref_b,ref_sum;
 wire signed [15:0] ref_left,ref_right;
 wire clk=dut.g_dual.clk_sys;
 mig_voice_engine reference_engine(.clk(clk),.rst_n(dut.g_dual.reset_n),.frame_tick(dut.g_dual.instrument.frame_tick),
  .v_gate(dut.g_dual.instrument.voice_gate),.v_note(dut.g_dual.instrument.voice_note),.v_inst(dut.g_dual.instrument.voice_inst),
  .pitch_scale_q16(dut.g_dual.instrument.modulated_pitch),
  .a_param(dut.g_dual.instrument.adsr_a),.d_param(dut.g_dual.instrument.adsr_d),.s_param(dut.g_dual.instrument.adsr_s),.r_param(dut.g_dual.instrument.adsr_r),
  .guitar_attack(dut.g_dual.instrument.guitar_attack),.guitar_sustain(dut.g_dual.instrument.guitar_sustain),
  .guitar_decay(dut.g_dual.instrument.guitar_decay),.guitar_release(dut.g_dual.instrument.guitar_release),
  .mix_sum(ref_sum),.panel_a_sum(ref_a),.panel_b_sum(ref_b));
 // Match the current top's authorized +3.52 dB master range.
 mig_stereo_mixer #(.EQUAL_POWER(1),.BOOST_MASTER(1)) reference_mixer(.clk(clk),.rst_n(dut.g_dual.reset_n),
  .panel_a(ref_a),.panel_b(ref_b),.master(dut.g_dual.instrument.master),.blend(dut.g_dual.instrument.blend),
  .balance(dut.g_dual.instrument.balance),.test_atten(1'b0),.pcm_left(ref_left),.pcm_right(ref_right));
 integer f,frames=0,play_frames=0,peak=0,difference=0,d,clipped=0;
 reg duet_seen=0,left_seen=0,right_seen=0;
 initial f=$fopen("results/action_recorder/top_pcm.csv","w");
 always @(posedge clk)if(dut.g_dual.instrument.frame_tick)begin
  frames=frames+1;
  $fdisplay(f,"%0d,%0d,%0d,%0d,%0d,%0d",frames,dut.g_dual.instrument.recording,dut.g_dual.instrument.playing,dut.g_dual.instrument.pcm,dut.g_dual.instrument.pcm_right,ref_left);
  if(dut.g_dual.instrument.playing)begin
   play_frames=play_frames+1;
   d=$signed(dut.g_dual.instrument.pcm)-$signed(ref_left);if(d<0)d=-d;if(d>difference)difference=d;
   d=$signed(dut.g_dual.instrument.pcm);if(d<0)d=-d;if(d>peak)peak=d;
   if(dut.g_dual.instrument.replay_keys[15:0]!=0)left_seen=1;
   if(dut.g_dual.instrument.replay_keys[31:16]!=0)right_seen=1;
   if(dut.g_dual.instrument.replay_keys[0] && dut.g_dual.instrument.voice_gate[21] && dut.g_dual.instrument.combined_gate[0] && dut.g_dual.instrument.combined_gate[21])duet_seen=1;
   if(dut.g_dual.instrument.pcm==32767 || dut.g_dual.instrument.pcm==-32768)clipped=clipped+1;
   if(dut.g_dual.instrument.active_voices==0 && dut.g_dual.instrument.combined_gate!=0)$fatal(1,"UART count misses playback");
  end
 end
 task rec;begin K_AUX3=0;#350000;K_AUX3=1;#350000;end endtask
 task play;begin K_AUX4=0;#350000;K_AUX4=1;#350000;end endtask
 initial begin
  #400000;rec;
  if(!dut.g_dual.instrument.recording || dut.g_dual.instrument.inst_l!=0 || dut.g_dual.instrument.inst_r!=0)$fatal(1,"physical K3/defaults");
  left_keys=1;right_keys=2;#1000000;
  left_keys=5;right_keys=16'h81;#1000000;
  left_keys=0;right_keys=0;#400000;rec;
  if(dut.g_dual.instrument.recording || dut.g_dual.instrument.record_length<5)$fatal(1,"physical K3 stop");
  play;right_keys=16'h20;#4000000;
  if(dut.g_dual.instrument.playing || dut.g_dual.instrument.replay_keys!=0 || !dut.g_dual.instrument.combined_gate[21])$fatal(1,"EOT/live overlay");
  if(!left_seen || !right_seen || !duet_seen || peak<100 || difference<100 || clipped!=0)$fatal(1,"actual re-synthesized PCM/duet peaks=%d diff=%d",peak,difference);
  right_keys=0;#500000;
  OCT_B=0;#1000;OCT_A=0;#1000;OCT_B=1;#1000;OCT_A=1;#2000;
  if(dut.g_dual.instrument.transpose_left!=1 || dut.g_dual.instrument.transpose_right!=0)$fatal(1,"octave independent");
  play;#500000;
  if(dut.g_dual.instrument.voice_note[7:0]!=72)$fatal(1,"playback failed to use current transposition");
  play;
  if(dut.g_dual.instrument.playing || dut.g_dual.instrument.replay_keys!=0)$fatal(1,"K4 manual stop");
  $display("PASS top recorder: serial TTP229 + physical K3/K4 -> BSRAM actions -> 32-voice live OR -> PCM; replay PCM peak=%0d, delta vs no-replay tail=%0d, play frames=%0d, no clipping, octave/UART count preserved",peak,difference,play_frames);
  $fclose(f);$finish;
 end
 initial begin #20000000;$fatal(1,"timeout");end
endmodule
