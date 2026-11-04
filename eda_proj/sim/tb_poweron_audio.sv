`timescale 1ns/1ps
// Both real serial scan inputs, with no forced key vectors or frame ticks.
module poweron_touch(input wire scl,input wire [15:0] keys,output reg sdo=1);
 integer idx=0; reg [15:0] latched=0; time last_edge=0;
 always @(negedge scl) begin
  last_edge=$time;
  if(idx==0) latched=keys;
  sdo<=#1 ~latched[idx];idx=(idx+1)%16;
 end
 always begin #50; if($time-last_edge>600) begin idx=0;sdo=1;end end
endmodule
module tb_poweron_audio;
 wire BLE_RX=1'b1;
 reg rst=0,KEY1=1,KEY2=1,TIMBRE_KEY=1,ENC_A=1,ENC_B=1,ENC_C=1,PITCH_UP_KEY=1,PITCH_DOWN_KEY=1;
 reg K_LEFT=1,K_RIGHT=1,K_AUX3=1,K_AUX4=1,TEST_MODE_KEY=1,OCT_A=1,OCT_B=1,OCT_SW_N=1,UART_RX=1;
 wire TTP229_SDO,TTP_R_SDO;
 tri1 PAJ_SCL,PAJ_SDA;
 tri1 KNOB_SCL,KNOB_SDA;
 wire TTP229_SCL,TTP_R_SCL,HP_BCK,HP_WS,HP_DIN,PA_EN,WS2812_DIN,UART_TX;
 reg [15:0] left_keys=0,right_keys=0;
 top dut(.*);
 defparam dut.g_dual.instrument.left_touch.CLK_HZ=20000;
 defparam dut.g_dual.instrument.right_touch.CLK_HZ=20000;
 defparam dut.g_dual.instrument.left_touch.SCL_HZ=2000;
 defparam dut.g_dual.instrument.right_touch.SCL_HZ=2000;
 poweron_touch left_model(TTP229_SCL,left_keys,TTP229_SDO);
 poweron_touch right_model(TTP_R_SCL,right_keys,TTP_R_SDO);
 integer ticks=0,peak_a=0,peak_b=0,peak_pcm=0,ones=0;
 reg measure=0;
 always @(posedge dut.g_dual.clk_sys) if(measure) begin
  if(dut.g_dual.instrument.frame_tick===1) ticks=ticks+1;
  if(dut.g_dual.instrument.panel_a_sum>peak_a) peak_a=dut.g_dual.instrument.panel_a_sum;
  if(dut.g_dual.instrument.panel_b_sum>peak_b) peak_b=dut.g_dual.instrument.panel_b_sum;
  if(dut.g_dual.instrument.pcm>peak_pcm) peak_pcm=dut.g_dual.instrument.pcm;
 end
 always @(negedge HP_BCK) if(measure && HP_DIN===1) ones=ones+1;
 task check(input integer mode);
  begin
   measure=0;left_keys=0;right_keys=0;#300000;
   case(mode)
    0:left_keys=16'h0001;
    1:right_keys=16'h0001;
    2:begin left_keys=16'h0005;right_keys=16'h0081;end
   endcase
   #100000;
   ticks=0;peak_a=0;peak_b=0;peak_pcm=0;ones=0;measure=1;#2000000;measure=0;
   $display("mode=%0d inst_l/r=%0d/%0d keys=%h/%h ticks=%0d sum_peaks=%0d/%0d PCM_peak=%0d serial_ones=%0d",
    mode,dut.g_dual.instrument.inst_l,dut.g_dual.instrument.inst_r,
    dut.g_dual.instrument.keys_left,dut.g_dual.instrument.keys_right,ticks,peak_a,peak_b,peak_pcm,ones);
   if(dut.g_dual.instrument.inst_l!==0 || dut.g_dual.instrument.inst_r!==0) $fatal(1,"not default piano");
   if(dut.g_dual.instrument.keys_left!==left_keys || dut.g_dual.instrument.keys_right!==right_keys) $fatal(1,"scan mismatch");
   if(ticks<80 || peak_pcm<10 || ones==0) $fatal(1,"audio failed to start without manual reset");
   if(mode!=1 && peak_a<10) $fatal(1,"left piano silent");
   if(mode!=0 && peak_b<10) $fatal(1,"right piano silent");
  end
 endtask
 initial begin
  // Default: cold start, rst never asserted. Also test initially asserted
  // reset and an explicit warm reset as separate invocations.
  if($test$plusargs("RESET_HELD")) begin rst=1;#3000;rst=0;end
  if($test$plusargs("WARM")) begin #3000;rst=1;#3000;rst=0;end
  #500000;
  if($test$plusargs("RIGHT_FIRST")) begin check(1);check(0);end
  else begin check(0);check(1);end
  check(2);
  rst=1;#3000;rst=0;#500000;check(1);
  $display("PASS poweron audio: left-only, right-only, both default piano and warm reset; final PCM/serial active");$finish;
 end
endmodule
