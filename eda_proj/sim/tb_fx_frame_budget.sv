`timescale 1ns/1ps
// Fixed 1057-cycle frame cadence, including all three effects together.
module tb_fx_frame_budget;
 reg clk=0; always #5 clk=~clk;
 reg rst_n=0,frame_tick=0;
 reg signed [15:0] dry_l=0,dry_r=0;
 reg rev_en=0,dly_en=0,cho_en=0;
 reg [1:0] rev_mix=3,rev_decay=3,rev_damp=3;
 reg [1:0] dly_mix=3,dly_time=3,dly_fb=3;
 reg [1:0] cho_mix=3,cho_rate=3,cho_depth=3;
 wire signed [15:0] wet_l,wet_r;
 wire fx_active,ready,busy,sample_valid;
 fx_chain dut(.*);
 integer n,j,outputs=0,age=0,max_age=0,frame_outputs=0;
 reg started=0,bypass_q=0;
 reg signed [15:0] expected_l,expected_r;
 always @(negedge clk)if(rst_n && started)begin
  age=age+1;
  if(sample_valid)begin
   outputs=outputs+1;frame_outputs=frame_outputs+1;
   if(frame_outputs!=1)$fatal(1,"multiple outputs per frame");
   if(^wet_l===1'bx || ^wet_r===1'bx)$fatal(1,"unknown FX output");
   if(bypass_q && (wet_l!==expected_l || wet_r!==expected_r))
    $fatal(1,"bypass mismatch during effect switching");
   if(age>max_age)max_age=age;
   // The synth consumes at most 562 clocks, leaving 495 of 1057.
   if(age>=495)$fatal(1,"FX exceeds post-synth budget: %0d",age);
  end
 end
 initial begin
  repeat(4)@(negedge clk);rst_n=1;wait(ready);
  for(n=0;n<5000;n=n+1)begin
   @(posedge clk);#1;
   if(busy || !ready)$fatal(1,"frame blocked n=%0d",n);
   if(n!=0 && frame_outputs!=1)$fatal(1,"missing output n=%0d",n-1);
   {rev_en,dly_en,cho_en}=(n<2500)?3'b111:((n/64)%8);
   rev_decay=n[9:8];rev_damp=n[8:7];dly_time=n[8:7];dly_fb=n[10:9];
   cho_rate=n[9:8];cho_depth=n[8:7];
   dry_l=(n*47)%20001-10000;dry_r=(n*73)%16001-8000;
   expected_l=dry_l;expected_r=dry_r;bypass_q=!(rev_en|dly_en|cho_en);
   frame_outputs=0;age=0;started=1;frame_tick=1;
   @(posedge clk);#1;frame_tick=0;
   repeat(1056)@(posedge clk);
  end
  #2;
  if(frame_outputs!=1 || outputs!=5000)$fatal(1,"output count %0d",outputs);
  $display("PASS FX fixed-frame stress: accepted=5000 outputs=%0d max_cycles=%0d budget=495 all-effects plus switching",outputs,max_age);
  $finish;
 end
 initial begin #100000000;$fatal(1,"FX budget watchdog");end
endmodule
