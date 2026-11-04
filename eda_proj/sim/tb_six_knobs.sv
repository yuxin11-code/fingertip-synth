`timescale 1ns/1ps
module tb_six_knobs;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,frame_tick=0;
 reg [5:0] write_mask=0;reg [101:0] write_values=0;
 reg [16:0] fallback_volume=32768;reg [17:0] base_pitch=65536;
 reg hmi_valid=0;reg [7:0] hmi_cmd=0;reg [15:0] hmi_value=0;
 reg volume_up_event=0,volume_down_event=0;reg [95:0] raw_values=0,calibration_low=0,calibration_high={6{16'd65535}};
 wire [84:0] targets,actual_values;
 wire [16:0] master,blend,balance;wire [17:0] modulated_pitch;
 // 1000-Hz test control updates accelerate the seconds-long return test.
 // LFO constants explicitly correspond to a 1000-Hz sample stream here.
 mig_six_knobs #(.CONTROL_FRAMES(1),.RATE_STEP_MIN(12884902),.RATE_STEP_SPAN(21474836)) dut(.*);
 reg signed [39:0] panel_a=4000,panel_b=8000;reg test_atten=0;
 wire signed [15:0] pcm_left,pcm_right;
 mig_stereo_mixer #(.EQUAL_POWER(1)) mixer(.*);
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 task frames(input integer n);
  integer i;begin for(i=0;i<n;i=i+1)begin frame_tick=1;cycles(1);frame_tick=0;cycles(10);end end
 endtask
 task put(input integer ch,input [16:0] v);
  begin write_values[ch*17+:17]=v;write_mask=1<<ch;cycles(1);write_mask=0;cycles(5);end
 endtask
 integer i,low,high,x,expected,actual,previous;reg [16:0] prior;
 longint curve_product;
 initial begin
  cycles(5);rst_n=1;frames(10);
  if(master!==32768 || blend!==32768 || balance!==32768 || modulated_pitch!==65536)$fatal(1,"clean power-on defaults");
  if(pcm_left<1058 || pcm_left>1061)$fatal(1,"equal power center %d",pcm_left);
  if(mixer.a_gain!=46341 || mixer.b_gain!=46341)$fatal(1,"equal-power midpoint");
  put(0,65536);prior=master;frames(1);
  if(master<=prior || master>=65536)$fatal(1,"volume step not smoothed");
  frames(220);if(master!=65536)$fatal(1,"volume endpoint");
  hmi_cmd=6;hmi_value=0;hmi_valid=1;volume_down_event=1;cycles(2);
  hmi_valid=0;volume_down_event=0;frames(30);
  if(targets[16:0]!=0 || !dut.locked[0])$fatal(1,"screen volume target not accepted");
  frames(220);if(master!=0)$fatal(1,"screen volume did not settle");
  // Real raw movement crosses the takeover threshold; KEY events stay retired.
  raw_values[15:0]=40000;put(0,65536);frames(220);
  if(master!=65536 || dut.locked[0])$fatal(1,"physical volume takeover");
  put(1,0);frames(220);if(pcm_left!=1000 || pcm_right!=1000)$fatal(1,"panel1 solo");
  put(1,65536);frames(220);if(pcm_left!=2000)$fatal(1,"panel2 solo");
  put(2,0);frames(220);if(pcm_left!=2000 || pcm_right!=0)$fatal(1,"left-only balance");
  put(2,65536);frames(220);if(pcm_left!=0 || pcm_right!=2000)$fatal(1,"right-only balance");
  // All six controls update in one transaction; no exclusive mode/select.
  write_values={17'd32768,17'd32768,17'd32768,17'd32768,17'd32768,17'd32768};write_mask=6'h3f;cycles(1);write_mask=0;frames(250);
  if(master!=32768 || blend!=32768 || balance!=32768 || dut.value[3]!=32768 || dut.value[4]!=32768)$fatal(1,"simultaneous controls");
  if(dut.phase_step<23622319 || dut.phase_step>23622321)$fatal(1,"5.5Hz center");
  put(4,0);frames(220);if(dut.phase_step!=12884902)$fatal(1,"3Hz minimum");
  put(3,65536);put(4,65536);frames(250);low=999999;high=0;
  if(dut.phase_step!=34359738)$fatal(1,"8Hz maximum");
  for(i=0;i<600;i=i+1)begin frames(1);if(modulated_pitch<low)low=modulated_pitch;if(modulated_pitch>high)high=modulated_pitch;end
  if(low<63660 || low>63700 || high<67410 || high>67470)$fatal(1,"50-cent vibrato %d..%d",low,high);
  $display("vibrato Q16 range %0d..%0d at 8Hz",low,high);
  put(3,0);frames(250);if(modulated_pitch!=65536)$fatal(1,"vibrato off not exact bypass");
  // Sweep all branches against an independent integer curve, including
  // 30-degree dead zone, rising peak, falling zero and both end stops.
  previous=0;
  for(i=0;i<=256;i=i+1)begin
   x=i*256;put(5,x);
   if(x<=3641)expected=0;
   else if(x<=34588)begin curve_product=longint'(x-3641)*51200;expected=(curve_product+15473)/30947;end
   else begin curve_product=longint'(x-34588)*102400;expected=51200-(curve_product+15474)/30948;end
   actual=$signed(dut.bend_command2);
   if(actual<expected-1 || actual>expected+1)$fatal(1,"540-degree curve x=%0d got=%0d expected=%0d",x,actual,expected);
   if(x<=34588 && actual<previous)$fatal(1,"rising curve reversed");
   if(x>34816 && actual>previous)$fatal(1,"falling curve reversed");
   previous=actual;
  end
  put(5,3641);if(dut.bend_command2!=0)$fatal(1,"30 degrees must be neutral");
  put(5,34588);if(dut.bend_command2!=51200)$fatal(1,"285 degrees must be +2 semitones");
  frames(110);
  if(modulated_pitch<73400 || modulated_pitch>73565)$fatal(1,"+200cent bend %d",modulated_pitch);
  while(dut.bend_idle<199)frames(1);
  if(dut.bend_target_q8!=51200)$fatal(1,"bend returned before 200ms");
  frames(3);if(dut.bend_target_q8!=0 || dut.bend_value_q8>=51199)$fatal(1,"bend did not start return after 200ms");
  // Unchanged repeated poll must not hold a bend forever.
  repeat(35)begin put(5,34588);frames(100);end
  if(modulated_pitch!=65536 || dut.bend_value_q8!=0)$fatal(1,"auto return failed %d",modulated_pitch);
  put(5,65536);frames(110);
  if(modulated_pitch<58370 || modulated_pitch>58530)$fatal(1,"-200cent bend %d",modulated_pitch);
  frames(3500);if(modulated_pitch!=65536)$fatal(1,"negative return exact center");
  put(5,0);frames(120);if(modulated_pitch!=65536)$fatal(1,"left end must not bend");
  put(5,50062);if(dut.bend_command2< -2 || dut.bend_command2>2)$fatal(1,"412.5 degrees must cross original pitch");
  // Pitch bend multiplies the existing global transposition, not replaces it.
  base_pitch=131072;put(5,34588);frames(110);
  if(modulated_pitch<146800 || modulated_pitch>147130)$fatal(1,"bend lost common pitch scaling");
  base_pitch=65536;frames(3500);
  put(0,0);frames(230);if(pcm_left!=0 || pcm_right!=0)$fatal(1,"master mute");
  panel_a=400000;panel_b=800000;put(0,65536);frames(230);if(pcm_right!=32767)$fatal(1,"positive limiter");
  panel_a=-400000;panel_b=-800000;cycles(12);if(pcm_right!=-32768)$fatal(1,"negative limiter");
  $display("PASS six knobs: touch/physical volume takeover, 540-degree piecewise bend, 30-degree neutral zone, +2/-2 semitone endpoints, 200ms idle auto-center, transpose/vibrato composition and existing mixer controls");$finish;
 end
 initial begin #100000000;$fatal(1,"timeout");end
endmodule
