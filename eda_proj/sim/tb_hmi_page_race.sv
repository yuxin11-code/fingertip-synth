`timescale 1ns/1ps
// Finish an in-flight public status frame while switching to another page.
module tb_hmi_page_race;
 `define HMI_DEFINE_TX_TABLE
 `include "hmi_defs.vh"
 `undef HMI_DEFINE_TX_TABLE
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,cmd_valid=0,page_valid=0;
 reg [7:0] cmd=0;
 reg [15:0] value=0,page_id=0;
 reg [HMI_TX_FIELD_COUNT*32-1:0] fields=0;
 wire tx;wire [3:0] current_page;wire [31:0] byte_count;
 hmi_tx #(.CLK_HZ(1843200),.FIELD_COUNT(HMI_TX_FIELD_COUNT)) dut(
  .clk(clk),.rst_n(rst_n),.cmd_valid(cmd_valid),.cmd(cmd),.value(value),
  .fields(fields),.page_valid(page_valid),.page_id(page_id),.screen_reset(1'b0),
  .aux_valid(1'b0),.aux_last(1'b0),.aux_data(8'd0),.tx(tx),
  .current_page(current_page),.byte_count(byte_count));
 wire [7:0] data;wire valid,frame_error;
 hmi_uart_rx #(.CLK_HZ(1843200)) rx(.clk(clk),.rst_n(rst_n),.rx(tx),
  .data(data),.valid(valid),.frame_error(frame_error));
 integer n=0,received=0,stream;reg [31:0] tail=0;reg [7:0] packet[0:63];
 reg seen_new=0;
 initial begin
  stream=$fopen("../results/full_audit_20261102/hmi_page_race.bin","wb");
  if(!stream)$fatal(1,"cannot open capture");
 end
 always @(negedge clk)if(rst_n)begin
  if(frame_error)$fatal(1,"UART framing error");
  if(valid)begin
   $fwrite(stream,"%c",data);packet[n]=data;n=n+1;tail={tail[23:0],data};
   if(tail==32'hcc33c33c)begin
    if(n!=7 && {packet[3],packet[4]}==16'd9 && {packet[5],packet[6]}==16'd81)seen_new=1;
    received=received+1;n=0;tail=0;
   end else if(n>=64)$fatal(1,"unbounded frame");
  end
 end
 task page(input [15:0] p);begin
  @(negedge clk);cmd_valid=1;cmd=8'h1f;value=p;page_valid=1;page_id=p;
  @(negedge clk);cmd_valid=0;page_valid=0;
 end endtask
 initial begin
  fields[HMI_FIELD_P6_C81_KNOB_0*32+:32]=500;
  fields[HMI_FIELD_P11_C81_KNOB_MIRROR_0*32+:32]=500;
  repeat(4)@(negedge clk);rst_n=1;page(6);
  // The public field is already transmitting for page 0. The switch
  // refreshes all fields before that old packet has finished.
  wait(dut.frame_mode==0 && dut.active_ctrl==81 && dut.state==6 && dut.pos==8);
  page(9);
  repeat(500000)@(negedge clk);
  $fclose(stream);
  if(!seen_new)$fatal(1,"volume c81 lost on page 9 after in-flight page change; frames=%0d",received);
  $display("PASS HMI page race: unchanged volume c81 retransmitted on new page");$finish;
 end
 initial begin #10000000;$fatal(1,"page race watchdog");end
endmodule
