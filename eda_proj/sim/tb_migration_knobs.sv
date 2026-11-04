`timescale 1ns/1ps
module tb_migration_knobs;
reg clk=0;always #5 clk=~clk;
reg rst_n=0,frame_tick=0;
reg [4:0] write_mask=0;reg [84:0] write_values=0;
reg [16:0] fallback_volume=32768;
reg [17:0] base_pitch=65536;
wire [16:0] master,blend,balance;wire [17:0] modulated_pitch;
mig_five_knobs dut(.*);
reg signed [39:0] panel_a=4000,panel_b=8000;
reg test_atten=0;
wire signed [15:0] pcm_left,pcm_right;
mig_stereo_mixer mixer(.*);
task cycles(input integer n);repeat(n) @(negedge clk);endtask
task frames(input integer n);integer i;begin
 for(i=0;i<n;i=i+1) begin frame_tick=1;cycles(1);frame_tick=0;cycles(1);end
 cycles(8);
end endtask
task set_knob(input integer n,input [16:0] v);begin
 write_values[n*17+:17]=v;write_mask=1<<n;cycles(1);write_mask=0;frames(300);
end endtask
integer low_pitch,high_pitch,i;reg [31:0] phase_before,slow_step,fast_step;
initial begin
 cycles(3);rst_n=1;frames(5);
 if(master!=32768 || blend!=32768 || balance!=32768 || modulated_pitch!=65536)
  $fatal(1,"fallback defaults");
 if(pcm_left!=1500 || pcm_right!=1500) $fatal(1,"center original gain");
 fallback_volume=0;frames(300);
 if(pcm_left!=0 || pcm_right!=0) $fatal(1,"button fallback mute");
 set_knob(0,65536);fallback_volume=0;frames(2);
 if(master!=65536 || pcm_left!=3000) $fatal(1,"knob owns master after valid write");
 set_knob(1,0);if(pcm_left!=1000) $fatal(1,"panel A solo");
 set_knob(1,65536);if(pcm_left!=2000) $fatal(1,"panel B solo");
 set_knob(2,0);if(pcm_left!=2000 || pcm_right!=0) $fatal(1,"left balance");
 set_knob(2,65536);if(pcm_left!=0 || pcm_right!=2000) $fatal(1,"right balance");
 set_knob(1,32768);set_knob(2,32768);
 panel_a=-4000;panel_b=-8000;cycles(10);
 if(pcm_left!=-3000 || pcm_right!=-3000) $fatal(1,"signed mix");
 panel_a=400000;panel_b=800000;cycles(10);
 if(pcm_left!=32767) $fatal(1,"positive clipping");
 panel_a=-400000;panel_b=-800000;cycles(10);
 if(pcm_right!=-32768) $fatal(1,"negative clipping");
 panel_a=4000;panel_b=8000;test_atten=1;cycles(10);
 if(pcm_left!=375) $fatal(1,"test attenuation");
 set_knob(4,0);slow_step=dut.phase_step;
 set_knob(4,65536);fast_step=dut.phase_step;
 if(slow_step!=43238 || fast_step!=864761) $fatal(1,"vibrato rates");
 set_knob(3,65536);low_pitch=999999;high_pitch=0;
 for(i=0;i<5100;i=i+1) begin
  frames(1);
  if(modulated_pitch<low_pitch) low_pitch=modulated_pitch;
  if(modulated_pitch>high_pitch) high_pitch=modulated_pitch;
 end
 if(low_pitch<63569 || low_pitch>63600 || high_pitch<67460 || high_pitch>67502)
  $fatal(1,"vibrato extrema %0d %0d",low_pitch,high_pitch);
 set_knob(3,0);base_pitch=131072;frames(5);
 if(modulated_pitch!=131072) $fatal(1,"zero-depth pitch bypass");
 set_knob(0,131071);if(master!=65536) $fatal(1,"input clamp");
 $display("PASS migration knobs");$finish;
end
initial begin #10000000;$fatal(1,"timeout");end
endmodule
