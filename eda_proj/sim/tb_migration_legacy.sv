`timescale 1ns/1ps
module tb_migration_legacy;
reg rst=1,KEY1=1,KEY2=1,TIMBRE_KEY=1,TTP229_SDO=1,ENC_A=1,ENC_B=1,ENC_C=1,PITCH_UP_KEY=1,PITCH_DOWN_KEY=1;
tri1 PAJ_SCL,PAJ_SDA,ref_scl,ref_sda;
wire TTP229_SCL,HP_BCK,HP_WS,HP_DIN,PA_EN,WS2812_DIN;
wire ref_touch,ref_bck,ref_ws,ref_din,ref_pa,ref_led,unused_scl,unused_uart;
top #(.ENABLE_DUAL_PANEL(0)) dut(.rst(rst),.KEY1(KEY1),.KEY2(KEY2),.TIMBRE_KEY(TIMBRE_KEY),.TTP229_SDO(TTP229_SDO),
 .ENC_A(ENC_A),.ENC_B(ENC_B),.ENC_C(ENC_C),.PITCH_UP_KEY(PITCH_UP_KEY),.PITCH_DOWN_KEY(PITCH_DOWN_KEY),
 .PAJ_SCL(PAJ_SCL),.PAJ_SDA(PAJ_SDA),.TTP229_SCL(TTP229_SCL),.HP_BCK(HP_BCK),.HP_WS(HP_WS),.HP_DIN(HP_DIN),.PA_EN(PA_EN),.WS2812_DIN(WS2812_DIN),
 .K_LEFT(1'b1),.K_RIGHT(1'b1),.TEST_MODE_KEY(1'b1),.TTP_R_SDO(1'b1),.TTP_R_SCL(unused_scl),.UART_TX(unused_uart));
top_reference reference(.rst(rst),.KEY1(KEY1),.KEY2(KEY2),.TIMBRE_KEY(TIMBRE_KEY),.TTP229_SDO(TTP229_SDO),
 .ENC_A(ENC_A),.ENC_B(ENC_B),.ENC_C(ENC_C),.PITCH_UP_KEY(PITCH_UP_KEY),.PITCH_DOWN_KEY(PITCH_DOWN_KEY),
 .PAJ_SCL(ref_scl),.PAJ_SDA(ref_sda),.TTP229_SCL(ref_touch),.HP_BCK(ref_bck),.HP_WS(ref_ws),.HP_DIN(ref_din),.PA_EN(ref_pa),.WS2812_DIN(ref_led));
integer checks=0;
always @(negedge HP_BCK) if(!rst) begin
 if({HP_WS,HP_DIN,PA_EN,WS2812_DIN,TTP229_SCL,PAJ_SCL,PAJ_SDA} !== {ref_ws,ref_din,ref_pa,ref_led,ref_touch,ref_scl,ref_sda}) $fatal(1,"legacy output changed");
 checks=checks+1;
end
initial begin
 #3000; rst=0;
 force dut.g_legacy.touch_keys_raw=16'h0085; force reference.touch_keys_raw=16'h0085;
 #200000;
 force dut.g_legacy.timbre_select=1; force reference.timbre_select=1; #200000;
 force dut.g_legacy.timbre_select=2; force reference.timbre_select=2; #200000;
 force dut.g_legacy.timbre_select=3; force reference.timbre_select=3;
 force dut.g_legacy.paj_init_ok=1; force reference.paj_init_ok=1;
 force dut.g_legacy.paj_sensor_error=0; force reference.paj_sensor_error=0;
 force dut.g_legacy.paj_right_pulse=1; force reference.paj_right_pulse=1; #1000;
 force dut.g_legacy.paj_right_pulse=0; force reference.paj_right_pulse=0;
 #200000;
 if(checks<1000) $fatal(1,"insufficient legacy samples");
 $display("PASS migration legacy"); $finish;
end
endmodule
