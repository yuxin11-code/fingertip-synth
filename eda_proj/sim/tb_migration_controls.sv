`timescale 1ns/1ps
module tb_migration_controls;
wire pluck_toggle_n=1'b1;wire pluck_mode;
 wire test_suspend=0;
reg clk=0; always #5 clk=~clk;
reg rst_n=0, frame_tick=0;
reg [15:0] keys_left=0,keys_right=0;
reg strum_right=0,strum_left=0;
reg key_up_n=1,key_dn_n=1,inst_left_n=1,inst_right_n=1,test_toggle_n=1,aux3_n=1,aux4_n=1;
reg enc_a=1,enc_b=1,enc_c_n=1;
reg signed [7:0] transpose_left=0,transpose_right=0;
reg hmi_valid=0; reg [7:0] hmi_cmd=0; reg [15:0] hmi_value=0; reg selected_panel=0;
wire volume_up_event,volume_down_event;
wire [31:0] voice_gate; wire [255:0] voice_note; wire [63:0] voice_inst;
wire [16:0] volume_q16; wire [3:0] adsr_a,adsr_d,adsr_s,adsr_r;
wire [5:0] active_voices; wire test_mode,strum_active; wire [1:0] inst_l,inst_r;
wire aux3_stable,aux4_stable;
wire [15:0] guitar_attack,guitar_sustain;
wire [3:0] guitar_decay,guitar_release;
`ifdef BASELINE
input_ctrl #(.DB_TICKS(4),.GAP_FRAMES(2),.HOLD_FRAMES(8)) dut(.*);
`else
mig_input_ctrl #(.CLK_HZ(20000),.DB_TICKS(4),.GAP_FRAMES(2),.HOLD_FRAMES(8)) dut(.*);
`endif
task cycles(input integer n); repeat(n) @(negedge clk); endtask
task frame; frame_tick=1; cycles(1); frame_tick=0; cycles(2); endtask
reg [16:0] previous_volume; integer i;
initial begin
 cycles(3); rst_n=1; cycles(5); previous_volume=volume_q16;
`ifndef BASELINE
 if(guitar_attack!=256 || guitar_decay!=3 || guitar_sustain!=2048 || guitar_release!=3)
   $fatal(1,"original guitar defaults");
`endif
 key_up_n=0; cycles(12); key_up_n=1; cycles(12);
 if(volume_q16<=previous_volume || inst_l!=0 || inst_r!=1 || test_mode) $fatal(1,"KEY1 mapping");
 previous_volume=volume_q16;
 key_dn_n=0; cycles(12); key_dn_n=1; cycles(12);
 if(volume_q16>=previous_volume || inst_l!=0) $fatal(1,"KEY2 mapping");
 inst_left_n=0; cycles(12); inst_left_n=1; cycles(12);
 if(inst_l!=1 || inst_r!=1) $fatal(1,"left timbre mapping");
 inst_right_n=0; cycles(12); inst_right_n=1; cycles(12);
 if(inst_l!=1 || inst_r!=2 || test_mode) $fatal(1,"right timbre mapping");
 test_toggle_n=0; cycles(12); test_toggle_n=1; cycles(12);
 if(!test_mode || active_voices!=32 || voice_gate!==32'hffffffff) $fatal(1,"test mode mapping");
 test_toggle_n=0; cycles(12); test_toggle_n=1; cycles(12);
 if(test_mode) $fatal(1,"test mode exit");
 keys_left=16'h8001; cycles(5);
 if(voice_gate[15:0]!=0) $fatal(1,"left guitar must wait for gesture");
 inst_left_n=0; cycles(12); inst_left_n=1; cycles(12);
 if(voice_gate[15:0]!=16'h8001 || active_voices!=2) $fatal(1,"left keys immediate");
 keys_right=16'h0005; cycles(5);
 if(voice_gate[31:16]!=16'h0005) $fatal(1,"right sine must sound directly");
 inst_right_n=0; cycles(12); inst_right_n=1; cycles(12);
 if(inst_r!=0 || voice_gate[31:16]!=16'h0005) $fatal(1,"right piano must sound directly");
 keys_right=0; cycles(5);
 if(voice_gate[31:16]!=0) $fatal(1,"right piano release");
 inst_right_n=0; cycles(12); inst_right_n=1; cycles(12);
 if(inst_r!=1 || voice_gate[31:16]!=0) $fatal(1,"right guitar must wait for gesture");
 keys_right=16'h0005; cycles(5); strum_right=1; cycles(5); strum_right=0;
 for(i=0;i<5;i=i+1) frame;
 if(!voice_gate[16] || voice_gate[18]) $fatal(1,"ascending strum first key");
 for(i=0;i<3;i=i+1) frame;
 if(!voice_gate[18]) $fatal(1,"ascending strum next key");
 for(i=0;i<14;i=i+1) frame;
 strum_left=1; cycles(5); strum_left=0;
 for(i=0;i<5;i=i+1) frame;
 if(!voice_gate[18] || voice_gate[16]) $fatal(1,"descending strum first key");
 // Re-strum while the previous note is still held: must retrigger its ADSR.
 keys_right=16'h0004; cycles(5); strum_right=1; cycles(5); strum_right=0;
 for(i=0;i<3;i=i+1) frame;
 if(voice_gate[18]) $fatal(1,"overlapping strum never releases gate for retrigger");
 frame;
 if(!voice_gate[18]) $fatal(1,"overlapping strum failed to reassert gate");
 // Both panels on guitar: independent chords, same direction and timing.
 inst_left_n=0; cycles(12); inst_left_n=1; cycles(12);
 if(inst_l!=0 || voice_gate[15:0]!=16'h8001) $fatal(1,"left piano direct");
 inst_left_n=0; cycles(12); inst_left_n=1; cycles(12);
 keys_left=16'h000a; keys_right=16'h0005; cycles(5);
 if(voice_gate[15:0]!=0) $fatal(1,"enter guitar must not inherit direct gate");
 repeat(14) frame; // Let the earlier right-panel re-strum finish first.
 strum_right=1; cycles(5); strum_right=0;
 repeat(5) frame;
 if(voice_gate[15:0]!=16'h0002 || voice_gate[31:16]!=16'h0001)
   $fatal(1,"both panels ascending first notes");
 repeat(3) frame;
 if(voice_gate[15:0]!=16'h000a || voice_gate[31:16]!=16'h0005)
   $fatal(1,"both panels ascending second notes");
 repeat(14) frame;
 strum_left=1; cycles(5); strum_left=0;
 repeat(5) frame;
 if(voice_gate[15:0]!=16'h0008 || voice_gate[31:16]!=16'h0004)
   $fatal(1,"both panels descending first notes");
 // Switching out and back must cancel queued and held strum notes.
 repeat(3) begin inst_left_n=0; cycles(12); inst_left_n=1; cycles(12); end
 repeat(10) frame;
 if(voice_gate[15:0]!=0) $fatal(1,"stale left strum after timbre cycle");
 // Full quadrature detents in both directions; one step per detent.
 cycles(30); enc_b=0; cycles(30); enc_a=0; cycles(30); enc_b=1; cycles(30); enc_a=1; cycles(30);
 if(adsr_a!=7) $fatal(1,"encoder CW full detent");
`ifndef BASELINE
 if(guitar_attack!=224) $fatal(1,"original guitar CW slows attack");
`endif
 enc_a=0; cycles(30); enc_b=0; cycles(30); enc_a=1; cycles(30); enc_b=1; cycles(30);
 if(adsr_a!=6) $fatal(1,"encoder CCW full detent");
`ifndef BASELINE
 if(guitar_attack!=252) $fatal(1,"original guitar CCW speeds attack");
`endif
 previous_volume=volume_q16; enc_c_n=0; cycles(420); enc_c_n=1; cycles(420);
 enc_b=0; cycles(30); enc_a=0; cycles(30); enc_b=1; cycles(30); enc_a=1; cycles(30);
 if(adsr_d!=5 || adsr_a!=6 || volume_q16!=previous_volume) $fatal(1,"encoder button stage mapping");
`ifndef BASELINE
 if(guitar_decay!=4 || guitar_attack!=252) $fatal(1,"original guitar decay stage");
`endif
 $display("PASS migration controls"); $finish;
end
initial begin #1000000; $fatal(1,"timeout"); end
endmodule
