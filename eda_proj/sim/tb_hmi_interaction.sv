`timescale 1ns/1ps
module tb_hmi_interaction;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,bv=0,selected=0;reg [7:0] bd=0;
 wire cv;wire [7:0] cmd;wire [15:0] value;
 hmi_rx #(.CLK_HZ(1843200)) parser(.clk(clk),.rst_n(rst_n),.byte_valid(bv),.byte_data(bd),.frame_error(1'b0),.selected_panel(selected),.cmd_valid(cv),.cmd(cmd),.value(value));
 reg [7:0] got_cmd;reg [15:0] got_value;
 wire wait_mode;wire [1:0] speed;
 score_guide #(.CLK_HZ(1843200)) guide(.clk(clk),.rst_n(rst_n),.score_valid(1'b0),.note_count(16'd0),.bpm(16'd120),.ticks_per_beat(16'd96),.length_ticks(32'd0),.ram_data(88'd0),.cmd_valid(cv),.cmd(cmd),.value(value),.keys(16'd0),.wait_mode(wait_mode),.speed(speed));
 always @(negedge clk)if(cv)begin got_cmd=cmd;got_value=value;end
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 task byte_send(input [7:0] b);begin bd=b;bv=1;cycles(1);bv=0;cycles(1);end endtask
 task tail;begin byte_send('hcc);byte_send('h33);byte_send('hc3);byte_send('h3c);cycles(3);end endtask
 task button(input [15:0] p,id,input bit state);begin
  byte_send('haa);byte_send('hb1);byte_send('h11);byte_send(p>>8);byte_send(p);byte_send(id>>8);byte_send(id);byte_send('h10);byte_send(1);byte_send(state);tail;
 end endtask
 task check(input [7:0] c,input [15:0] v);if(got_cmd!=c || got_value!=v)$fatal(1,"cmd=%h value=%h expected=%h/%h",got_cmd,got_value,c,v);endtask
 reg tick=0;reg signed [15:0] sample=0;wire [31:0] hz;wire [15:0] peak;
 hmi_scope_metrics #(.CLK_HZ(10000)) metrics(.clk(clk),.rst_n(rst_n),.tick(tick),.sample(sample),.frequency(hz),.peak(peak));
 initial begin
  cycles(5);rst_n=1;cycles(5);
  button(1,100,1);check('h30,1);
  selected=1;cycles(4);button(1,101,1);check('h31,2);button(1,101,0);check('h31,0);
  selected=0;cycles(4);button(1,102,1);check('h30,4);button(1,102,0);check('h30,0);
  button(1,103,1);button(1,30,1);check('h1f,0);button(1,104,1);check('h30,16);button(1,104,0);
  button(7,40,1);check('h50,1);button(7,41,1);check('h51,1);button(7,42,1);check('h52,1);
  if(!wait_mode)$fatal(1,"practice must always wait");
  button(8,41,1);check('h10,1);button(8,42,1);check('h10,0);button(8,43,1);check('h11,1);
  // Captured from the real CF-Design V2.16 virtual screen Uart window.
  byte_send('haa);byte_send('hb1);byte_send('h11);byte_send(0);byte_send(5);byte_send(0);byte_send('h32);byte_send('h13);byte_send(0);byte_send(7);tail;check(3,3);
  byte_send('haa);byte_send('hb1);byte_send('h11);byte_send(0);byte_send(5);byte_send(0);byte_send('h32);byte_send('h13);byte_send(0);byte_send(0);byte_send(0);byte_send(8);tail;check(3,4);
  for(integer i=0;i<200;i++)begin tick=1;sample=(i%10<5)?-12345:12345;cycles(1);tick=0;cycles(9);end
  if(hz<99 || hz>101 || peak!=12345)$fatal(1,"scope metrics hz=%0d peak=%0d",hz,peak);
  $display("PASS physical board/key masks/page exit; fixed practice commands/recording uploads/ten pages; read-only frequency and peak");$finish;
 end
 initial begin cycles(20000);$fatal(1,"interaction watchdog");end
endmodule
