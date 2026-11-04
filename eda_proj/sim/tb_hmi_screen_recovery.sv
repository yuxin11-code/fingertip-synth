`timescale 1ns/1ps
module tb_hmi_screen_recovery;
 parameter integer SYNTH_MODE=1;
 `include "hmi_defs.vh"
 reg rst=1,KEY1=1,KEY2=1,TIMBRE_KEY=1,TTP229_SDO=1;
 reg ENC_A=1,ENC_B=1,ENC_C=1,PITCH_UP_KEY=1,PITCH_DOWN_KEY=1;
 reg K_LEFT=1,K_RIGHT=1,K_AUX3=1,K_AUX4=1,TEST_MODE_KEY=1;
 reg TTP_R_SDO=1,UART_RX=1,BLE_RX=1,OCT_A=1,OCT_B=1,OCT_SW_N=1;
 tri1 PAJ_SCL,PAJ_SDA,KNOB_SCL,KNOB_SDA;
 wire TTP229_SCL,TTP_R_SCL,HP_BCK,HP_WS,HP_DIN,PA_EN,WS2812_DIN,UART_TX;
 top #(.SYNTH_MODE(SYNTH_MODE)) dut(.*);
 defparam dut.g_dual.instrument.hmi_link.TIMEOUT_CLKS=120;
 reg inject_valid=0;reg [7:0] inject_byte=0;reg panel=0;
 task cycles(input integer n);repeat(n)@(negedge dut.g_dual.clk_sys);endtask
 task put(input [7:0] b);begin inject_byte=b;inject_valid=1;cycles(1);inject_valid=0;cycles(2);end endtask
 task tail;begin put(8'hcc);put(8'h33);put(8'hc3);put(8'h3c);cycles(5);end endtask
 task touch(input [7:0] id);begin
  put(8'haa);put(8'hb1);put(8'h11);put(0);put(1);put(0);put(id);put(8'h10);put(1);put(1);tail();
 end endtask
 task boot;begin put(8'haa);put(8'h07);tail();end endtask
 initial begin
  force dut.g_dual.instrument.keys_left=16'h20;
  force dut.g_dual.instrument.keys_right=16'h40;
  force dut.g_dual.instrument.rx_valid=inject_valid;
  force dut.g_dual.instrument.rx_byte=inject_byte;
  force dut.g_dual.instrument.selected_panel=panel;
  #3000;rst=0;cycles(50);
  if(dut.g_dual.instrument.hmi_tx_bytes==0 || dut.g_dual.instrument.hmi_link_online)
   $fatal(1,"TX-only traffic falsely marked link online");
  touch(100);if(dut.g_dual.instrument.screen_left!==1 || !dut.g_dual.instrument.hmi_link_online)$fatal(1,"left touch setup");
  boot();if(dut.g_dual.instrument.screen_left!==0 || dut.g_dual.instrument.screen_right!==0 || dut.g_dual.instrument.hmi_link_online)$fatal(1,"boot did not clear virtual keys/link");
  touch(101);if(dut.g_dual.instrument.screen_left!==2)$fatal(1,"left stale key resurrected");
  panel=1;cycles(5);touch(103);
  if(dut.g_dual.instrument.screen_right!==8)$fatal(1,"right touch setup");
  boot();if(dut.g_dual.instrument.screen_left!==0 || dut.g_dual.instrument.screen_right!==0)$fatal(1,"right boot clear");
  touch(103);cycles(130);
  if(dut.g_dual.instrument.hmi_link_online || dut.g_dual.instrument.screen_right!==0 ||
     dut.g_dual.instrument.ui_fields[HMI_FIELD_P10_C74_HMI_LINK*32+:32]!==0)$fatal(1,"disconnect state/keys not cleared");
  if(dut.g_dual.instrument.transmitter.page_known!==0)
   $fatal(1,"disconnect left TX page cache valid: reconnect can lose offline value updates");
  touch(104);if(dut.g_dual.instrument.screen_right!==16)$fatal(1,"disconnect did not clear parser mask");
  if(dut.g_dual.instrument.keys_left!==16'h20 || dut.g_dual.instrument.keys_right!==16'h40)$fatal(1,"physical key state changed");
  $display("PASS screen recovery mode=%0d: RX-only online, boot clears both panels, disconnect release, parser recovery, physical keys preserved",SYNTH_MODE);$finish;
 end
 initial begin #10000000;$fatal(1,"screen recovery watchdog");end
endmodule
