`timescale 1ns/1ps
module tb_additive_hmi_count;
 `include "hmi_defs.vh"
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0;reg [HMI_TX_FIELD_COUNT*32-1:0] fields=0;
 wire tx;wire [7:0] data;wire valid;
 hmi_tx #(.CLK_HZ(1843200),.FIELD_COUNT(HMI_TX_FIELD_COUNT)) sender(
  .clk(clk),.rst_n(rst_n),.cmd_valid(1'b0),.cmd(8'd0),.value(16'd0),.fields(fields),
  .page_valid(1'b0),.page_id(16'd0),.screen_reset(1'b0),
  .aux_valid(1'b0),.aux_last(1'b0),.aux_data(8'd0),.tx(tx));
 hmi_uart_rx #(.CLK_HZ(1843200)) monitor(.clk(clk),.rst_n(rst_n),.rx(tx),.data(data),.valid(valid));
 reg [7:0] packet[0:31];reg [31:0] tail=0;integer n=0;
 always @(negedge clk)if(valid)begin
  packet[n]=data;n=n+1;tail={tail[23:0],data};
  if(tail==32'hcc33c33c)begin
   if(n>9 && {packet[5],packet[6]}==16'd5)begin
    if(n!=14 || {packet[7],packet[8],packet[9]}!="512")
     $fatal(1,"home c5 count truncated or malformed");
    $display("PASS additive HMI serial: home c5 active_osc=512 -> 512 compact decimal text");$finish;
   end
   n=0;tail=0;
  end
 end
 initial begin fields[HMI_FIELD_P0_C5_ACTIVE_OSC*32+:32]=512;repeat(5)@(negedge clk);rst_n=1;end
 initial begin repeat(300000)@(negedge clk);$fatal(1,"HMI count watchdog");end
endmodule
