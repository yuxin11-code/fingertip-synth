`timescale 1ns/1ps
// Regression for the field failure: after 0->1->2->3->4->0, a new piano
// key must reach the voice engine and produce non-zero panel PCM.
module tb_piano_cycle_regression;
 wire pluck_toggle_n=1'b1;wire pluck_mode;
 wire test_suspend=0;
  reg clk=0; always #5 clk=~clk;
  reg rst_n=0, frame_tick=0;
  wire signed [7:0] transpose_left=0,transpose_right=0;
  reg [15:0] keys_left=0, keys_right=0;
  reg inst_left_n=1,inst_right_n=1;
  reg key_up_n=1,key_dn_n=1,aux3_n=1,aux4_n=1,test_toggle_n=1;
  reg strum_right=0,strum_left=0,enc_a=1,enc_b=1,enc_c_n=1;
  reg hmi_valid=0; reg [7:0] hmi_cmd=0; reg [15:0] hmi_value=0; reg selected_panel=0;
  wire volume_up_event,volume_down_event;
  wire [31:0] voice_gate; wire [255:0] voice_note; wire [95:0] voice_inst;
  wire [16:0] volume_q16; wire [3:0] adsr_a,adsr_d,adsr_s,adsr_r;
  wire [5:0] active_voices; wire test_mode,strum_active,aux3_stable,aux4_stable;
  wire [2:0] inst_l,inst_r;
  wire [15:0] guitar_attack,guitar_sustain; wire [3:0] guitar_decay,guitar_release;
  wire signed [39:0] mix_sum,panel_a_sum,panel_b_sum;
  mig_input_ctrl #(.CLK_HZ(20000),.DB_TICKS(2),.GAP_FRAMES(2),.HOLD_FRAMES(8)) ctrl(.*);
  mig_voice_engine voices(.clk(clk),.rst_n(rst_n),.frame_tick(frame_tick),.v_gate(voice_gate),
    .v_note(voice_note),.v_inst(voice_inst),.pitch_scale_q16(18'd65536),
    .guitar_attack(guitar_attack),.guitar_sustain(guitar_sustain),.guitar_decay(guitar_decay),
    .guitar_release(guitar_release),.a_param(adsr_a),.d_param(adsr_d),.s_param(adsr_s),
    .r_param(adsr_r),.mix_sum(mix_sum),.panel_a_sum(panel_a_sum),.panel_b_sum(panel_b_sum));
  task cycles(input integer n); repeat(n) @(negedge clk); endtask
  task frame; begin frame_tick=1; cycles(1); frame_tick=0; cycles(60); end endtask
  task left_press;
    begin inst_left_n=0; cycles(6); inst_left_n=1; cycles(6); end
  endtask
  task right_press;
    begin inst_right_n=0; cycles(6); inst_right_n=1; cycles(6); end
  endtask
  integer n,s;
  task check_sound(input integer panel);
    integer k,peak;
    reg signed [39:0] value;
    begin
      peak=0;
      // A single PCM sample can legitimately be zero at a waveform crossing.
      // Check a time window rather than requiring every sampled instant nonzero.
      for(k=0;k<24;k=k+1) begin
        frame;
        value=panel ? panel_b_sum : panel_a_sum;
        if(value<0) value=-value;
        if(value>peak) peak=value;
      end
      if(peak<32) $fatal(1,"piano PCM window silent panel %0d cycle %0d",panel,n);
    end
  endtask
  initial begin
    cycles(4); rst_n=1; cycles(8);
    if(inst_l!==0 || inst_r!==0) $fatal(1,"piano reset state");
    for(n=0;n<100;n=n+1) begin
      for(s=0;s<5;s=s+1) left_press();
      if(inst_l!==0) $fatal(1,"left cycle state %0d",n);
      keys_left=16'h0001; check_sound(0);
      keys_left=0; repeat(3) frame;
    end
    for(n=0;n<100;n=n+1) begin
      for(s=0;s<5;s=s+1) right_press();
      if(inst_r!==0) $fatal(1,"right cycle state %0d",n);
      keys_right=16'h0001; check_sound(1);
      keys_right=0; repeat(3) frame;
    end
    keys_left=16'h0001; keys_right=16'h0001; check_sound(0);check_sound(1);
    $display("PASS piano cycle regression"); $finish;
  end
  initial begin #20000000; $fatal(1,"timeout"); end
endmodule
