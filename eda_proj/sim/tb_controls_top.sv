`timescale 1ns/1ps
module tb_controls_top;
 parameter integer SYNTH_MODE=1;
 reg rst=1,KEY1=1,KEY2=1,TIMBRE_KEY=1,TTP229_SDO=1;
 reg ENC_A=1,ENC_B=1,ENC_C=1,PITCH_UP_KEY=1,PITCH_DOWN_KEY=1;
 reg K_LEFT=1,K_RIGHT=1,K_AUX3=1,K_AUX4=1,TEST_MODE_KEY=1;
 reg TTP_R_SDO=1,UART_RX=1,BLE_RX=1,OCT_A=1,OCT_B=1,OCT_SW_N=1;
 tri1 PAJ_SCL,PAJ_SDA,KNOB_SCL,KNOB_SDA;
 wire TTP229_SCL,TTP_R_SCL,HP_BCK,HP_WS,HP_DIN,PA_EN,WS2812_DIN,UART_TX;
 top #(.SYNTH_MODE(SYNTH_MODE)) dut(.*);
 defparam dut.g_dual.instrument.controls.DB_TICKS=4;
 defparam dut.g_dual.instrument.controls.GAP_FRAMES=2;
 defparam dut.g_dual.instrument.controls.HOLD_FRAMES=24;
 defparam dut.g_dual.instrument.knobs.CONTROL_FRAMES=1;
 reg [15:0] left_keys=0,right_keys=0;
 reg right_swipe=0,left_swipe=0;
 reg [5:0] pot_mask=0;reg [101:0] pot_values=0;
 task cycles(input integer n);repeat(n)@(negedge dut.g_dual.clk_sys);endtask
 task frames(input integer n);repeat(n)@(negedge dut.g_dual.instrument.frame_tick);endtask
 task key3;begin TIMBRE_KEY=0;cycles(20);TIMBRE_KEY=1;cycles(20);end endtask
 integer n;reg audio_seen_a=0,audio_seen_b=0;
 always @(negedge dut.g_dual.clk_sys)begin
  if(dut.g_dual.instrument.panel_a_sum!=0)audio_seen_a=1;
  if(dut.g_dual.instrument.panel_b_sum!=0)audio_seen_b=1;
 end
 initial begin
  force dut.g_dual.instrument.keys_left=left_keys;
  force dut.g_dual.instrument.keys_right=right_keys;
  force dut.g_dual.instrument.paj_ok=1'b1;
  force dut.g_dual.instrument.paj_error=1'b0;
  force dut.g_dual.instrument.paj_right=right_swipe;
  force dut.g_dual.instrument.paj_left=left_swipe;
  force dut.g_dual.instrument.knob_write_mask=pot_mask;
  force dut.g_dual.instrument.knob_write_values=pot_values;
  #3000;rst=0;
  wait(dut.g_dual.instrument.engine_ready && dut.g_dual.instrument.fx_ready);
  cycles(15);key3;
  if(dut.g_dual.instrument.pluck_mode!==1)$fatal(1,"AA13 KEY3 not connected mode=%0d",SYNTH_MODE);
  left_keys=1;right_keys=1;frames(4);cycles(20);
  if(dut.g_dual.instrument.voice_gate!==0 || dut.g_dual.instrument.combined_gate!==0 || audio_seen_a || audio_seen_b)
   $fatal(1,"touch emitted sound in gesture-only mode=%0d",SYNTH_MODE);
  pot_values[16:0]=20000;pot_mask=1;cycles(1);pot_mask=0;
  KEY1=0;KEY2=0;cycles(30);KEY1=1;KEY2=1;cycles(30);frames(140);cycles(20);
  if(dut.g_dual.instrument.master!==20000 || dut.g_dual.instrument.knob_targets[16:0]!==20000)
   $fatal(1,"KEY1/KEY2 stole physical volume mode=%0d",SYNTH_MODE);
  right_swipe=1;cycles(8);right_swipe=0;
  // The first additive onset intentionally resets phase to zero. Check
  // after subsequent complete synthesis frames, not at frame_tick itself.
  frames(8);cycles(700);
  if(!audio_seen_a || !audio_seen_b || dut.g_dual.instrument.voice_gate!==32'h00010001)
   $fatal(1,"gesture did not reach both audio engines mode=%0d gate=%h audio=%b%b",SYNTH_MODE,dut.g_dual.instrument.voice_gate,audio_seen_b,audio_seen_a);
  if(dut.g_dual.instrument.recording || dut.g_dual.instrument.record_length!=0)
   $fatal(1,"board KEY3 conflicted with external recording key");
  key3;cycles(20);
  if(dut.g_dual.instrument.pluck_mode!==0 || dut.g_dual.instrument.voice_gate!==32'h00010001)
   $fatal(1,"KEY3 did not restore direct touch mode=%0d",SYNTH_MODE);
  if(dut.g_dual.instrument.deadline_count!=0)$fatal(1,"controls introduced audio deadline error");
  $display("PASS top controls mode=%0d: AA13 toggle, silent touch, dual-panel gesture audio, knob-only volume, recorder isolation, zero deadline errors",SYNTH_MODE);
  $finish;
 end
 initial begin #100000000;$fatal(1,"top control watchdog");end
endmodule
