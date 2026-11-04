`timescale 1ns/1ps
module tb_hmi_decimal;
 `include "hmi_defs.vh"
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,cmd_valid=0;reg [7:0] cmd=0;reg [15:0] value=0;
 reg [HMI_TX_FIELD_COUNT*32-1:0] fields=0;wire tx;wire [3:0] current_page;wire [31:0] byte_count;
 wire page_valid=0,screen_reset=0;wire [15:0] page_id=0;
 wire aux_valid=0,aux_last=0;wire [7:0] aux_data=0;wire aux_ready;
 hmi_tx #(.CLK_HZ(1843200),.FIELD_COUNT(HMI_TX_FIELD_COUNT)) dut(.*);
 wire [7:0] data;wire valid,frame_error;
 hmi_uart_rx #(.CLK_HZ(1843200)) rx(.clk(clk),.rst_n(rst_n),.rx(tx),.data(data),.valid(valid),.frame_error(frame_error));
 reg [7:0] frame[0:31];integer frame_len=0,latest=-1,latest_signed=32'h7fffffff,i,nmag;
 integer home_osc=-1,home_voices=-1,home_tenths=-1;
 reg [31:0] tail=0;
 always @(negedge clk)begin
  if(frame_error)$fatal(1,"TX framing");
  if(valid)begin
   frame[frame_len]=data;frame_len=frame_len+1;tail={tail[23:0],data};
   if(tail==32'hcc33c33c)begin
    if(frame[0]!=8'haa || frame[1]!=8'hb1 || (frame_len<9 && !(frame_len==7 && frame[2]==1)))$fatal(1,"native frame");
    if({frame[3],frame[4]}==9 && {frame[5],frame[6]}==52)begin
     if(frame_len!=17)$fatal(1,"unsigned text frame length");
     latest=0;for(i=7;i<=12;i=i+1)latest=latest*10+frame[i]-8'h30;
    end
    if({frame[3],frame[4]}==5 && {frame[5],frame[6]}==92)begin
     if(frame_len!=17)$fatal(1,"signed text frame length");
     nmag=0;for(i=8;i<=12;i=i+1)nmag=nmag*10+frame[i]-8'h30;
     latest_signed=(frame[7]==8'h2d)?-nmag:nmag;
    end
    if({frame[3],frame[4]}==0 && {frame[5],frame[6]}==5)begin
     if(frame_len!=14)$fatal(1,"active oscillator field width");
     home_osc=(frame[7]-48)*100+(frame[8]-48)*10+frame[9]-48;
    end
    if({frame[3],frame[4]}==0 && {frame[5],frame[6]}==6)begin
     if(frame_len!=13)$fatal(1,"sounding voice field width");
     home_voices=(frame[7]-48)*10+frame[8]-48;
    end
    if({frame[3],frame[4]}==0 && {frame[5],frame[6]}==7)begin
     if(frame_len!=15 || frame[9]!=8'h2e)$fatal(1,"throughput fixed point format");
     home_tenths=(frame[7]-48)*100+(frame[8]-48)*10+frame[10]-48;
    end
    frame_len=0;tail=0;
   end else if(frame_len>=32)$fatal(1,"unterminated native frame");
  end
 end
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 task page(input [15:0] p);begin value=p;cmd='h1f;cmd_valid=1;cycles(1);cmd_valid=0;end endtask
 task check(input [31:0] v);integer n;begin
  fields[HMI_FIELD_P9_C52_DURATION_MS*32+:32]=v;n=0;
  while(latest!=v && n<80000)begin cycles(1);n=n+1;end
  if(latest!=v)$fatal(1,"decimal %0d vs %0d",latest,v);
 end endtask
 task check_signed(input signed [31:0] v);integer n;begin
  fields[HMI_FIELD_P5_C92_SEMITONE*32+:32]=v;n=0;
  while(latest_signed!=v && n<250000)begin cycles(1);n=n+1;end
  if(latest_signed!=v)$fatal(1,"signed %0d vs %0d",latest_signed,v);
 end endtask
 initial begin
  cycles(5);rst_n=1;page(9);
  check(0);check(1);check(9);check(10);check(99);check(100);check(999);
  check(1000);check(65536);check(999999);
  page(65535);cycles(6000);page(5);
  check_signed(-12);check_signed(12);check_signed(0);check_signed(-99999);check_signed(99999);
  page(65535);cycles(6000);page(0);
  fields[HMI_FIELD_P0_C5_ACTIVE_OSC*32+:32]=512;
  fields[HMI_FIELD_P0_C6_SOUNDING_VOICES*32+:32]=32;
  fields[HMI_FIELD_P0_C7_THROUGHPUT*32+:32]=254;
  i=0;while((home_osc!=512 || home_voices!=32 || home_tenths!=254) && i<300000)begin cycles(1);i=i+1;end
  if(home_osc!=512 || home_voices!=32 || home_tenths!=254)$fatal(1,"home formats: %0d %0d %0d",home_osc,home_voices,home_tenths);
  $display("PASS HMI decimals and home 512/32/25.4 formats");$finish;
 end
endmodule
