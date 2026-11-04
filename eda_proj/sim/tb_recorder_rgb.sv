`timescale 1ns/1ps
module tb_recorder_rgb;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0;reg [23:0] color=24'h002000;wire data_out;
 mig_ws2812_color dut(.*);
 reg [23:0] word;
 time rise,fall,last_fall;integer b;
 task read_color;
  begin
   word=0;
   for(b=0;b<24;b=b+1)begin
    @(posedge data_out);rise=$time;@(negedge data_out);fall=$time;
    if(fall-rise!=180 && fall-rise!=370)$fatal(1,"invalid WS2812 high pulse");
    word={word[22:0],(fall-rise==370)};
   end
  end
 endtask
 initial begin
  repeat(5)@(negedge clk);rst_n=1;
  fork
   begin read_color;if(word!=24'h002000)$fatal(1,"red GRB order/torn frame %h",word);end
   begin @(posedge data_out);repeat(200)@(negedge clk);color=24'h200000;end
  join
  last_fall=$time;read_color;
  if(word!=24'h200000 || $time-last_fall<210000)$fatal(1,"green/latch interval");
  color=0;read_color;if(word!=0)$fatal(1,"off frame");
  $display("PASS RGB: actual WS2812 GRB pulse decoding, red/green/off, complete frame latching and reset interval");$finish;
 end
 initial begin #2000000;$fatal(1,"timeout");end
endmodule
