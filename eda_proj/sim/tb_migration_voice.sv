`timescale 1ns/1ps
module tb_migration_voice;
reg clk=0; always #5 clk=~clk;
reg rst_n=0,frame_tick=0;
reg [31:0] v_gate=0; reg [255:0] v_note=0; reg [63:0] v_inst={32{2'd2}};
reg [3:0] a_param=6,d_param=4,s_param=15,r_param=5;
reg [17:0] pitch_scale_q16=65536;
wire signed [39:0] mix_sum;
wire signed [39:0] panel_a_sum,panel_b_sum;
wire [15:0] guitar_attack=256,guitar_sustain=2048;
wire [3:0] guitar_decay=3,guitar_release=3;
`ifdef BASELINE
voice_engine dut(.clk(clk),.rst_n(rst_n),.frame_tick(frame_tick),.v_gate(v_gate),.v_note(v_note),.v_inst(v_inst),.a_param(a_param),.d_param(d_param),.s_param(s_param),.r_param(r_param),.mix_sum(mix_sum));
`else
wire [39:0] env_observe;
mig_voice_engine dut(.*);
`endif
integer i;
task cycles(input integer n); repeat(n) @(negedge clk); endtask
task frame; frame_tick=1; cycles(1); frame_tick=0; cycles(48); endtask
task seed(input integer voice_id);
 begin
 rst_n=0; cycles(3); rst_n=1; cycles(3); v_gate=32'd1<<voice_id;
 for(i=0;i<32;i=i+1) begin
 v_note[i*8+:8]=60; dut.note_d[i]=60;
`ifndef BASELINE
 dut.inst_d[i]=2;
`endif
 dut.phase[i]=32'h40000000; dut.step[i]=0;
 dut.gain[i]=(i==voice_id)?65535:0;
 dut.env_st[i]=(i==voice_id)?3:0; dut.gate_d[i]=(i==voice_id);
 end
 end
endtask
reg [31:0] normal_step;
initial begin
 seed(0); frame;
 if(mix_sum!==40'sd32766) $fatal(1,"first voice ROM/gain alignment: %0d",mix_sum);
 if(panel_a_sum!==32766 || panel_b_sum!==0) $fatal(1,"first voice panel routing");
 seed(31); frame;
 if(mix_sum!==40'sd32766) $fatal(1,"last voice ROM/gain alignment: %0d",mix_sum);
 if(panel_b_sum!==32766 || panel_a_sum!==0) $fatal(1,"last voice panel routing");
`ifndef BASELINE
 normal_step=dut.step[31]; pitch_scale_q16=131072; frame;
 if(dut.step[31]!=normal_step*2) $fatal(1,"live pitch x2");
 pitch_scale_q16=65536;
 rst_n=0; cycles(3); rst_n=1; cycles(3); v_gate=32'hffffffff;
 for(i=0;i<32;i=i+1) v_note[i*8+:8]=36+i;
 repeat(40) frame;
 for(i=0;i<32;i=i+1) begin
 if(dut.gain[i]==0 || dut.step[i]==0 || dut.phase[i]==0) $fatal(1,"voice %0d inactive",i);
 if(i>0 && dut.step[i]<=dut.step[i-1]) $fatal(1,"note steps not ascending");
 end
`endif
 $display("PASS migration voice"); $finish;
end
initial begin #1000000; $fatal(1,"timeout"); end
endmodule
