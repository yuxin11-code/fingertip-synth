`timescale 1ns/1ps
// Accelerated peripheral timing only: no force on the DUT touch vectors.
module mig_test_touch(input wire scl,enabled,input wire [15:0] keys,output reg sdo=1);
integer bit_index=0; reg [15:0] latched=0; time last_edge=0;
always @(negedge scl) begin
 last_edge=$time;
 if(enabled) begin
  if(bit_index==0) latched=keys;
  sdo<=#1 ~latched[bit_index];
  bit_index=(bit_index+1)%16;
 end
end
always begin
 #50;
 if(!enabled || $time-last_edge>600) begin bit_index=0; sdo=1; end
end
endmodule
module tb_migration_panels;
reg rst=1,KEY1=1,KEY2=1,TIMBRE_KEY=1,ENC_A=1,ENC_B=1,ENC_C=1,PITCH_UP_KEY=1,PITCH_DOWN_KEY=1;
reg K_LEFT=1,K_RIGHT=1,TEST_MODE_KEY=1,UART_RX=1;
wire TTP229_SDO,TTP_R_SDO;
reg right_connected=0; reg [15:0] left_keys=16'h8001,right_keys=16'h0005;
tri1 PAJ_SCL,PAJ_SDA;
wire TTP229_SCL,TTP_R_SCL,HP_BCK,HP_WS,HP_DIN,PA_EN,WS2812_DIN,UART_TX;
top #(.ENABLE_DUAL_PANEL(1)) dut(.*);
defparam dut.g_dual.instrument.left_touch.CLK_HZ=20000;
defparam dut.g_dual.instrument.right_touch.CLK_HZ=20000;
defparam dut.g_dual.instrument.left_touch.SCL_HZ=2000;
defparam dut.g_dual.instrument.right_touch.SCL_HZ=2000;
mig_test_touch left_model(TTP229_SCL,1'b1,left_keys,TTP229_SDO);
mig_test_touch right_model(TTP_R_SCL,right_connected,right_keys,TTP_R_SDO);
integer left_frames=0,right_frames=0;
always @(posedge dut.g_dual.clk_sys) begin
 if(dut.g_dual.instrument.left_touch.frame_valid) left_frames=left_frames+1;
 if(dut.g_dual.instrument.right_touch.frame_valid) right_frames=right_frames+1;
end
initial begin
 #3000; rst=0; #300000;
 if(left_frames!=0 || right_frames!=0) $fatal(1,"startup wait bypassed");
 #300000;
 if(left_frames<2 || right_frames<2) $fatal(1,"no complete touch frames");
 if(dut.g_dual.instrument.keys_left!==16'h8001 || dut.g_dual.instrument.keys_right!==0 || dut.g_dual.instrument.voice_gate[31:16]!==0) $fatal(1,"absent right panel or left serial mapping");
 right_connected=1; #50000;
 if(dut.g_dual.instrument.keys_right!==16'h0005) $fatal(1,"right panel serial mapping");
 left_keys=16'h0084; right_keys=16'h8000; #50000;
 if(dut.g_dual.instrument.keys_left!==16'h0084 || dut.g_dual.instrument.keys_right!==16'h8000) $fatal(1,"updated panel bitmaps");
 rst=1; #3000; rst=0; #100000;
 if(dut.g_dual.instrument.keys_left!==0 || dut.g_dual.instrument.keys_right!==0 || dut.g_dual.instrument.pcm!==0) $fatal(1,"warm reset stale state");
 #500000;
 if(dut.g_dual.instrument.keys_left!==16'h0084 || dut.g_dual.instrument.keys_right!==16'h8000) $fatal(1,"warm reset reacquisition");
 $display("PASS migration panels"); $finish;
end
endmodule
