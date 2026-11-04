`timescale 1ns/1ps
module tb_migration_guitar;
reg clk=0; always #5 clk=~clk;
reg rst_n=0,frame_tick=0,ref_tick=0;
reg [31:0] v_gate=0;
reg [255:0] v_note={32{8'd60}};
reg [63:0] v_inst={32{2'd1}};
wire [17:0] pitch_scale_q16=18'd65536;
wire [3:0] a_param=6,d_param=4,s_param=12,r_param=5;
reg [15:0] guitar_attack=256,guitar_sustain=2048;
reg [3:0] guitar_decay=3,guitar_release=3;
wire signed [39:0] mix_sum;
wire signed [39:0] panel_a_sum,panel_b_sum;
wire [39:0] env_observe;
mig_voice_engine dut(.*);
wire signed [31:0] reference_gain;
instrument_envelope_volume reference_env(
 .clk(clk),.rst_n(rst_n),.sample_enable(ref_tick),.note_on(v_gate[0]),
 .note_number(v_note[6:0]),.timbre_select(2'd3),
 .attack_step(guitar_attack),.decay_divider_limit(guitar_decay),
 .sustain_level(guitar_sustain),.release_divider_limit(guitar_release),
 .sample_in(32'sd32768),.sample_out(reference_gain));
reg [7:0] idx=0;
wire signed [15:0] new_wave,old_wave;
mig_wave_rom wave(.clk(clk),.inst(2'd1),.idx(idx),.data(new_wave));
instrument_wavetable_bank reference_wave(.clk(clk),.rst_n(rst_n),
 .timbre_select(2'd3),.address(idx),.sample(old_wave));
task frame;
 begin
 @(negedge clk); frame_tick=1; ref_tick=1;
 @(negedge clk); frame_tick=0;
 @(negedge clk); ref_tick=0;
 repeat(42) @(negedge clk);
 if(dut.pipe_valid || dut.running) $fatal(1,"scheduler did not finish");
 // Q15 -> Q16 adaptation must preserve all integer envelope values.
 if(dut.gain[0] !== {reference_gain[15:0],1'b0})
   $fatal(1,"guitar envelope mismatch: %0d vs %0d",dut.gain[0],reference_gain*2);
 if(dut.gain[31] !== dut.gain[0]) $fatal(1,"voice 0/31 envelope timing differs");
 end
endtask
integer i;
initial begin
 repeat(3) @(negedge clk); rst_n=1;
 for(i=0;i<256;i=i+1) begin
  idx=i; @(negedge clk);
  if(new_wave !== old_wave) $fatal(1,"original waveform mismatch at %0d",i);
 end
 v_gate=32'hffffffff;
 repeat(50) frame;
 if(reference_gain<24000) $fatal(1,"original attack peak not reached");
 repeat(25000) frame;
 if(reference_gain!=2048) $fatal(1,"original sustain not reached");
 v_gate=0; repeat(5000) frame;
 if(reference_gain!=0 || mix_sum!=0) $fatal(1,"release did not reach silence");
 v_gate=32'hffffffff; repeat(10) frame;
 v_note={32{8'd62}}; frame;
 if(reference_gain!=256) $fatal(1,"note change retrigger");
 guitar_attack=4096; guitar_sustain=30000; guitar_decay=0; guitar_release=0;
 repeat(20) frame;
 if(reference_gain!=24576) $fatal(1,"sustain clamp at original peak");
 v_gate=0; repeat(7000) frame;
 if(reference_gain!=0) $fatal(1,"edited release failed");
 // A held key must restart when switching out of, and back into, guitar.
 v_gate=32'hffffffff; repeat(10) frame;
 v_inst={32{2'd2}};
 @(negedge clk); frame_tick=1;
 @(negedge clk); frame_tick=0;
 repeat(44) @(negedge clk);
 if(dut.env_st[0]!=1 || dut.gain[0]!=0) $fatal(1,"switch to sine must attack");
 @(negedge clk); frame_tick=1;
 @(negedge clk); frame_tick=0;
 repeat(44) @(negedge clk);
 if(dut.gain[0]==0) $fatal(1,"held key silent after leaving guitar");
 v_inst={32{2'd1}};
 @(negedge clk); frame_tick=1;
 @(negedge clk); frame_tick=0;
 repeat(44) @(negedge clk);
 if(dut.gain[0]!=8192 || dut.gain[31]!=8192) $fatal(1,"switch back to guitar must restart");
 $display("PASS migration guitar: 256 original samples; 32 envelopes, attack/decay/sustain/release, retrigger and parameter edits");
 $finish;
end
initial begin #100000000; $fatal(1,"timeout"); end
endmodule
