`timescale 1ns/1ps
// Constructed manual-format fixtures; real hardware Hex has NOT been supplied.
module tb_hmi_diagnostics;
 `include "hmi_defs.vh"
 reg clk=0;always #5 clk=~clk;reg rst_n=0,bv=0,fe=0;reg [7:0] bd=0;
 wire cv,fv,fi,pv,sr;wire [7:0] cmd;wire [15:0] value,pid;
 hmi_rx #(.CLK_HZ(1843200)) parser(.clk(clk),.rst_n(rst_n),.byte_valid(bv),.frame_error(fe),.byte_data(bd),.cmd_valid(cv),.cmd(cmd),.value(value),.frame_valid(fv),.frame_invalid(fi),.page_valid(pv),.page_id(pid),.screen_reset(sr));
 wire [3:0] page;wire tx;wire [31:0] bytes_sent;
 reg [HMI_TX_FIELD_COUNT*32-1:0] fields=0;
 hmi_tx #(.CLK_HZ(1843200),.FIELD_COUNT(HMI_TX_FIELD_COUNT),.LINK_DIAGNOSTICS(1),.HEARTBEAT_CLKS(100000),.QUERY_CLKS(60000)) sender(
 .clk(clk),.rst_n(rst_n),.cmd_valid(cv),.cmd(cmd),.value(value),.fields(fields),.aux_valid(1'b0),.aux_last(1'b0),.aux_data(8'd0),.page_valid(pv),.page_id(pid),.screen_reset(sr),.tx(tx),.current_page(page),.byte_count(bytes_sent));
 wire [2:0] il,ir;wire tm;
 mig_input_ctrl #(.CLK_HZ(1843200)) controls(.clk(clk),.rst_n(rst_n),.frame_tick(1'b0),.test_suspend(1'b0),.hmi_valid(cv),.hmi_cmd(cmd),.hmi_value(value),.selected_panel(1'b0),
 .keys_left(16'd0),.keys_right(16'd0),.strum_right(1'b0),.strum_left(1'b0),.key_up_n(1'b1),.key_dn_n(1'b1),.inst_left_n(1'b1),.inst_right_n(1'b1),
 .aux3_n(1'b1),.aux4_n(1'b1),.test_toggle_n(1'b1),.enc_a(1'b1),.enc_b(1'b1),.enc_c_n(1'b1),.transpose_left(8'sd0),.transpose_right(8'sd0),.inst_l(il),.inst_r(ir),.test_mode(tm));
 wire [7:0] td;wire tv,te;
 hmi_uart_rx #(.CLK_HZ(1843200)) monitor(.clk(clk),.rst_n(rst_n),.rx(tx),.data(td),.valid(tv),.frame_error(te));
 integer valid_frames=0,invalid_frames=0,queries=0,n=0,stream,cycle=0,hb_count=0,queries_saved;reg [10:0] hb_pages=0;reg [31:0] tail=0;reg [7:0] pkt[0:31];reg [7:0] last_cmd;reg [15:0] last_value;
 initial begin stream=$fopen("results/integration/debug/hmi_diagnostics_raw.bin","wb");if(stream==0)$fatal(1,"cannot open diagnostic stream");end
 always @(negedge clk)begin
  cycle++;if(fv)valid_frames++;if(fi)invalid_frames++;if(cv)begin last_cmd=cmd;last_value=value;end
  if(te)$fatal(1,"TX framing");
  if(tv)begin
   $fwrite(stream,"%c",td);pkt[n]=td;n++;tail={tail[23:0],td};
   if(tail==32'hcc33c33c)begin
    if(n==7 && pkt[2]==1)queries++;
    if(n==19 && pkt[2]==8'h10 && {pkt[5],pkt[6]}==900)begin
     if(pkt[7]!=8'h48 || pkt[8]!=8'h42)$fatal(1,"heartbeat text");
     for(integer i=9;i<15;i++)if(pkt[i]<48 || pkt[i]>57)$fatal(1,"heartbeat count");
     hb_pages[{pkt[3],pkt[4]}]=1;hb_count++;
    end
    n=0;tail=0;
   end
  end
 end
 task cycles(input integer k);repeat(k)@(negedge clk);endtask
 task send(input [7:0] b);begin @(negedge clk);bd=b;bv=1;cycles(1);bv=0;cycles(1);end endtask
 task finish_frame;begin send(8'hcc);send(8'h33);send(8'hc3);send(8'h3c);cycles(3);end endtask
 task page_reply(input [15:0] p);begin send(8'haa);send(8'hb1);send(1);send(p[15:8]);send(p[7:0]);finish_frame;end endtask
 task button(input [15:0] p,c,input [7:0] typ,sub,st);begin send(8'haa);send(8'hb1);send(8'h11);send(p[15:8]);send(p[7:0]);send(c[15:8]);send(c[7:0]);send(typ);send(sub);send(st);finish_frame;end endtask
 integer v_before,b_before;
 initial begin
  cycles(5);rst_n=1;wait(queries>=3);wait(hb_pages[0]);
  // Screen boots late: stable fields must be refreshed after reply.
  page_reply(5);cycles(10);if(page!=5 || !sender.page_known)$fatal(1,"late screen page sync");
  // Known pages must still be queried to detect a lost display RX path.
  queries_saved=queries;cycles(80000);
  if(queries<=queries_saved || queries>queries_saved+2 || !sender.page_known)
   $fatal(1,"continuous query cadence/page synchronization failed");
  button(5,44,8'h10,1,1);if(il!=4 || last_cmd!=1 || last_value!=4)$fatal(1,"board1 instrument");
  button(5,47,8'h10,1,1);if(ir!=2)$fatal(1,"board2 instrument");
  button(10,31,8'h10,1,1);if(!tm || page!=10)$fatal(1,"test mode/control source page sync");
  // Navigation frame carries source page. Do not overwrite target with it.
  button(10,30,8'h10,0,1);if(page!=0)$fatal(1,"navigation target overridden");page_reply(0);
  b_before=invalid_frames;v_before=valid_frames;
  button(5,44,8'h13,1,1);button(5,44,8'h10,2,1);page_reply(256);
  if(invalid_frames!=b_before+3 || valid_frames!=v_before || il!=4)$fatal(1,"invalid type/subtype/length/page accepted");
  send(8'haa);send(8'hb1);cycles(9500);if(invalid_frames!=b_before+4)$fatal(1,"timeout not diagnosed");
  fe=1;cycles(1);fe=0;cycles(2);if(invalid_frames!=b_before+5)$fatal(1,"UART error not diagnosed");
  send(8'haa);send(8'h07);finish_frame;cycles(10);if(sender.page_known)$fatal(1,"screen reset not rearmed");
  queries_saved=queries;wait(queries>queries_saved);page_reply(6);cycles(10);if(page!=6)$fatal(1,"screen reboot recovery");
  wait(n==0);$fclose(stream);
  $display("PASS diagnostics: late boot/retry/continuous poll/reboot/page source/navigation; current-page heartbeat; real control vectors from MANUAL fixtures, valid=%0d invalid=%0d heartbeats=%0d",valid_frames,invalid_frames,hb_count);$finish;
 end
 initial begin cycles(900000);$fatal(1,"diagnostics watchdog queries=%0d hb=%h",queries,hb_pages);end
endmodule
