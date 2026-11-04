`timescale 1ns/1ps
module tb_hmi_pages;
 `define HMI_DEFINE_TX_TABLE
 `include "hmi_defs.vh"
 `undef HMI_DEFINE_TX_TABLE
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,byte_valid=0;reg [7:0] byte_data=0;
 wire cmd_valid;wire [7:0] cmd;wire [15:0] value;
 hmi_rx #(.CLK_HZ(1843200)) parser(.clk(clk),.rst_n(rst_n),.byte_valid(byte_valid),.byte_data(byte_data),.frame_error(1'b0),.cmd_valid(cmd_valid),.cmd(cmd),.value(value));
 reg [HMI_TX_FIELD_COUNT*32-1:0] fields;
 wire tx;wire [3:0] page;wire [31:0] byte_count;
 hmi_tx #(.CLK_HZ(1843200),.FIELD_COUNT(HMI_TX_FIELD_COUNT)) sender(.clk(clk),.rst_n(rst_n),.cmd_valid(cmd_valid),.cmd(cmd),.value(value),.fields(fields),.tx(tx),.current_page(page),.byte_count(byte_count),.aux_valid(1'b0),.aux_last(1'b0),.aux_data(8'd0),.aux_ready());
 wire [7:0] d;wire dv,fe;
 hmi_uart_rx #(.CLK_HZ(1843200)) monitor(.clk(clk),.rst_n(rst_n),.rx(tx),.data(d),.valid(dv),.frame_error(fe));
 bit seen[0:11][0:918];bit [15:0] updates[0:11][0:918];reg [7:0] packet[0:31];reg [31:0] tail=0;
 integer before_button,before_lamp;
 integer n=0,frames=0,cycle=0,stream,i,p,all_seen;reg [7:0] last_cmd=0;reg [15:0] last_value=0;
 initial stream=$fopen("results/integration/hmi_pages_screen.bin","wb");
 always @(negedge clk)begin
  cycle=cycle+1;
  if(cmd_valid)begin last_cmd=cmd;last_value=value;end
  if(fe)$fatal(1,"UART framing");
  if(dv)begin
   for(integer b=0;b<8;b=b+1)$fwrite(stream,"%c",(64'(cycle)>>(8*b))&255);
   $fwrite(stream,"%c",d);packet[n]=d;n=n+1;tail={tail[23:0],d};
   if(tail==32'hcc33c33c)begin
    if(packet[0]!=8'haa || packet[1]!=8'hb1)$fatal(1,"bad header");
    if(n!=7)seen[{packet[3],packet[4]}][{packet[5],packet[6]}]=1;if(n!=7)updates[{packet[3],packet[4]}][{packet[5],packet[6]}]++;frames=frames+1;n=0;tail=0;
   end else if(n>=32)$fatal(1,"unbounded frame");
  end
 end
 task cycles(input integer k);repeat(k)@(negedge clk);endtask
 task send(input [7:0] b);begin @(negedge clk);byte_data=b;byte_valid=1;cycles(1);byte_valid=0;cycles(1);end endtask
 task end_frame;begin send(8'hcc);send(8'h33);send(8'hc3);send(8'h3c);cycles(3);end endtask
 task go_page(input integer pg);begin send(8'haa);send(8'hb1);send(1);send(0);send(pg);end_frame;end endtask
 task button(input [15:0] pg,id,input [7:0] expected,input [15:0] v);begin
  send(8'haa);send(8'hb1);send(8'h11);send(pg[15:8]);send(pg[7:0]);send(id[15:8]);send(id[7:0]);send(8'h10);send(1);send(1);end_frame;
  if(last_cmd!=expected || last_value!=v)$fatal(1,"native button %d/%d cmd=%h value=%h",pg,id,last_cmd,last_value);
 end endtask
 task release_button(input [15:0] pg,id);begin
  send(8'haa);send(8'hb1);send(8'h11);send(pg[15:8]);send(pg[7:0]);send(id[15:8]);send(id[7:0]);send(8'h10);send(1);send(0);end_frame;
  if(last_cmd!=8'h7f)$fatal(1,"button release must request authoritative refresh");
 end endtask
 initial begin
  fields=0;for(i=0;i<HMI_TX_FIELD_COUNT;i=i+1)fields[i*32+:32]=1;
  cycles(5);rst_n=1;cycles(10);
  for(p=0;p<HMI_PAGE_COUNT;p=p+1)begin
   go_page(p);if(page!=p)$fatal(1,"page report");
   all_seen=0;
   while(!all_seen)begin
    cycles(100);all_seen=1;
    for(i=0;i<HMI_TX_FIELD_COUNT;i=i+1)if((hmi_field_page(i)==p || hmi_field_page(i)==14) && !seen[p][hmi_field_ctrl(i)])all_seen=0;
   end
  end
  button(2,24,8'h40,0);button(2,27,8'h40,3);
  button(4,65,8'h41,0);button(4,66,8'h41,1);
  for(i=0;i<3;i=i+1)button(7,40+i,8'h50+i,1);
  button(8,41,8'h10,1);button(8,42,8'h10,0);button(8,43,8'h11,1);button(8,44,8'h11,0);button(8,45,8'h14,0);
  button(5,40,1,0);button(5,49,2,4);button(1,91,8'h15,1);
  go_page(5);cycles(100000);before_button=updates[5][40];
  button(5,40,1,0);release_button(5,40);cycles(100000);
  if(updates[5][40]<=before_button)$fatal(1,"selected button not reasserted after release");
  go_page(7);cycles(100000);before_lamp=updates[7][133];
  release_button(5,40);cycles(30000);
  if(updates[7][133]!=before_lamp)$fatal(1,"unchanged game lamp retransmitted");
  wait(n==0);$fclose(stream);
  $display("PASS all10 native pages and generated TX fields; decimation/liss/game/timbre/panel notify ID mapping, release selection refresh and change-only lamps; frames=%0d illegal=0",frames);$finish;
 end
 initial begin cycles(2400000);$fatal(1,"page mapping watchdog page=%0d",page);end
endmodule
