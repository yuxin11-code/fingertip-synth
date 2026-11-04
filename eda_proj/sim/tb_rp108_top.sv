`timescale 1ns/1ps
module tb_rp108_top;
 wire BLE_RX=1'b1;
 reg rst=0,KEY1=1,KEY2=1,TIMBRE_KEY=1,ENC_A=1,ENC_B=1,ENC_C=1,PITCH_UP_KEY=1,PITCH_DOWN_KEY=1;
 reg K_LEFT=1,K_RIGHT=1,K_AUX3=1,K_AUX4=1,TEST_MODE_KEY=1,OCT_A=1,OCT_B=1,OCT_SW_N=1,UART_RX=1;
 wire TTP229_SDO,TTP_R_SDO;
 tri1 PAJ_SCL,PAJ_SDA,KNOB_SCL,KNOB_SDA;
 wire TTP229_SCL,TTP_R_SCL,HP_BCK,HP_WS,HP_DIN,PA_EN,WS2812_DIN,UART_TX;
 reg [127:0] values=0;reg enabled=1,bad_id=0;
 reg [15:0] left_keys=1,right_keys=2;
 top dut(.*);
 defparam dut.g_dual.instrument.left_touch.CLK_HZ=20000;
 defparam dut.g_dual.instrument.right_touch.CLK_HZ=20000;
 defparam dut.g_dual.instrument.left_touch.SCL_HZ=2000;
 defparam dut.g_dual.instrument.right_touch.SCL_HZ=2000;
 defparam dut.g_dual.instrument.rp108.CLK_HZ=100000;
 defparam dut.g_dual.instrument.rp108.I2C_HZ=5000;
 defparam dut.g_dual.instrument.knobs.CONTROL_FRAMES=1;
 poweron_touch left_model(TTP229_SCL,left_keys,TTP229_SDO);
 poweron_touch right_model(TTP_R_SCL,right_keys,TTP_R_SDO);
 rp108_slave_model slave(.scl(KNOB_SCL),.sda(KNOB_SDA),.values(values),.enabled(enabled),.bad_id(bad_id));
 integer pl=0,pr=0,pa=0,pb=0,frames=0,clipped=0;
 integer f;
 initial f=$fopen("results/rp108/top_pcm.csv","w");
 always @(posedge dut.g_dual.clk_sys)if(dut.g_dual.instrument.frame_tick===1)begin
  frames=frames+1;
  $fdisplay(f,"%0d,%0d,%0d",frames,dut.g_dual.instrument.pcm,dut.g_dual.instrument.pcm_right);
  if(dut.g_dual.instrument.pcm>pl)pl=dut.g_dual.instrument.pcm;
  if(dut.g_dual.instrument.pcm_right>pr)pr=dut.g_dual.instrument.pcm_right;
  if(dut.g_dual.instrument.panel_a_sum>pa)pa=dut.g_dual.instrument.panel_a_sum;
  if(dut.g_dual.instrument.panel_b_sum>pb)pb=dut.g_dual.instrument.panel_b_sum;
  if(dut.g_dual.instrument.pcm==32767 || dut.g_dual.instrument.pcm==-32768 || dut.g_dual.instrument.pcm_right==32767 || dut.g_dual.instrument.pcm_right==-32768)clipped=clipped+1;
 end
 initial begin
  #1000000;values={8{16'h1234}};#1000000;values=0;#1000000;
  values[15:0]=16'h1234; // volume full
  values[31:16]=16'h091a;values[47:32]=16'h091a; // blend and balance center
  values[63:48]=0;values[79:64]=16'h091a;values[95:80]=16'h091a;
  #6000000;
  if(dut.g_dual.instrument.knob_online!==1 || dut.g_dual.instrument.master!=65536)$fatal(1,"physical RP108 not connected to master");
  if(dut.g_dual.instrument.inst_l!==0 || dut.g_dual.instrument.inst_r!==0 || pa<100 || pb<100 || pl<100 || pr<100)$fatal(1,"default pianos or final PCM silent");
  values[31:16]=0;values[47:32]=0;#6000000;
  if(dut.g_dual.instrument.mixer.b_gain!=0 || dut.g_dual.instrument.mixer.a_gain!=65536 || dut.g_dual.instrument.pcm_right!=0)$fatal(1,"physical pots left solo/balance");
  // Six simultaneous absolute knob values, no switch/push mode.
  values[15:0]=16'h091a;values[31:16]=16'h1234;values[47:32]=16'h1234;
  values[63:48]=16'h091a;values[79:64]=16'h1234;values[95:80]=16'h091a;
  #6000000;
  if(dut.g_dual.instrument.master!=32768 || dut.g_dual.instrument.mixer.a_gain!=0 || dut.g_dual.instrument.mixer.b_gain!=65536 || dut.g_dual.instrument.pcm!=0)$fatal(1,"simultaneous pots physical path");
  if(dut.g_dual.instrument.knobs.value[3]!=32768 || dut.g_dual.instrument.knobs.value[4]!=65536)$fatal(1,"vibrato pots physical path");
  if(clipped!=0)$fatal(1,"two-note representative PCM clipped");
  $display("PASS RP108 top: real I2C+calibration -> six controls -> 32 voices -> stereo PCM; frames=%0d peaks L/R=%0d/%0d A/B=%0d/%0d clipped=%0d",frames,pl,pr,pa,pb,clipped);
  $fclose(f);$finish;
 end
endmodule
