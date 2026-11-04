`timescale 1ns/1ps
module tb_hmi_status;
 `include "hmi_defs.vh"
 reg clk=0;always #5 clk=~clk;reg rst_n=0;
 reg [HMI_TX_FIELD_COUNT*32-1:0] fields=0;wire tx;wire [7:0] d;wire dv;
 hmi_tx #(.CLK_HZ(1843200),.FIELD_COUNT(HMI_TX_FIELD_COUNT)) sender(.clk(clk),.rst_n(rst_n),.fields(fields),.cmd_valid(1'b0),.cmd(8'd0),.value(16'd0),.page_valid(1'b0),.screen_reset(1'b0),.page_id(16'd0),.aux_valid(1'b0),.aux_last(1'b0),.aux_data(8'd0),.tx(tx));
 hmi_uart_rx #(.CLK_HZ(1843200)) monitor(.clk(clk),.rst_n(rst_n),.rx(tx),.data(d),.valid(dv));
 reg [7:0] pkt[0:31];integer n=0;reg [31:0] tail=0;bit voices=0,timbre=0;
 always @(negedge clk)if(dv)begin
  pkt[n]=d;n++;tail={tail[23:0],d};
  if(tail==32'hcc33c33c)begin
   if(n>9 && {pkt[5],pkt[6]}==915)begin
    if(n!=13 || pkt[7]!="3" || pkt[8]!="2")$fatal(1,"32 voices truncated");voices=1;
   end
   if(n>9 && {pkt[5],pkt[6]}==910)begin
    if(n!=15 || {pkt[7],pkt[8],pkt[9],pkt[10]}!=32'hb8d6c7d9)$fatal(1,"GBK timbre name");timbre=1;
   end
   n=0;tail=0;
  end
 end
 initial begin
  fields[HMI_FIELD_P0_C915_BAR_VOICES*32+:32]=32;repeat(5)@(negedge clk);rst_n=1;
  wait(voices && timbre);$display("PASS shared status: two-digit 32 voices and GBK timbre names");$finish;
 end
 initial begin repeat(400000)@(negedge clk);$fatal(1,"status watchdog");end
endmodule
