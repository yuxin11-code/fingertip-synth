`timescale 1ns/1ps
// Exercise the actual default top, real frame clocks, serializer and UI wiring.
module tb_additive_top;
 `include "hmi_defs.vh"
 reg rst=1,TEST_MODE_KEY=1;
 wire HP_BCK,HP_WS,HP_DIN,UART_TX;
 top #(.RECORD_DEPTH(64)) dut(.rst(rst),.BLE_RX(1'b1),.UART_RX(1'b1),
  .KEY1(1'b1),.KEY2(1'b1),.K_LEFT(1'b1),.K_RIGHT(1'b1),.K_AUX3(1'b1),.K_AUX4(1'b1),.TEST_MODE_KEY(TEST_MODE_KEY),
  .OCT_A(1'b1),.OCT_B(1'b1),.OCT_SW_N(1'b1),.ENC_A(1'b1),.ENC_B(1'b1),.ENC_C(1'b1),
  .PITCH_UP_KEY(1'b1),.PITCH_DOWN_KEY(1'b1),.TTP229_SDO(1'b1),.TTP_R_SDO(1'b1),
  .HP_BCK(HP_BCK),.HP_WS(HP_WS),.HP_DIN(HP_DIN),.UART_TX(UART_TX));
 defparam dut.g_dual.instrument.controls.DB_TICKS=4;
 wire clk=dut.g_dual.clk_sys;
 integer frames=0,ones=0,peak=0,clipped=0;
 always @(negedge HP_BCK)if(HP_DIN===1)ones=ones+1;
 always @(posedge clk)if(dut.g_dual.instrument.frame_tick && dut.g_dual.instrument.test_mode)begin
  frames=frames+1;
  if(dut.g_dual.instrument.pcm>peak)peak=dut.g_dual.instrument.pcm;
  if(dut.g_dual.instrument.pcm==32767 || dut.g_dual.instrument.pcm==-32768)clipped=clipped+1;
  if(dut.g_dual.instrument.g_additive.voices.deadline_error)$fatal(1,"deadline");
 end
 initial begin
  repeat(10)@(negedge clk);rst=0;repeat(1000)@(negedge clk);
  TEST_MODE_KEY=0;repeat(40)@(negedge clk);TEST_MODE_KEY=1;
  wait(frames==1600);repeat(600)@(negedge clk);
  if(dut.g_dual.instrument.active_osc!==512)$fatal(1,"32x16 test population %d",dut.g_dual.instrument.active_osc);
  if(dut.g_dual.instrument.ui_fields_q[HMI_FIELD_P0_C5_ACTIVE_OSC*32+:32]!==512)$fatal(1,"HMI population");
  if(ones==0 || peak==0 || clipped!=0)$fatal(1,"PCM/serializer");
  if(dut.g_dual.instrument.voice_note[7:0]!=36 || dut.g_dual.instrument.voice_note[255:248]!=67)$fatal(1,"original test notes");
  $display("PASS additive actual top: active_osc=512 HMI=512 original notes=36..67 frames=%0d PCM_peak=%0d serial_ones=%0d clipped=%0d",frames,peak,ones,clipped);
  $finish;
 end
 initial begin #100000000;$fatal(1,"watchdog");end
endmodule
