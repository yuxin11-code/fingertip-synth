`timescale 1ns/1ps
module tb_top_score_connect;
 reg rst=1,BLE_RX=1,UART_RX=1;
 top dut(.rst(rst),.BLE_RX(BLE_RX),.UART_RX(UART_RX),
  .KEY1(1'b1),.KEY2(1'b1),.K_LEFT(1'b1),.K_RIGHT(1'b1),.K_AUX3(1'b1),.K_AUX4(1'b1),.TEST_MODE_KEY(1'b1),
  .OCT_A(1'b1),.OCT_B(1'b1),.OCT_SW_N(1'b1),.ENC_A(1'b1),.ENC_B(1'b1),.ENC_C(1'b1),
  .PITCH_UP_KEY(1'b1),.PITCH_DOWN_KEY(1'b1),.TTP229_SDO(1'b1),.TTP_R_SDO(1'b1));
 wire clk=dut.g_dual.clk_sys;
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 reg packet_valid=0;reg [7:0] kind=0,len=0;reg [15:0] seq=0;reg [95:0] body=0;
 task packet(input [7:0] k,input [15:0] s,input [7:0] l,input [95:0] b);begin
  @(negedge clk);kind=k;seq=s;len=l;body=b;packet_valid=1;cycles(1);packet_valid=0;cycles(4);
 end endtask
 reg cv=0;reg [7:0] cmd=0;reg [15:0] value=0;
 task command(input [7:0] c,input [15:0] v);begin @(negedge clk);cmd=c;value=v;cv=1;cycles(1);cv=0;cycles(4);end endtask
 reg [15:0] touch_keys=0;
 initial begin
  force dut.score_packet_valid=packet_valid;force dut.score_packet_type=kind;force dut.score_packet_len=len;force dut.score_packet_seq=seq;force dut.score_payload=body;
  force dut.g_dual.instrument.cmd_valid=cv;force dut.g_dual.instrument.cmd=cmd;force dut.g_dual.instrument.cmd_value=value;
  force dut.g_dual.instrument.keys_left=touch_keys;
  cycles(10);rst=0;cycles(30);
  packet(1,0,12,{32'd1000,16'd96,16'd120,16'd1,8'd0,8'd1});
  packet(2,1,11,{8'd0,8'd0,8'd100,8'd60,32'd10,32'd0});packet(3,2,2,96'd1);
  cycles(300);
  if(dut.score_valid!==1 || dut.g_dual.instrument.score_valid!==1 || dut.g_dual.instrument.game.guide.ready!==1)$fatal(1,"top score connection/metadata");
  command(8'h1f,7);command(8'h53,1);command(8'h50,1);cycles(300);
  if(dut.g_dual.instrument.game_active!==1 || dut.g_dual.instrument.game.guide.lane_now!==1 || dut.score_read_address!==0)$fatal(1,"top score RAM read/lane");
  if(dut.g_dual.instrument.recorder.paused!==1 || dut.g_dual.instrument.controls.test_suspend!==1)$fatal(1,"top freeze wiring");
  touch_keys=1;cycles(300);
  if(dut.g_dual.instrument.game_score!==100 || dut.g_dual.instrument.voice_gate[0]!==1)$fatal(1,"top physical hit/audio");
  command(8'h1f,0);cycles(10);
  if(dut.g_dual.instrument.game_active!==0 || dut.g_dual.instrument.controls.test_suspend!==0)$fatal(1,"top exit restore");
  $display("PASS real top score metadata -> guide -> synchronous score RAM -> physical lane hit -> UI fields; freeze and exit restore");$finish;
 end
 initial begin cycles(10000);$fatal(1,"top score connection watchdog");end
endmodule
