`timescale 1ns/1ps
module tb_all_timbres_strum;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0;reg [5:0] frame_count=0;wire frame_tick=(frame_count==0);
 always @(posedge clk)frame_count<=frame_count+1'b1;
 reg [15:0] keys_left=0,keys_right=0;reg strum_right=0,strum_left=0;reg il=1,ir=1;
 wire [31:0] voice_gate;wire [255:0] voice_note;wire [95:0] voice_inst;
 wire [16:0] volume_q16;wire [3:0] aa,dd,ss,rr;wire [5:0] active;wire test_mode,strum_active;
 wire [2:0] inst_l,inst_r;wire [15:0] ga,gs;wire [3:0] gd,gr;
 mig_input_ctrl #(.CLK_HZ(10000),.DB_TICKS(4),.GAP_FRAMES(2),.HOLD_FRAMES(80)) controls(
  .clk(clk),.rst_n(rst_n),.frame_tick(frame_tick),.keys_left(keys_left),.keys_right(keys_right),
  .strum_right(strum_right),.strum_left(strum_left),.key_up_n(1'b1),.key_dn_n(1'b1),
  .inst_left_n(il),.inst_right_n(ir),.aux3_n(1'b1),.aux4_n(1'b1),.test_toggle_n(1'b1),
  .enc_a(1'b1),.enc_b(1'b1),.enc_c_n(1'b1),.transpose_left(8'sd0),.transpose_right(8'sd0),
  .voice_gate(voice_gate),.voice_note(voice_note),.voice_inst(voice_inst),.volume_q16(volume_q16),
  .adsr_a(aa),.adsr_d(dd),.adsr_s(ss),.adsr_r(rr),.active_voices(active),.test_mode(test_mode),.strum_active(strum_active),
  .inst_l(inst_l),.inst_r(inst_r),.aux3_stable(),.aux4_stable(),.guitar_attack(ga),.guitar_sustain(gs),.guitar_decay(gd),.guitar_release(gr));
 wire signed [39:0] sum,pa,pb;wire signed [15:0] pcm_l,pcm_r;
 mig_voice_engine voices(.clk(clk),.rst_n(rst_n),.frame_tick(frame_tick),.v_gate(voice_gate),.v_note(voice_note),.v_inst(voice_inst),
  .pitch_scale_q16(18'd65536),.a_param(aa),.d_param(dd),.s_param(ss),.r_param(rr),
  .guitar_attack(ga),.guitar_sustain(gs),.guitar_decay(gd),.guitar_release(gr),.mix_sum(sum),.panel_a_sum(pa),.panel_b_sum(pb));
 mig_stereo_mixer #(.EQUAL_POWER(1)) mixer(.clk(clk),.rst_n(rst_n),.panel_a(pa),.panel_b(pb),
  .master(17'd65536),.blend(17'd32768),.balance(17'd32768),.test_atten(1'b0),.pcm_left(pcm_l),.pcm_right(pcm_r));
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 task timbre_next;begin il=0;cycles(12);il=1;cycles(12);end endtask
 task direct_left;begin keys_left=16'h0001;cycles(12);if(!voice_gate[0])$fatal(1,"direct touch timbre %d",inst_l);keys_left=0;cycles(20);end endtask
 integer i,frames;reg strum_seen;integer peak;
 always @(posedge clk)if(frame_tick && strum_active)begin strum_seen=1;if($signed(pcm_l)>peak)peak=pcm_l;end
 task pluck_left;begin
  keys_left=16'h0003;strum_right=1;cycles(8);strum_right=0;cycles(12);keys_left=0;frames=0;strum_seen=0;
  while(!strum_seen && frames<400)begin cycles(20);frames=frames+1;end
  if(!strum_seen)$fatal(1,"gesture pluck timbre %d",inst_l);cycles(100);
 end endtask
 initial begin
  cycles(5);rst_n=1;cycles(10);peak=0;
  if(inst_l!==0 || inst_r!==0)$fatal(1,"reset timbre");
  for(i=0;i<5;i=i+1)begin
   if(i!=0)timbre_next;
   if(inst_l!==i[2:0])$fatal(1,"left timbre selection %d",i);
   direct_left;pluck_left;
  end
  repeat(4)timbre_next;
  il=1;ir=0;cycles(12);ir=1;cycles(12);
  keys_right=16'h0004;cycles(12);if(!voice_gate[18])$fatal(1,"right direct guitar");keys_right=0;cycles(20);
  keys_right=16'h000c;strum_left=1;cycles(8);strum_left=0;cycles(12);keys_right=0;frames=0;strum_seen=0;
  while(!strum_seen && frames<400)begin cycles(20);frames=frames+1;end
  if(!strum_seen)$fatal(1,"right gesture guitar");
  if(peak<10)$fatal(1,"strum PCM silent peak %d",peak);
  $display("PASS all timbres: direct touch and both-direction gesture pluck for piano/guitar/violin/guzheng/pipa, dual-panel gate and PCM peak=%0d",peak);$finish;
 end
 initial begin #3000000;$fatal(1,"timeout");end
endmodule
