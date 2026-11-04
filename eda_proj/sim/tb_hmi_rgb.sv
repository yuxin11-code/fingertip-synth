`timescale 1ns/1ps
module tb_hmi_rgb;
 reg rst=1,UART_RX=1;wire BLE_RX=1;
 top dut(.rst(rst),.UART_RX(UART_RX),.BLE_RX(BLE_RX),.KEY1(1'b1),.KEY2(1'b1),.K_LEFT(1'b1),.K_RIGHT(1'b1),.K_AUX3(1'b1),.K_AUX4(1'b1),.TEST_MODE_KEY(1'b1),
 .OCT_A(1'b1),.OCT_B(1'b1),.OCT_SW_N(1'b1),.ENC_A(1'b1),.ENC_B(1'b1),.ENC_C(1'b1),.PITCH_UP_KEY(1'b1),.PITCH_DOWN_KEY(1'b1),.TTP229_SDO(1'b1),.TTP_R_SDO(1'b1));
 wire clk=dut.g_dual.clk_sys;
 reg bv=0,fe=0;reg [7:0] bd=0;
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 task send(input [7:0] b);begin @(negedge clk);bv=1;bd=b;cycles(1);bv=0;cycles(1);end endtask
 initial begin
  force dut.g_dual.instrument.rx_valid=bv;force dut.g_dual.instrument.rx_error=fe;force dut.g_dual.instrument.rx_byte=bd;
  cycles(10);rst=0;cycles(20);
  send(8'haa);send(8'hb1);send(1);send(0);send(5);send(8'hcc);send(8'h33);send(8'hc3);send(8'h3c);cycles(5);
  if(dut.g_dual.instrument.hmi_flash_timer==0 || dut.g_dual.instrument.link_color!=24'h0000ff)$fatal(1,"valid frame blue flash");
  fe=1;cycles(1);fe=0;cycles(5);
  if(dut.g_dual.instrument.link_color!=24'h606000)$fatal(1,"invalid UART yellow flash");
  force dut.g_dual.instrument.recording=1;force dut.g_dual.instrument.RECORD_LED=1;cycles(2);
  if(dut.g_dual.instrument.link_color!=24'h002000)$fatal(1,"record red priority");
  force dut.g_dual.instrument.playing=1;cycles(2);
  if(dut.g_dual.instrument.link_color!=24'h200000)$fatal(1,"play green priority");
  release dut.g_dual.instrument.playing;release dut.g_dual.instrument.recording;release dut.g_dual.instrument.RECORD_LED;
  $display("PASS actual top RGB: valid blue/invalid yellow; recording red and playback green preserve priority");$finish;
 end
endmodule
