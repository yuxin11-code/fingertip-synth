`timescale 1ns/1ps
// Checks the actual voice-engine PCM accumulator, not only the timbre register.
module tb_dual_five_pcm;
  reg clk=0; always #5 clk=~clk;
  reg rst_n=0, frame_tick=0;
  reg [31:0] v_gate=32'd1;
  reg [255:0] v_note=0;
  reg [95:0] v_inst=0;
  reg [17:0] pitch_scale_q16=18'd65536;
  reg [3:0] a_param=4'd6,d_param=4'd4,s_param=4'd12,r_param=4'd5;
  reg [15:0] guitar_attack=16'd256,guitar_sustain=16'd2048;
  reg [3:0] guitar_decay=4'd3,guitar_release=4'd3;
  wire signed [39:0] mix_sum,panel_a_sum,panel_b_sum;
  wire [39:0] env_observe;
  mig_voice_engine dut(.*);
  integer i; reg signed [39:0] pcm [0:4];
  task tick_frame;
    begin frame_tick=1; @(negedge clk); frame_tick=0; repeat(60) @(negedge clk); end
  endtask
  task run_inst(input integer n);
    begin
      rst_n=0; repeat(3) @(negedge clk); rst_n=1; repeat(3) @(negedge clk);
      v_inst=0; v_inst[2:0]=n[2:0]; v_note[7:0]=8'd60;
      repeat(8) tick_frame; pcm[n]=mix_sum;
    end
  endtask
  initial begin
    for(i=0;i<5;i=i+1) run_inst(i);
    for(i=0;i<5;i=i+1) begin
      if(pcm[i]===0) $fatal(1,"instrument %0d produced silent PCM",i);
      if(i>0 && pcm[i]===pcm[i-1]) $fatal(1,"instrument %0d PCM identical",i);
    end
    $display("PASS five timbre PCM: %0d %0d %0d %0d %0d",pcm[0],pcm[1],pcm[2],pcm[3],pcm[4]);
    $finish;
  end
  initial begin #1000000; $fatal(1,"timeout"); end
endmodule
