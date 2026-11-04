`timescale 1ns/1ps
module tb_engine_diag;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,frame_tick=0,busy=0,sample_valid=0;
 wire [11:0] last_frame_cycles;
 wire [31:0] deadline_count,sample_count;
 mig_engine_diagnostics dut(.*);
 initial begin
  repeat(3)@(negedge clk);rst_n=1;
  frame_tick=1;@(negedge clk);frame_tick=0;busy=1;
  repeat(560)@(negedge clk);
  sample_valid=1;busy=0;@(negedge clk);sample_valid=0;
  if(last_frame_cycles!=560 || sample_count!=1 || deadline_count!=0)
   $fatal(1,"frame metrics: %0d %0d %0d",last_frame_cycles,sample_count,deadline_count);
  busy=1;frame_tick=1;@(negedge clk);frame_tick=0;
  if(deadline_count!=1)$fatal(1,"deadline count");
  rst_n=0;@(negedge clk);
  if(last_frame_cycles!=0 || sample_count!=0 || deadline_count!=0)
   $fatal(1,"reset did not clear diagnostics");
  $display("PASS engine diagnostic cycles, missed frame, reset");$finish;
 end
endmodule
