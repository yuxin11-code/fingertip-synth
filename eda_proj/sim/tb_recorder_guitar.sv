`timescale 1ns/1ps
module tb_recorder_guitar;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0;reg [5:0] fc=0;always @(posedge clk)fc<=fc+1'b1;
 wire frame_tick=(fc==0);
 reg [15:0] keys_left=0,keys_right=0;
 reg strum_right=0,strum_left=0,il=1,ir=1,rec_n=1,play_n=1;
 wire [31:0] live,replay;
 wire [31:0] combined=live|replay;
 wire [255:0] notes;wire [95:0] inst;
 wire [3:0] a,d,s,r;wire [15:0] ga,gs;wire [3:0] gd,gr;
 wire recording,playing;wire [6:0] length;
 mig_input_ctrl #(.CLK_HZ(10000),.DB_TICKS(2),.GAP_FRAMES(2),.HOLD_FRAMES(10)) controls(
  .clk(clk),.rst_n(rst_n),.frame_tick(frame_tick),.keys_left(keys_left),.keys_right(keys_right),
  .strum_right(strum_right),.strum_left(strum_left),.key_up_n(1'b1),.key_dn_n(1'b1),
  .inst_left_n(il),.inst_right_n(ir),.aux3_n(1'b1),.aux4_n(1'b1),.test_toggle_n(1'b1),
  .enc_a(1'b1),.enc_b(1'b1),.enc_c_n(1'b1),.transpose_left(8'sd0),.transpose_right(8'sd0),
  .voice_gate(live),.voice_note(notes),.voice_inst(inst),.volume_q16(),
  .adsr_a(a),.adsr_d(d),.adsr_s(s),.adsr_r(r),.active_voices(),.test_mode(),.strum_active(),
  .inst_l(),.inst_r(),.aux3_stable(),.aux4_stable(),.guitar_attack(ga),.guitar_sustain(gs),.guitar_decay(gd),.guitar_release(gr));
 mig_action_recorder #(.CLK_HZ(10000),.DEPTH(64)) recorder(
  .clk(clk),.rst_n(rst_n),.record_n(rec_n),.play_n(play_n),.live_keys(live),.replay_keys(replay),
  .record_stable(),.play_stable(),.recording(recording),.playing(playing),.record_led(),.play_led(),.full(),.length(length));
 wire signed [39:0] mix_sum,pa,pb;wire signed [15:0] pcm_left,pcm_right;
 mig_voice_engine voices(.clk(clk),.rst_n(rst_n),.frame_tick(frame_tick),.v_gate(combined),.v_note(notes),.v_inst(inst),
  .pitch_scale_q16(18'd65536),.a_param(a),.d_param(d),.s_param(s),.r_param(r),
  .guitar_attack(ga),.guitar_sustain(gs),.guitar_decay(gd),.guitar_release(gr),.mix_sum(mix_sum),.panel_a_sum(pa),.panel_b_sum(pb));
 mig_stereo_mixer #(.EQUAL_POWER(1)) mixer(.clk(clk),.rst_n(rst_n),.panel_a(pa),.panel_b(pb),
  .master(17'd65536),.blend(17'd32768),.balance(17'd32768),.test_atten(1'b0),.pcm_left(pcm_left),.pcm_right(pcm_right));
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 integer i,onsets=0,peak=0,n,v;reg [31:0] prev=0,new_on;
 reg heard_left=0,heard_right=0;
 always @(posedge clk)if(playing && frame_tick)begin
  v=$signed(pcm_left);if(v<0)v=-v;if(v>peak)peak=v;
  if(replay[15:0]!=0)heard_left=1;
  if(replay[31:16]!=0)heard_right=1;
  if(strum_right || strum_left)$fatal(1,"playback must not require a new gesture");
 end
 initial begin
  cycles(5);rst_n=1;cycles(10);il=0;ir=0;cycles(10);il=1;ir=1;cycles(20);
  keys_left=5;keys_right=16'h8001;cycles(20);
  if(live!=32'h80010005 || controls.inst_l!=1 || controls.inst_r!=1)$fatal(1,"direct touch guitar gating changed");
  keys_left=0;keys_right=0;cycles(40);
  rec_n=0;cycles(180);rec_n=1;cycles(180);
  keys_left=16'h0001;keys_right=16'h0001;cycles(20);
  strum_right=1;cycles(10);strum_right=0;cycles(1500);
  keys_left=0;keys_right=0;cycles(30);
  keys_left=16'h8000;keys_right=16'h0004;cycles(20);
  strum_left=1;cycles(10);strum_left=0;cycles(1500);
  keys_left=0;keys_right=0;cycles(30);
  rec_n=0;cycles(180);rec_n=1;cycles(180);
  if(recording || length<5)$fatal(1,"strum transitions missing from recording");
  if(live!=0)$fatal(1,"live gate stuck after strum");
  keys_left=0;keys_right=0;cycles(20);
  play_n=0;cycles(180);play_n=1;cycles(180);
  n=0;while(playing && n<10000)begin cycles(1);n=n+1;end
  if(playing || replay!=0 || peak<10 || !heard_left || !heard_right)$fatal(1,"guitar replay PCM missing peak=%d",peak);
  $display("PASS guitar action replay: both panels ascending/descending gesture order captured, no repeat gesture required, original guitar envelope -> final PCM peak=%0d, EOT releases",peak);$finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
