`timescale 1ns/1ps
// Parser/loader boundary tests; UART serialization is covered by score_guide.
module tb_score_protocol_edges;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,rx_valid=0,rx_error=0;reg [7:0] rx_data=0;
 wire packet_valid,packet_error;wire [7:0] packet_type,packet_len;
 wire [15:0] packet_seq;wire [95:0] payload;
 score_frame_rx #(.CLK_HZ(10000)) parser(.*);
 wire receiving,score_valid,receive_error,ram_we;
 wire [15:0] received_count,note_count,bpm,ticks_per_beat;
 wire [31:0] length_ticks;wire [7:0] ram_waddr;wire [87:0] ram_wdata;
 score_loader #(.CLK_HZ(10000)) loader(.*);
 integer valid_packets=0,errors=0,writes=0,n;
 reg track=0;reg [87:0] memory[0:255];
 always @(negedge clk)begin
  if(packet_valid)valid_packets=valid_packets+1;
  if(packet_error)errors=errors+1;
  if(ram_we)begin
   if(track && ram_waddr!==writes[7:0])$fatal(1,"RAM address %0d expected %0d",ram_waddr,writes);
   memory[ram_waddr]=ram_wdata;writes=writes+1;
  end
 end
 task put(input [7:0] b);begin
  @(posedge clk);#1;rx_data=b;rx_valid=1;
  @(posedge clk);#1;rx_valid=0;
 end endtask
 function [15:0] crcbyte(input [15:0] c,input [7:0] b);
  reg [15:0] r;begin r=c^{b,8'd0};repeat(8)r=r[15]?(r<<1)^16'h1021:r<<1;crcbyte=r;end
 endfunction
 task packet(input [7:0] kind,input [15:0] seq,input [7:0] len,input [95:0] body,input corrupt);
  reg [7:0] b[0:19];reg [15:0] crc;integer j;
  begin
   b[0]=8'haa;b[1]=8'h55;b[2]=kind;b[3]=seq[7:0];b[4]=seq[15:8];b[5]=len;
   for(j=0;j<12;j=j+1)b[6+j]=body[j*8+:8];
   crc=16'hffff;for(j=2;j<18;j=j+1)crc=crcbyte(crc,b[j]);
   b[18]=crc[7:0]^{7'd0,corrupt};b[19]=crc[15:8];
   for(j=0;j<20;j=j+1)put(b[j]);repeat(5)@(posedge clk);#1;
  end
 endtask
 task start(input [15:0] count);begin
  packet(1,0,12,{32'd1000,16'd96,16'd120,count,8'd0,8'd1},0);
 end endtask
 task note(input [15:0] seq,input [31:0] tick,input [31:0] duration);begin
  packet(2,seq,11,{8'd0,8'd0,8'd100,8'd60,duration,tick},0);
 end endtask
 initial begin
  repeat(4)@(posedge clk);#1;rst_n=1;
  start(256);track=1;
  for(n=0;n<256;n=n+1)note(n+1,n,1);
  packet(3,257,2,96'd256,0);track=0;
  if(!score_valid || receiving || receive_error || writes!=256 || note_count!=256)
   $fatal(1,"256-note boundary failed writes=%0d",writes);
  if(memory[0][31:0]!==0 || memory[255][31:0]!==255)$fatal(1,"RAM wrapped/corrupted");
  start(257);if(receiving || !receive_error || score_valid)$fatal(1,"257 accepted");
  start(1);note(2,0,1);if(receiving || !receive_error)$fatal(1,"out-of-order accepted");
  start(1);note(1,999,32'hffffffff);if(receiving || !receive_error)$fatal(1,"overflow duration accepted");
  start(1);packet(2,1,11,{8'd0,8'd0,8'd100,8'd60,32'd1,32'd0},1);
  if(receiving || !receive_error || score_valid)$fatal(1,"CRC error did not abort");
  start(1);put(8'haa);put(8'h55);put(8'h02);repeat(220)@(posedge clk);#1;
  if(receiving || !receive_error)$fatal(1,"truncated packet timeout did not abort");
  start(1);note(1,0,1);packet(3,2,2,96'd1,0);
  if(!score_valid || receive_error || receiving)$fatal(1,"protocol did not recover");
  if(errors!=2)$fatal(1,"parser errors=%0d expected CRC+timeout",errors);
  $display("PASS score protocol: 256-note RAM boundary, 257 rejection, sequence, duration overflow, CRC, truncation timeout, recovery; valid=%0d errors=%0d",valid_packets,errors);
  $finish;
 end
 initial begin #10000000;$fatal(1,"score edge watchdog");end
endmodule
