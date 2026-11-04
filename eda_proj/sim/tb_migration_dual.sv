`timescale 1ns/1ps
module tb_migration_dual;
reg rst=1,KEY1=1,KEY2=1,TIMBRE_KEY=1,TTP229_SDO=1,ENC_A=1,ENC_B=1,ENC_C=1,PITCH_UP_KEY=1,PITCH_DOWN_KEY=1;
reg K_LEFT=1,K_RIGHT=1,TEST_MODE_KEY=1,TTP_R_SDO=1,UART_RX=1;
tri1 PAJ_SCL,PAJ_SDA;
wire TTP229_SCL,TTP_R_SCL,HP_BCK,HP_WS,HP_DIN,PA_EN,WS2812_DIN,UART_TX;
top #(.ENABLE_DUAL_PANEL(1)) dut(.*);
defparam dut.g_dual.instrument.controls.DB_TICKS=4;
defparam dut.g_dual.instrument.pitch.CLK_HZ=20000;
integer ticks=0; reg [31:0] prior_step;
always @(posedge dut.g_dual.clk_sys) if(dut.g_dual.instrument.frame_tick) ticks=ticks+1;
initial begin
 #3000; rst=0; #3000;
 force dut.g_dual.instrument.keys_left=16'h8001;
 force dut.g_dual.instrument.keys_right=16'h0005;
 #10000;
 if(dut.g_dual.instrument.voice_gate[15:0]!=16'h8001 || dut.g_dual.instrument.voice_gate[31:16]!=0) $fatal(1,"dual touch routing");
 K_LEFT=0; #1000; K_LEFT=1; #1000;
 if(dut.g_dual.instrument.inst_l!=1 || dut.g_dual.instrument.inst_r!=1) $fatal(1,"top K_LEFT");
 K_RIGHT=0; #1000; K_RIGHT=1; #1000;
 if(dut.g_dual.instrument.inst_r!=2) $fatal(1,"top K_RIGHT");
 if(dut.g_dual.instrument.voice_gate[15:0]!=16'h8001 || dut.g_dual.instrument.voice_gate[31:16]!=16'h0005)
   $fatal(1,"direct touch must work for both selected timbres");
 PITCH_UP_KEY=0; #10000; PITCH_UP_KEY=1; #10000;
 if(dut.g_dual.instrument.pitch_scale_q16<=65536) $fatal(1,"original pitch pin not connected");
 TEST_MODE_KEY=0; #1000; TEST_MODE_KEY=1; #1500000;
 if(!dut.g_dual.instrument.test_mode || dut.g_dual.instrument.active_voices!=32) $fatal(1,"top test key");
 if(^dut.g_dual.instrument.pcm===1'bx || dut.g_dual.instrument.mix_sum==0) $fatal(1,"invalid mixed audio");
 if(ticks<60 || ticks>100) $fatal(1,"frame rate wrong %0d",ticks);
 if(PA_EN!==0) $fatal(1,"PA enable changed");
 // Inject logical knob data at the future driver boundary. Physical I2C is TBD.
 force dut.g_dual.instrument.knob_write_values={17'd32768,17'd0,17'd65536,17'd0,17'd65536};
 force dut.g_dual.instrument.knob_write_mask=5'b11111;
 #100; release dut.g_dual.instrument.knob_write_mask;
 #7000000;
 if(dut.g_dual.instrument.master!=65536 || dut.g_dual.instrument.blend!=0 ||
    dut.g_dual.instrument.balance!=65536) $fatal(1,"knob boundary not connected");
 if(dut.g_dual.instrument.pcm!=0 || dut.g_dual.instrument.pcm_right==0)
    $fatal(1,"knob right-only stereo path");
 release dut.g_dual.instrument.knob_write_values;
 $display("PASS migration dual"); $finish;
end
endmodule
