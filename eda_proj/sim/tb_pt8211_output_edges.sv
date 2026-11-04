`timescale 1ns/1ps
// PT8211 captures DIN on rising BCK. The FPGA must launch DIN/WS on
// falling BCK, giving a half-bit setup/hold margin at the DAC pins.
module tb_pt8211_output_edges;
 reg clk_1p536m=0,rst_n=0;
 always #314.593 clk_1p536m=~clk_1p536m;
 reg [15:0] idata=16'h5aa5;
 wire req,HP_BCK,HP_WS,HP_DIN;
 audio_drive dut(.*);
 integer changes=0,cycles=0;
 realtime last_change=0;
 always @(HP_DIN or HP_WS)if(rst_n && cycles>5)begin
  changes=changes+1;last_change=$realtime;
  if(HP_BCK!==0)$fatal(1,"DAC launch collision: DIN/WS changes on rising/high BCK at %0t",$time);
 end
 always @(posedge HP_BCK)if(rst_n)begin
  cycles=cycles+1;
  if(cycles>10 && $realtime-last_change<300.0)$fatal(1,"DAC setup margin less than 300ns");
  if(req)idata<=idata+16'h0103;
 end
 initial begin
  #1000;rst_n=1;repeat(4096)@(negedge HP_BCK);#2;
  if(changes<100)$fatal(1,"insufficient edge checks");
  $display("PASS PT8211 pin launch: DIN/WS falling-edge-only changes=%0d setup>=300ns",changes);$finish;
 end
endmodule
