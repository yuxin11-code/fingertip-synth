`timescale 1ns/1ps
// Actual serial capacitance keys, production note mapping, engine and mixer.
// No forced keys/PCM/analysis clocks. Sensor startup/polling alone is sped up.
module spectrum_touch(input wire scl,input wire [15:0] keys,output reg sdo=1);
 integer idx=0;reg [15:0] latched=0;time last_edge=0;
 always @(negedge scl)begin
  last_edge=$time;if(idx==0)latched=keys;
  sdo<=#1 ~latched[idx];idx=(idx+1)%16;
 end
 always begin #50;if($time-last_edge>600)begin idx=0;sdo=1;end end
endmodule
module tb_spectrum_key_correspondence #(parameter integer ALL_KEYS=0);
 reg rst=1,KEY1=1,KEY2=1,TIMBRE_KEY=1,ENC_A=1,ENC_B=1,ENC_C=1,PITCH_UP_KEY=1,PITCH_DOWN_KEY=1;
 reg K_LEFT=1,K_RIGHT=1,K_AUX3=1,K_AUX4=1,TEST_MODE_KEY=1,OCT_A=1,OCT_B=1,OCT_SW_N=1,UART_RX=1;
 wire BLE_RX=1'b1;
 wire TTP229_SDO,TTP_R_SDO,BLE_TX;
 tri1 PAJ_SCL,PAJ_SDA,KNOB_SCL,KNOB_SDA;
 wire TTP229_SCL,TTP_R_SCL,HP_BCK,HP_WS,HP_DIN,PA_EN,WS2812_DIN,UART_TX;
 reg [15:0] left_keys=0,right_keys=0;
 top dut(.*);
 defparam dut.g_dual.instrument.left_touch.CLK_HZ=20000;
 defparam dut.g_dual.instrument.right_touch.CLK_HZ=20000;
 defparam dut.g_dual.instrument.left_touch.SCL_HZ=2000;
 defparam dut.g_dual.instrument.right_touch.SCL_HZ=2000;
 spectrum_touch left_model(TTP229_SCL,left_keys,TTP229_SDO);
 spectrum_touch right_model(TTP_R_SCL,right_keys,TTP_R_SDO);
 integer fd,case_id=0,key=0,panel=0,samples=0,total=0,mismatches=0,note=60,seen_frames=0,ik,ip;
 reg capture=0;reg signed [15:0] sl,sr;
 // Compare the exact sample accepted by the analyzer against the atomic
 // left/right frame currently latched by the production audio bridge.
 always @(posedge dut.g_dual.clk_sys)begin
  if(dut.g_dual.instrument.frame_tick)seen_frames=seen_frames+1;
  if(capture && dut.g_dual.instrument.frame_tick)begin
   sl=dut.g_dual.instrument.visualization.left_q;sr=dut.g_dual.instrument.visualization.right_q;
   note=dut.g_dual.instrument.voice_note[(panel*16+key)*8+:8];
   if(sl!==$signed(dut.g_dual.instrument.audio.pcm_frame[15:0]) ||
      sr!==$signed(dut.g_dual.instrument.audio.pcm_frame[31:16]))mismatches=mismatches+1;
   $fwrite(fd,"0,%0d,%0d,%0d,%0d,%0d,%0d,%0d,-1,0,%0d\n",case_id,samples,key,panel,note,sl,sr,
    (sl!==$signed(dut.g_dual.instrument.audio.pcm_frame[15:0]) || sr!==$signed(dut.g_dual.instrument.audio.pcm_frame[31:16])));
   samples=samples+1;total=total+1;
  end
 end
 always @(negedge dut.g_dual.clk_sys)if(capture && dut.g_dual.instrument.visualization.spec_valid)
  $fwrite(fd,"1,%0d,%0d,%0d,%0d,%0d,0,0,%0d,%0d,0\n",case_id,samples,key,panel,note,
   dut.g_dual.instrument.visualization.spec_addr,dut.g_dual.instrument.visualization.spec_mag);
 task scenario(input integer cid,k,p);
  begin
   capture=0;rst=1;left_keys=0;right_keys=0;#3000;rst=0;#500000;
   case_id=cid;key=k;panel=p;
   if(p==0)left_keys=16'b1<<k;else right_keys=16'b1<<k;
   $display("START case=%0d time=%0t reset=%b aud=%b frames=%0d scanned=%h/%h",cid,$time,dut.g_dual.reset_n,dut.g_dual.clk_aud,seen_frames,dut.g_dual.instrument.keys_left,dut.g_dual.instrument.keys_right);
   wait((p==0?dut.g_dual.instrument.keys_left:dut.g_dual.instrument.keys_right)==(16'b1<<k));
   $display("SCAN case=%0d time=%0t frames=%0d",cid,$time,seen_frames);
   // Let controls and initial envelope settle, then save a complete 4096 PCM
   // sample block and all 32 analysis values on each real publication.
   repeat(1024)@(posedge dut.g_dual.instrument.frame_tick);
   samples=0;capture=1;wait(samples>=4096);
   @(negedge dut.g_dual.clk_sys);capture=0;
   if(dut.g_dual.instrument.visualization.analyser.overrun_count!=0)$fatal(1,"spectrum overrun");
   if(dut.g_dual.instrument.deadline_count!=0)$fatal(1,"engine deadline");
   $display("CAPTURE case=%0d key=%0d panel=%0d note=%0d samples=%0d cumulative_tap_mismatches=%0d",cid,k,p,note,samples,mismatches);
  end
 endtask
 initial begin
  fd=$fopen("key_pcm.csv","w");
  $fwrite(fd,"kind,case_id,sample_id,key,panel,note,left,right,band,mag,tap_mismatch\n");
  if(ALL_KEYS)begin
   for(ip=0;ip<2;ip=ip+1)for(ik=0;ik<16;ik=ik+1)scenario(ip*16+ik,ik,ip);
  end else begin scenario(0,0,0);scenario(1,5,0);scenario(2,7,1);scenario(3,14,1);end
  $fclose(fd);$display("PASS actual serial keys captured: PCM samples=%0d tap_mismatches=%0d",total,mismatches);$finish;
 end
 initial begin #(64'd5000000000);$fatal(1,"timeout");end
endmodule
