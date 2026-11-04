`timescale 1ns/1ps
module tb_fx_top_bypass;
 parameter integer SYNTH_MODE=1;
 reg rst=1,KEY1=1,KEY2=1,TIMBRE_KEY=1,TTP229_SDO=1;
 reg ENC_A=1,ENC_B=1,ENC_C=1,PITCH_UP_KEY=1,PITCH_DOWN_KEY=1;
 reg K_LEFT=1,K_RIGHT=1,K_AUX3=1,K_AUX4=1,TEST_MODE_KEY=1;
 reg TTP_R_SDO=1,UART_RX=1,BLE_RX=1,OCT_A=1,OCT_B=1,OCT_SW_N=1;
 tri1 PAJ_SCL,PAJ_SDA,KNOB_SCL,KNOB_SDA;
 wire TTP229_SCL,TTP_R_SCL,HP_BCK,HP_WS,HP_DIN,PA_EN,WS2812_DIN,UART_TX;
 top #(.ENABLE_DUAL_PANEL(1),.SYNTH_MODE(SYNTH_MODE)) dut(.*);
 integer checks=0,mismatches=0;
 reg checking=0;
 always @(negedge dut.g_dual.clk_sys)if(checking && dut.g_dual.instrument.ui_fx_enable===3'b000)begin
  checks=checks+1;
  if(dut.g_dual.instrument.mixed_panel_a!==dut.g_dual.instrument.panel_a_sum ||
     dut.g_dual.instrument.mixed_panel_b!==dut.g_dual.instrument.panel_b_sum)
   mismatches=mismatches+1;
 end
 initial begin
  #3000;rst=0;
  wait(dut.g_dual.instrument.engine_ready && dut.g_dual.instrument.fx_ready);
  checking=1;
  repeat(4)@(posedge dut.g_dual.instrument.frame_tick);
  if(checks<1000 || mismatches!=0)$fatal(1,"bypass mode=%0d checks=%0d mismatches=%0d",SYNTH_MODE,checks,mismatches);
  force dut.g_dual.instrument.panel_a_sum=40'sd40000;
  force dut.g_dual.instrument.panel_b_sum=40'sd0;
  force dut.g_dual.instrument.ui_fx_enable=3'b010;
  repeat(2)@(posedge dut.g_dual.instrument.fx_sample_valid);
  #1;
  if(!dut.g_dual.instrument.fx_active || dut.g_dual.instrument.fx_left==0 ||
     dut.g_dual.instrument.mixed_panel_a!=={{22{dut.g_dual.instrument.fx_left[15]}},dut.g_dual.instrument.fx_left,2'b00})
   $fatal(1,"effect routing mode=%0d",SYNTH_MODE);
  release dut.g_dual.instrument.ui_fx_enable;
  release dut.g_dual.instrument.panel_a_sum;
  release dut.g_dual.instrument.panel_b_sum;
  $display("PASS FX top mode=%0d all_off_mismatches=%0d checks=%0d",SYNTH_MODE,mismatches,checks);
  $finish;
 end
 initial begin #10000000;$fatal(1,"FX top watchdog");end
endmodule
