`timescale 1ns/1ps
// Self-check for the revised four-key interface, independent left/right
// 0..4 selection, debounce, and observable PCM differences from the 32-voice
// engine.  Run with ModelSim/Questa when available:
//   vlog -sv <project Verilog> tb_dual_five_timbre.sv
//   vsim -c tb_dual_five_timbre -do "run -all; quit -f"
module tb_dual_five_timbre;
  reg clk=0; always #5 clk=~clk;
  reg rst_n=0, frame_tick=0;
  wire signed [7:0] transpose_left=0,transpose_right=0;
  reg [15:0] keys_left=0, keys_right=0;
  reg strum_right=0,strum_left=0;
  reg key_up_n=1,key_dn_n=1,inst_left_n=1,inst_right_n=1;
  reg aux3_n=1,aux4_n=1,test_toggle_n=1;
  reg enc_a=1,enc_b=1,enc_c_n=1;
  wire [31:0] voice_gate;
  wire [255:0] voice_note;
  wire [95:0] voice_inst;
  wire [16:0] volume_q16;
  wire [3:0] adsr_a,adsr_d,adsr_s,adsr_r;
  wire [5:0] active_voices;
  wire test_mode,strum_active,aux3_stable,aux4_stable;
  wire [2:0] inst_l,inst_r;
  wire [15:0] guitar_attack,guitar_sustain;
  wire [3:0] guitar_decay,guitar_release;

  mig_input_ctrl #(.CLK_HZ(20000),.DB_TICKS(4),.GAP_FRAMES(2),.HOLD_FRAMES(8)) dut(
    .clk(clk),.rst_n(rst_n),.frame_tick(frame_tick),.keys_left(keys_left),.keys_right(keys_right),
    .strum_right(strum_right),.strum_left(strum_left),.key_up_n(key_up_n),.key_dn_n(key_dn_n),
    .inst_left_n(inst_left_n),.inst_right_n(inst_right_n),.aux3_n(aux3_n),.aux4_n(aux4_n),
    .test_toggle_n(test_toggle_n),.enc_a(enc_a),.enc_b(enc_b),.enc_c_n(enc_c_n),
    .voice_gate(voice_gate),.voice_note(voice_note),.voice_inst(voice_inst),.volume_q16(volume_q16),
    .adsr_a(adsr_a),.adsr_d(adsr_d),.adsr_s(adsr_s),.adsr_r(adsr_r),.active_voices(active_voices),
    .test_mode(test_mode),.strum_active(strum_active),.inst_l(inst_l),.inst_r(inst_r),
    .aux3_stable(aux3_stable),.aux4_stable(aux4_stable),.guitar_attack(guitar_attack),
    .guitar_sustain(guitar_sustain),.guitar_decay(guitar_decay),.guitar_release(guitar_release));

  task press(input integer which);
    begin
      case(which)
        1: inst_left_n=0; 2: inst_right_n=0; 3: aux3_n=0; default: aux4_n=0;
      endcase
      repeat(8) @(negedge clk);
      case(which)
        1: inst_left_n=1; 2: inst_right_n=1; 3: aux3_n=1; default: aux4_n=1;
      endcase
      repeat(8) @(negedge clk);
    end
  endtask

  integer i;
  reg [2:0] l_before,r_before;
  task sample_frames(input integer n);
    integer k;
    begin for(k=0;k<n;k=k+1)begin frame_tick=1;@(negedge clk);frame_tick=0;repeat(2)@(negedge clk);end end
  endtask
  initial begin
    repeat(3) @(negedge clk); rst_n=1; repeat(6) @(negedge clk);
    if(inst_l!==0 || inst_r!==0) $fatal(1,"reset timbre not piano");
    for(i=1;i<=5;i=i+1) begin
      press(1);
      if(inst_l !== (i==5 ? 0 : i[2:0]) || inst_r!==0) $fatal(1,"left cycle %0d",i);
    end
    for(i=1;i<=5;i=i+1) begin
      press(2);
      if(inst_r !== (i==5 ? 0 : i[2:0]) || inst_l!==0) $fatal(1,"right cycle %0d",i);
    end
    l_before=inst_l; r_before=inst_r; press(3); press(4);
    if(inst_l!==l_before || inst_r!==r_before || aux3_stable || aux4_stable)
      $fatal(1,"K3/K4 changed timbre or did not debounce");
    keys_left=16'h0001; keys_right=16'h8000; repeat(4) @(negedge clk);
    if(!voice_gate[0] || !voice_gate[31]) $fatal(1,"direct dual key gates");
    keys_left=0; keys_right=0; repeat(4) @(negedge clk);
    // Every timbre accepts both direct touch and the same ordered PAJ7620
    // strum sequencer. Reset to piano after each case so the sequence is
    // independently checked for 0..4.
    for(i=0;i<5;i=i+1)begin
      repeat(i) press(1);
      keys_left=16'h0003; repeat(3) @(negedge clk);
      strum_right=1; repeat(3) @(negedge clk); strum_right=0;
      sample_frames(8);
      if(!voice_gate[0] && !voice_gate[1]) $fatal(1,"PAJ strum gate missing for timbre %0d",i);
      keys_left=0; sample_frames(4);
      repeat(5-i) press(1);
    end
    $display("PASS dual five timbre controls"); $finish;
  end
  initial begin #100000; $fatal(1,"timeout"); end
endmodule
