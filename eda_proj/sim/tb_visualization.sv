`timescale 1ns/1ps
module tb_visualization;
 `include "hmi_defs.vh"
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,cmd_valid=0;reg [7:0] cmd=0;reg [15:0] value=0;
 reg [10:0] sample_div=0;wire tick=sample_div==0;
 integer sample_index=0;real phase;
 reg signed [15:0] left=0,right=0;reg signed [39:0] panel_a=0,panel_b=0;
 always @(posedge clk)begin
  if(!rst_n)begin sample_div<=0;sample_index<=0;end
  else begin
   sample_div<=(sample_div==1056)?0:sample_div+1'b1;
   if(tick)begin
    sample_index<=sample_index+1;phase=6.283185307179586*391.99543598*sample_index/49667.358398438;
    left<=1000*$sin(phase);right<=1000*$cos(phase);
    panel_a<=16*20000*$sin(phase);panel_b<=16*16000*$cos(phase);
   end
  end
 end
 wire [3:0] page;wire av,al,ar,afe,lmode;wire [7:0] ad;wire tx;wire [31:0] txbytes;
 reg [HMI_TX_FIELD_COUNT*32-1:0] fields=0;
 hmi_tx #(.CLK_HZ(1843200),.FIELD_COUNT(HMI_TX_FIELD_COUNT)) transmitter(.clk(clk),.rst_n(rst_n),.cmd_valid(cmd_valid),.cmd(cmd),.value(value),.fields(fields),.tx(tx),.current_page(page),.byte_count(txbytes),.aux_valid(av),.aux_last(al),.aux_frame_end(afe),.aux_data(ad),.aux_ready(ar));
 mig_visualization #(.CLK_HZ(1843200)) graphics(.clk(clk),.rst_n(rst_n),.frame_tick(tick),.page(page),.pcm_left(left),.pcm_right(right),.panel_a(panel_a),.panel_b(panel_b),.env_observe({3'd3,17'd40000}),.a(4'd5),.d(4'd4),.s(4'd8),.r(4'd6),.cmd_valid(cmd_valid),.cmd(cmd),.value(value),.aux_valid(av),.aux_last(al),.aux_frame_end(afe),.aux_data(ad),.aux_ready(ar),.liss_mode(lmode));
 wire [7:0] byte_data;wire byte_valid,frame_error;
 hmi_uart_rx #(.CLK_HZ(1843200)) monitor(.clk(clk),.rst_n(rst_n),.rx(tx),.data(byte_data),.valid(byte_valid),.frame_error(frame_error));
 reg [7:0] packet[0:255];reg [31:0] tail=0;integer n=0,frames=0,curves=0,home_curves=0,moves=0,bars=0,dots=0,illegal=0,cycle=0,stream;
 reg [15:0] ctrl,packet_page;reg [11:0] peak=0;integer peak_bin=0,published=0;
 initial stream=$fopen("results/integration/visualization_screen.bin","wb");
 always @(negedge clk)begin
  cycle=cycle+1;
  if(graphics.spec_valid)begin
   published=published+1;
   if(graphics.spec_mag>peak)begin peak=graphics.spec_mag;peak_bin=graphics.spec_addr;end
  end
  if(frame_error)$fatal(1,"UART frame error");
  if(byte_valid)begin
   for(integer b=0;b<8;b=b+1)$fwrite(stream,"%c",(64'(cycle)>>(8*b))&255);
   $fwrite(stream,"%c",byte_data);packet[n]=byte_data;n=n+1;tail={tail[23:0],byte_data};
   if(tail==32'hcc33c33c)begin
    frames=frames+1;ctrl={packet[5],packet[6]};packet_page={packet[3],packet[4]};
    if(packet[0]!=8'haa)illegal=illegal+1;
    if(packet[1]==8'h66)begin
     if(n!=246 && n!=46)$fatal(1,"native polyline packet size");
     for(integer q=2;q<n-4;q=q+4)
      if({packet[q],packet[q+1]}<24 || {packet[q],packet[q+1]}>452 || {packet[q+2],packet[q+3]}<64 || {packet[q+2],packet[q+3]}>218)$fatal(1,"native XY bounds");
     moves=moves+(n-6)/4-1;
    end else if(packet[1]!=8'hb1 && packet[1]!=8'h50 && packet[1]!=8'h6a)illegal=illegal+1;
    if(packet[1]==8'hb1 && packet[2]==8'h32)begin
     if(packet_page==0)begin
      if(n!=78 || packet[9]!=64)$fatal(1,"home curve format");home_curves++;
     end else begin
      if(n!=142 || packet[9]!=128 || (packet_page!=2 && packet_page!=5))$fatal(1,"curve format");curves++;
     end
     for(integer i=10;i<n-4;i=i+1)if(packet[i]>100 || ^packet[i]===1'bx)$fatal(1,"curve point %d",packet[i]);
    end
    if(packet[1]==8'hb1 && packet[2]==8'h28 && packet_page==4)$fatal(1,"obsolete scatter controls");
    if(packet[1]==8'hb1 && packet[2]==8'h10 && packet_page==3 && ctrl>=101 && ctrl<=132)begin
     if(n!=135)$fatal(1,"spectrum batch");bars=bars+16;
     for(integer q=3;q<n-4;q=q+8)if(^packet[q+7]===1'bx || packet[q+7]>100)$fatal(1,"spectrum bar");
    end
    if(packet[2]==8'h28 && packet_page==5 && ctrl==61)begin
     if({packet[7],packet[8]}<20 || {packet[7],packet[8]}>276 || {packet[9],packet[10]}<176 || {packet[9],packet[10]}>249)$fatal(1,"ADSR dot outside plot");
     dots=dots+1;
    end
    n=0;tail=0;
   end else if(n>250)$fatal(1,"unbounded packet");
  end
 end
 task cycles(input integer count);repeat(count)@(negedge clk);endtask
 task command(input [7:0] c,input [15:0] v);begin @(negedge clk);cmd=c;value=v;cmd_valid=1;cycles(1);cmd_valid=0;cycles(2);end endtask
 initial begin
  cycles(10);rst_n=1;cycles(10);command(8'h1f,0);wait(home_curves>=1);command(8'h1f,2);wait(curves>=1);
  command(8'h40,3);if(graphics.decim!=3)$fatal(1,"wave decimation");
  command(8'h1f,4);wait(moves>=127);command(8'h41,1);if(!lmode)$fatal(1,"L/R mode");wait(moves>=254);
  command(8'h1f,3);wait(published>=32);wait(bars>=32);
  if(peak==0 || peak_bin<15 || peak_bin>18)$fatal(1,"375/420Hz real-band peak=%0d bin=%0d",peak,peak_bin);
  command(8'h1f,5);wait(curves>=2);wait(dots>=1);
  // Let the current frame finish; close exactly at a protocol boundary.
  wait(n==0);$fclose(stream);if(illegal)$fatal(1,"illegal=%0d",illegal);
  $display("PASS home64/waveform128/trigger/decimation; spectrum32 actual tone peakbin=%0d; native liss128 A+B/LR; ADSR128/live dot bounds; frames=%0d illegal=0",peak_bin,frames);$finish;
 end
 initial begin cycles(3500000);$fatal(1,"visualization watchdog curves=%0d moves=%0d bars=%0d dots=%0d state=%0d",curves,moves,bars,dots,graphics.sender.state);end
endmodule
