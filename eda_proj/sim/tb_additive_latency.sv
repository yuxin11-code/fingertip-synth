`timescale 1ns/1ps
// Digital-path latency measurement only; excludes TTP229 sensor and analog DAC.
module tb_additive_latency;
 localparam real SYS_HALF=1000000000.0/105000000.0;
 localparam real AUDIO_HALF=1000000000.0/(2.0*52500000.0*31.0/256.0/4.0);
 reg clk=0;always #(SYS_HALF)clk=~clk;
 reg clk_aud=0;always #(AUDIO_HALF)clk_aud=~clk_aud;
 reg rst_n=0;wire frame_tick;
 reg [31:0] v_gate=0;wire [255:0] v_note={32{8'd60}};wire [95:0] v_inst=0;
 wire signed [39:0] mix_sum,panel_a_sum,panel_b_sum;
 wire [9:0] active_osc;wire [39:0] env_observe;
 wire busy,ready,sample_valid,deadline_error;
 wire signed [15:0] pcm_left,pcm_right;
 wire HP_BCK,HP_WS,HP_DIN;
 mig_additive_engine engine(.clk(clk),.rst_n(rst_n),.frame_tick(frame_tick),
  .v_gate(v_gate),.v_note(v_note),.v_inst(v_inst),.pitch_scale_q16(18'd65536),
  .a_param(8'd102),.d_param(8'd68),.s_param(8'd204),.r_param(8'd85),
  .guitar_d_param(8'd68),.guitar_r_param(8'd85),
  .mix_sum(mix_sum),.panel_a_sum(panel_a_sum),.panel_b_sum(panel_b_sum),
  .active_osc(active_osc),.env_observe(env_observe),.busy(busy),.ready(ready),
  .sample_valid(sample_valid),.deadline_error(deadline_error));
 mig_stereo_mixer #(.EQUAL_POWER(1)) mixer(.clk(clk),.rst_n(rst_n),
  .panel_a(panel_a_sum),.panel_b(panel_b_sum),.master(17'd65536),.blend(17'd32768),
  .balance(17'd32768),.test_atten(1'b0),.pcm_left(pcm_left),.pcm_right(pcm_right));
 mig_audio_bridge #(.STEREO(1)) audio(.clk_sys(clk),.clk_aud(clk_aud),.rst_n(rst_n),
  .pcm_sys(pcm_left),.pcm_right_sys(pcm_right),.frame_tick(frame_tick),
  .HP_BCK(HP_BCK),.HP_WS(HP_WS),.HP_DIN(HP_DIN));
 realtime change_time,accept_time,commit_time,pcm_time,frame_time,word_time;
 reg measuring=0;integer frame_accepts=0;integer trial,offset;
 reg last_ws=1;integer bits=0;reg [15:0] word_value=0;
 always @(posedge clk)begin
  if(measuring && frame_tick && ready && !busy && v_gate!=0 && accept_time==0)accept_time=$realtime;
  #0.001;
  if(measuring && sample_valid && accept_time!=0 && commit_time==0)commit_time=$realtime;
  if(measuring && pcm_left!=0 && pcm_time==0)pcm_time=$realtime;
  if(deadline_error)$fatal(1,"unexpected deadline miss");
 end
 always @(posedge clk_aud)begin
  #0.001;
  if(measuring && audio.pcm_frame!=0 && frame_time==0)frame_time=$realtime;
 end
 always @(negedge HP_BCK)begin
  if(!rst_n)begin bits=0;word_value=0;last_ws=1;end
  else begin
   if(HP_WS!=last_ws)begin bits=0;word_value=0;end
   last_ws=HP_WS;word_value={word_value[14:0],HP_DIN};bits=bits+1;
   if(measuring && !HP_WS && bits==16 && word_value!=0 && word_time==0)word_time=$realtime;
  end
 end
 initial begin
  for(trial=0;trial<6;trial=trial+1)begin
   measuring=0;v_gate=0;rst_n=0;repeat(4)@(negedge clk);rst_n=1;
   wait(ready);@(posedge frame_tick);@(negedge clk);
   case(trial)0:offset=0;1:offset=1;2:offset=100;3:offset=500;4:offset=1000;5:offset=1055;endcase
   repeat(offset)@(negedge clk);
   accept_time=0;commit_time=0;pcm_time=0;frame_time=0;word_time=0;
   change_time=$realtime;v_gate=1;measuring=1;
   wait(word_time!=0);@(negedge clk);
   $display("LATENCY offset=%0d wait_snapshot_us=%0.6f compute_us=%0.6f gate_to_nonzero_pcm_us=%0.6f gate_to_stereo_latch_us=%0.6f gate_to_complete_left_word_us=%0.6f",
    offset,(accept_time-change_time)/1000.0,(commit_time-accept_time)/1000.0,
    (pcm_time-change_time)/1000.0,(frame_time-change_time)/1000.0,(word_time-change_time)/1000.0);
  end
  $display("PASS digital-path latency: real frame/CDC/mixer/PT8211 serializer, no sensor or analog delay included");$finish;
 end
 initial begin #1000000;$fatal(1,"latency watchdog");end
endmodule
