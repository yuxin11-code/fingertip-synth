`timescale 1ns/1ps
// A screen boot notification invalidates its previously held touch keys.
module tb_hmi_reset_keys;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,byte_valid=0,clear_keys=0;reg [7:0] byte_data=0;
 wire cmd_valid,frame_valid,frame_invalid,page_valid,screen_reset;
 wire [7:0] cmd;wire [15:0] value,page_id;
 hmi_rx #(.CLK_HZ(1843200)) dut(.selected_panel(1'b0),.clear_keys(clear_keys),.clk(clk),.rst_n(rst_n),
  .byte_valid(byte_valid),.byte_data(byte_data),.frame_error(1'b0),
  .cmd_valid(cmd_valid),.cmd(cmd),.value(value),.frame_valid(frame_valid),
  .frame_invalid(frame_invalid),.page_valid(page_valid),.screen_reset(screen_reset),.page_id(page_id));
 reg [15:0] last_keys=0;integer resets=0;
 always @(negedge clk)begin
  if(cmd_valid && cmd==8'h30)last_keys=value;
  if(screen_reset)resets=resets+1;
 end
 task put(input [7:0] b);begin
  @(negedge clk);byte_valid=1;byte_data=b;
  @(negedge clk);byte_valid=0;@(negedge clk);
 end endtask
 task tail;begin put(8'hcc);put(8'h33);put(8'hc3);put(8'h3c);repeat(4)@(negedge clk);end endtask
 task touch(input [7:0] id);begin
  put(8'haa);put(8'hb1);put(8'h11);put(0);put(1);put(0);put(id);
  put(8'h10);put(1);put(1);tail();
 end endtask
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  touch(100);if(last_keys!==1)$fatal(1,"initial touch failed");
  put(8'haa);put(8'h07);tail();if(resets!=1)$fatal(1,"boot not recognized");
  // Page 1 is restored, or its first touch arrives before the page-0 query
  // response. Neither event represents a continued press of old key c100.
  put(8'haa);put(8'hb1);put(1);put(0);put(1);tail();
  touch(101);
  if(last_keys!==2)$fatal(1,"stale screen key resurrected after reset: got=%h expected=0002",last_keys);
  // Watchdog clear can coincide with the last byte of an in-flight touch.
  put(8'haa);put(8'hb1);put(8'h11);put(0);put(1);put(0);put(102);
  put(8'h10);put(1);put(1);put(8'hcc);put(8'h33);put(8'hc3);
  @(negedge clk);clear_keys=1;byte_valid=1;byte_data=8'h3c;
  @(negedge clk);#1;
  if(dut.native_left!==0 || dut.native_right!==0 || cmd_valid)
   $fatal(1,"watchdog clear lost to in-flight touch");
  clear_keys=0;byte_valid=0;repeat(4)@(negedge clk);
  touch(103);if(last_keys!==8)$fatal(1,"key resurrected after watchdog collision");
  $display("PASS screen reset clears native held-key state");$finish;
 end
 initial begin #1000000;$fatal(1,"reset keys watchdog");end
endmodule
