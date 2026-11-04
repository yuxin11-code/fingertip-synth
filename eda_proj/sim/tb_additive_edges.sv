`timescale 1ns/1ps
// Directed checks independent of the Python oracle. RAM injection is limited
// to boundary values that would otherwise take millions of decay frames.
module tb_additive_edges;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,frame_tick=0;
 reg [31:0] v_gate=0;reg [255:0] v_note={32{8'd60}};
 reg [95:0] v_inst=0;reg [17:0] pitch_scale_q16=65536;
 reg [7:0] a_param=0,d_param=255,s_param=255,r_param=255;
 reg [7:0] guitar_d_param=255,guitar_r_param=255;
 wire signed [39:0] mix_sum,panel_a_sum,panel_b_sum;
 wire [9:0] active_osc,observed_voice;wire [5:0] sounding_voices;wire [39:0] env_observe;
 wire busy,ready,sample_valid,deadline_error;
 mig_additive_engine dut(.*);
 integer i,frames=0;
 reg [31:0] first_phase;
 task start_frame;begin
  @(negedge clk);frame_tick=1;@(negedge clk);frame_tick=0;
 end endtask
 task finish_frame;integer n;begin
  n=0;while(!sample_valid && n<600)begin @(negedge clk);n=n+1;end
  if(n>=600)$fatal(1,"frame did not finish");frames=frames+1;
 end endtask
 task reset_engine;begin
  @(negedge clk);rst_n=0;repeat(3)@(negedge clk);rst_n=1;
  wait(ready);@(negedge clk);
  if(busy || sample_valid || deadline_error || active_osc!=0 || mix_sum!=0)$fatal(1,"reset control state");
  for(i=0;i<512;i=i+1)if(dut.oscillator[i]!==64'd0)$fatal(1,"RAM scrub index=%0d",i);
 end endtask
 initial begin
  reset_engine;
  // Even with gate low and zero amplitude, all independent DDS phases run.
  start_frame;finish_frame;
  if(active_osc!=0 || mix_sum!=0)$fatal(1,"silent frame");
  if(dut.oscillator[0][63:32]==0 || dut.oscillator[1][63:32]==dut.oscillator[0][63:32])$fatal(1,"independent DDS frequency");
  first_phase=dut.oscillator[0][63:32];
  start_frame;finish_frame;
  if(dut.oscillator[0][63:32]!==first_phase+first_phase)$fatal(1,"silent phase continuity");
  // Minimum negative envelope step must remove the last LSB without wrap.
  @(negedge clk);dut.oscillator[0]={32'd0,32'd1};
  start_frame;finish_frame;
  if(dut.oscillator[0][31:0]!==0)$fatal(1,"release residual LSB");
  // Strict > -66 dB threshold, applied AFTER this sample's envelope update.
  // Release sh=16 here: these amplitudes decrease by exactly 17 LSBs.
  @(negedge clk);
  dut.oscillator[0]={32'd0,32'd1076308};
  dut.oscillator[1]={32'd0,32'd1076309};
  start_frame;finish_frame;
  if(dut.oscillator[0][31:0]!==1076291 || dut.oscillator[1][31:0]!==1076292 || active_osc!==1)
   $fatal(1,"activity threshold: amps=%d/%d count=%d",dut.oscillator[0][31:0],dut.oscillator[1][31:0],active_osc);
  // High absolute frequencies must be silent even with nonzero amplitudes.
  v_note={32{8'd135}};v_gate=32'hffffffff;pitch_scale_q16=262143;
  start_frame;finish_frame;
  if(active_osc!=0 || mix_sum!=0)$fatal(1,"alias mute");
  if(dut.oscillator[0][31:0]==0)$fatal(1,"muted oscillators lost amplitude state");
  // Reset in a live pipeline must suppress late state writes and commits.
  start_frame;repeat(100)@(negedge clk);reset_engine;
  v_gate=0;v_note={32{8'd60}};pitch_scale_q16=65536;
  start_frame;finish_frame;
  if(active_osc!=0 || mix_sum!=0)$fatal(1,"stale state after warm reset");
  // An overlapping frame is rejected and raises the sticky diagnostic.
  start_frame;repeat(15)@(negedge clk);start_frame;
  if(deadline_error!==1)$fatal(1,"missing overlap diagnostic");
  finish_frame;repeat(10)@(negedge clk);
  if(deadline_error!==1)$fatal(1,"diagnostic was not sticky");
  reset_engine;
  $display("PASS additive edges: RAM scrub, independent DDS, minimum release, strict threshold, alias mute, mid-frame reset, sticky deadline; frames=%0d",frames);
  $finish;
 end
 initial begin #200000;$fatal(1,"edge watchdog");end
endmodule
