`timescale 1ns/1ps
module tb_score_guide;
 localparam HZ=1843200;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,rx=1;
 wire [7:0] data,ptype,plen;wire [15:0] pseq;
 wire byte_valid,frame_error,packet_valid,packet_error;wire [95:0] payload;
 score_uart_rx #(.CLK_HZ(HZ)) uart(.clk(clk),.rst_n(rst_n),.rx(rx),.rx_data(data),.rx_valid(byte_valid),.frame_error(frame_error));
 score_frame_rx #(.CLK_HZ(HZ)) parser(.clk(clk),.rst_n(rst_n),.rx_data(data),.rx_valid(byte_valid),.rx_error(frame_error),.packet_valid(packet_valid),.packet_error(packet_error),.packet_type(ptype),.packet_seq(pseq),.packet_len(plen),.payload(payload));
 wire receiving,score_valid,receive_error,we;wire [15:0] received,ncount,bpm,tpb;wire [31:0] duration;
 wire [7:0] waddr,raddr;wire [87:0] wdata,rdata;wire rd;
 score_loader #(.CLK_HZ(HZ)) loader(.clk(clk),.rst_n(rst_n),.packet_valid(packet_valid),.packet_error(packet_error),.packet_type(ptype),.packet_seq(pseq),.packet_len(plen),.payload(payload),.receiving(receiving),.score_valid(score_valid),.receive_error(receive_error),.received_count(received),.note_count(ncount),.bpm(bpm),.ticks_per_beat(tpb),.length_ticks(duration),.ram_we(we),.ram_waddr(waddr),.ram_wdata(wdata));
 score_ram memory(.clk(clk),.we(we),.waddr(waddr),.wdata(wdata),.rd_en(rd),.raddr(raddr),.rdata(rdata));
 reg cmd_valid=0;reg [7:0] cmd=0;reg [15:0] keys=0;
 wire active,paused,wait_mode,ready,waiting,completed;wire [1:0] speed;
 wire [15:0] lane_now,lane_next,lane_hit,lane_miss,score,combo;wire [6:0] accuracy,progress;
 wire [31:0] song_tick,clk_per_tick,window_ticks;
 score_guide #(.CLK_HZ(HZ)) guide(.clk(clk),.rst_n(rst_n),.score_valid(score_valid),.note_count(ncount),.bpm(bpm),.ticks_per_beat(tpb),.length_ticks(duration),.ram_data(rdata),.ram_rd(rd),.ram_addr(raddr),.cmd_valid(cmd_valid),.cmd(cmd),.keys(keys),.active(active),.paused(paused),.wait_mode(wait_mode),.speed(speed),.lane_now(lane_now),.lane_next(lane_next),.lane_hit(lane_hit),.lane_miss(lane_miss),.score(score),.combo(combo),.accuracy(accuracy),.progress(progress),.song_tick(song_tick),.clk_per_tick(clk_per_tick),.window_ticks(window_ticks),.ready(ready),.waiting(waiting),.completed(completed));
 `include "hmi_defs.vh"
 reg [HMI_TX_FIELD_COUNT*32-1:0] fields;
 integer k;
 always @*begin
  fields=0;
  for(integer j=0;j<16;j=j+1)fields[(HMI_FIELD_P7_C133_GAME_LANE_0+j)*32+:32]=lane_hit[j]?3:lane_miss[j]?4:lane_now[j]?2:lane_next[j]?1:0;
  fields[HMI_FIELD_P7_C70_GAME_NOTE_COUNT*32+:32]=ncount;
  fields[HMI_FIELD_P7_C71_GAME_SCORE*32+:32]=score;
  fields[HMI_FIELD_P7_C72_GAME_COMBO*32+:32]=combo;
  fields[HMI_FIELD_P7_C73_GAME_ACCURACY*32+:32]=accuracy;
  fields[HMI_FIELD_P7_C74_GAME_PROGRESS*32+:32]=progress;
  fields[HMI_FIELD_P7_C75_GAME_STATE*32+:32]={31'd0,!score_valid};
 end
 reg page_cmd=0;wire tx;wire [3:0] page;wire [31:0] bytes_sent;
 hmi_tx #(.CLK_HZ(HZ),.FIELD_COUNT(HMI_TX_FIELD_COUNT)) sender(.clk(clk),.rst_n(rst_n),.cmd_valid(page_cmd),.cmd(8'h1f),.value(16'd7),.fields(fields),.tx(tx),.current_page(page),.byte_count(bytes_sent),.aux_valid(1'b0),.aux_last(1'b0),.aux_data(8'd0),.aux_ready());
 wire [7:0] screen_byte;wire screen_valid,screen_error;
 hmi_uart_rx #(.CLK_HZ(HZ)) monitor(.clk(clk),.rst_n(rst_n),.rx(tx),.data(screen_byte),.valid(screen_valid),.frame_error(screen_error));
 integer stream,cycle=0,frames=0,nbytes=0;reg [31:0] tail=0;
 initial stream=$fopen("results/integration/score_guide_screen.bin","wb");
 always @(negedge clk)begin
  cycle=cycle+1;
  if(packet_error || frame_error || receive_error || screen_error)$fatal(1,"frame/loader error");
  if(screen_valid)begin
   for(integer b=0;b<8;b=b+1)$fwrite(stream,"%c",(64'(cycle)>>(8*b))&255);
   $fwrite(stream,"%c",screen_byte);tail={tail[23:0],screen_byte};nbytes=nbytes+1;
   if(tail==32'hcc33c33c)begin frames=frames+1;nbytes=0;end
  end
 end
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 task command(input [7:0] c);begin @(negedge clk);cmd=c;cmd_valid=1;cycles(1);cmd_valid=0;cycles(2);end endtask
 task byte_send(input [7:0] v);begin rx=0;cycles(16);for(integer j=0;j<8;j=j+1)begin rx=v[j];cycles(16);end rx=1;cycles(32);end endtask
 function [15:0] crcbyte(input [15:0] c,input [7:0] d);reg [15:0] r;begin r=c^{d,8'd0};repeat(8)r=r[15]?(r<<1)^16'h1021:r<<1;crcbyte=r;end endfunction
 task packet(input [7:0] kind,input [15:0] seq,input [7:0] len,input [95:0] body);
  reg [7:0] b[0:19];reg [15:0] crc;
  begin b[0]=8'haa;b[1]=8'h55;b[2]=kind;b[3]=seq[7:0];b[4]=seq[15:8];b[5]=len;
   for(integer j=0;j<12;j=j+1)b[6+j]=body[j*8+:8];
   crc=16'hffff;for(integer j=2;j<18;j=j+1)crc=crcbyte(crc,b[j]);b[18]=crc[7:0];b[19]=crc[15:8];
   for(integer j=0;j<20;j=j+1)byte_send(b[j]);cycles(10);
  end
 endtask
 integer pitches[0:9];integer hold_tick;
 initial begin
  pitches[0]=60;pitches[1]=62;pitches[2]=64;pitches[3]=65;pitches[4]=67;pitches[5]=69;pitches[6]=71;pitches[7]=72;pitches[8]=74;pitches[9]=76;
  cycles(10);rst_n=1;cycles(10);page_cmd=1;cycles(1);page_cmd=0;
  packet(1,0,12,{32'd140,16'd96,16'd120,16'd10,8'd0,8'd1});
  for(k=0;k<10;k=k+1)packet(2,k+1,11,{8'd0,8'd0,8'd100,8'(pitches[k]),32'd3,32'(5+k*10)});
  packet(3,11,2,96'd10);
  wait(ready);cycles(3);
  if(!score_valid || ncount!=10 || clk_per_tick!=9600 || window_ticks!=19)$fatal(1,"metadata/conversion %0d %0d",clk_per_tick,window_ticks);
  command(8'h50);
  for(k=0;k<10;k=k+1)begin
   wait(lane_now==(16'h1<<k));hold_tick=song_tick;cycles(30000);
   if(song_tick!=hold_tick || !waiting)$fatal(1,"practice auto skipped note %0d",k);
   if(k==0)begin keys=2;cycles(100);keys=0;cycles(100);if(lane_now!=1)$fatal(1,"wrong key advanced");end
   if(k==1)begin command(8'h51);cycles(20000);if(!paused || song_tick!=hold_tick)$fatal(1,"practice pause");command(8'h51);end
   keys=16'h1<<k;cycles(100);keys=0;cycles(100);
  end
  wait(completed);cycles(100);
  if(score!=1000 || guide.hits!=10 || guide.misses!=0 || accuracy!=100)$fatal(1,"practice result score=%0d",score);
  command(8'h53);if(!wait_mode)$fatal(1,"legacy mode command restored timed skipping");
  command(8'h54);wait(!ready);wait(ready);if(clk_per_tick!=12800 || speed!=1)$fatal(1,"75 percent");
  command(8'h54);wait(!ready);wait(ready);if(clk_per_tick!=19200 || speed!=2)$fatal(1,"50 percent");
  command(8'h52);if(active)$fatal(1,"stop");
  // Stop TX at a complete frame boundary before closing the exported stream.
  wait(nbytes==0 && frames>20);$fclose(stream);
  $display("PASS ESP32 UART 10-note score: valid=1 practice hits=10 misses=0 score=1000 accuracy=100; indefinite wait/wrong key/pause/legacy safety; frames=%0d illegal=0",frames);$finish;
 end
 initial begin cycles(3000000);$fatal(1,"guide watchdog tick=%0d head=%0d state=%0d",song_tick,guide.head,guide.scan_state);end
endmodule
