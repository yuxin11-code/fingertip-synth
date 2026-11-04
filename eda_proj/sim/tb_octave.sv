`timescale 1ns/1ps
module tb_octave;
  reg clk=0; always #5 clk=~clk;
  reg rst_n=0; reg [6:0] fc=0;
  always @(posedge clk) fc<=fc+1;
  wire frame_tick=(fc==0);
  reg enc_a=1,enc_b=1,enc_sw_n=1;
  reg hmi_valid=0; reg [7:0] hmi_cmd=0; reg [15:0] hmi_value=0;
  wire selected_panel;
  wire signed [7:0] transpose_left,transpose_right;
  mig_octave_control #(.CLK_HZ(20000)) oct(.*);
  wire wide_selected;
  wire signed [7:0] wide_left,wide_right;
  mig_octave_control #(.CLK_HZ(20000),.T_MIN(-12),.T_MAX(12)) wide_oct(
    .clk(clk),.rst_n(rst_n),.enc_a(enc_a),.enc_b(enc_b),.enc_sw_n(enc_sw_n),
    .selected_panel(wide_selected),.transpose_left(wide_left),.transpose_right(wide_right));
  reg [15:0] keys_left=0,keys_right=0;
  reg strum_right=0,strum_left=0;
  reg key_up_n=1,key_dn_n=1,inst_left_n=1,inst_right_n=1;
  reg aux3_n=1,aux4_n=1,test_toggle_n=1;
  wire [31:0] voice_gate; wire [255:0] voice_note; wire [95:0] voice_inst;
  wire [16:0] volume_q16; wire [3:0] adsr_a,adsr_d,adsr_s,adsr_r;
  wire [5:0] active_voices; wire test_mode,strum_active,aux3_stable,aux4_stable;
  wire [2:0] inst_l,inst_r;
  wire [15:0] guitar_attack,guitar_sustain; wire [3:0] guitar_decay,guitar_release;
  // Original ADSR encoder remains idle. Only the dedicated OCT encoder moves.
  mig_input_ctrl #(.CLK_HZ(20000),.DB_TICKS(4),.GAP_FRAMES(2),.HOLD_FRAMES(80)) ctrl(
    .clk(clk),.rst_n(rst_n),.frame_tick(frame_tick),.keys_left(keys_left),.keys_right(keys_right),
    .strum_right(strum_right),.strum_left(strum_left),.key_up_n(key_up_n),.key_dn_n(key_dn_n),
    .inst_left_n(inst_left_n),.inst_right_n(inst_right_n),.aux3_n(aux3_n),.aux4_n(aux4_n),
    .test_toggle_n(test_toggle_n),.enc_a(1'b1),.enc_b(1'b1),.enc_c_n(1'b1),
    .transpose_left(transpose_left),.transpose_right(transpose_right),
    .voice_gate(voice_gate),.voice_note(voice_note),.voice_inst(voice_inst),.volume_q16(volume_q16),
    .adsr_a(adsr_a),.adsr_d(adsr_d),.adsr_s(adsr_s),.adsr_r(adsr_r),
    .active_voices(active_voices),.test_mode(test_mode),.strum_active(strum_active),
    .inst_l(inst_l),.inst_r(inst_r),.aux3_stable(aux3_stable),.aux4_stable(aux4_stable),
    .guitar_attack(guitar_attack),.guitar_sustain(guitar_sustain),.guitar_decay(guitar_decay),.guitar_release(guitar_release));
  wire signed [39:0] mix_sum,panel_a_sum,panel_b_sum;
  mig_voice_engine voices(.clk(clk),.rst_n(rst_n),.frame_tick(frame_tick),
    .v_gate(voice_gate),.v_note(voice_note),.v_inst(voice_inst),.pitch_scale_q16(18'd65536),
    .a_param(adsr_a),.d_param(adsr_d),.s_param(adsr_s),.r_param(adsr_r),
    .guitar_attack(guitar_attack),.guitar_sustain(guitar_sustain),.guitar_decay(guitar_decay),
    .guitar_release(guitar_release),.mix_sum(mix_sum),.panel_a_sum(panel_a_sum),.panel_b_sum(panel_b_sum));
  wire signed [15:0] pcm_left,pcm_right;
  mig_stereo_mixer mix(.clk(clk),.rst_n(rst_n),.panel_a(panel_a_sum),.panel_b(panel_b_sum),
    .master(17'd32768),.blend(17'd32768),.balance(17'd32768),.test_atten(1'b0),
    .pcm_left(pcm_left),.pcm_right(pcm_right));
  task cycles(input integer n); repeat(n) @(negedge clk); endtask
  task detent(input bit cw);
    if(cw) begin
      enc_b=0; cycles(40); enc_a=0; cycles(40); enc_b=1; cycles(40); enc_a=1; cycles(40);
    end else begin
      enc_a=0; cycles(40); enc_b=0; cycles(40); enc_a=1; cycles(40); enc_b=1; cycles(40);
    end
  endtask
  task press; enc_sw_n=0; cycles(500); enc_sw_n=1; cycles(500); endtask
  task check_pcm;
    integer peak,k;
    begin
      peak=0;
      for(k=0;k<20000;k=k+1) begin cycles(1); if(pcm_left>peak) peak=pcm_left; end
      if(peak<10) $fatal(1,"final mixer PCM silent");
    end
  endtask
  reg [31:0] step0,step16;
  integer i;
  initial begin
    cycles(5); rst_n=1; cycles(10);
    if(inst_l!==0 || inst_r!==0 || selected_panel!==0) $fatal(1,"reset defaults");
    for(i=0;i<16;i=i+1) if(voice_note[i*8+:8]!==voice_note[(16+i)*8+:8]) $fatal(1,"panel scale differs");
    if(voice_note[7:0]!==60 || voice_note[127:120]!==86) $fatal(1,"existing C4..D6 map changed");
    keys_left=16'h0001; keys_right=16'h0001; check_pcm;
    step0=voices.step[0]; step16=voices.step[16];
    detent(1); cycles(512);
    if(transpose_left!==1 || transpose_right!==0 || voices.step[0]!==step0*2 || voices.step[16]!==step16) $fatal(1,"one octave left independence");
    detent(1); cycles(512);
    if(voices.step[0]!==step0*4) $fatal(1,"two octaves");
    repeat(8) detent(1);
    if(transpose_left!==4) $fatal(1,"upper clamp");
    if(wide_left!==10) $fatal(1,"T_MAX override still clamped at four");
    repeat(12) detent(0);
    if(transpose_left!==-4 || transpose_right!==0) $fatal(1,"lower clamp");
    if(wide_left!==-2) $fatal(1,"T_MIN override");
    press; if(selected_panel!==1) $fatal(1,"selection");
    detent(1); detent(1);
    if(transpose_right!==2 || transpose_left!==-4) $fatal(1,"right independent memory");
    enc_sw_n=0; cycles(2000);
    if(selected_panel!==0) $fatal(1,"long press repeated");
    enc_sw_n=1; cycles(500);
    // Short bounce cannot select another panel.
    repeat(5) begin enc_sw_n=0; cycles(10); enc_sw_n=1; cycles(10); end
    cycles(500); if(selected_panel!==0) $fatal(1,"SW bounce");
    repeat(4) detent(1);
    if(transpose_left!==0 || transpose_right!==2) $fatal(1,"restore independent values");
    // Simultaneous timbre presses must affect both; K2 alone only right.
    inst_right_n=0; cycles(12); inst_right_n=1; cycles(12);
    if(inst_r!==1 || inst_l!==0) $fatal(1,"K2 timbre");
    repeat(4) begin inst_right_n=0; cycles(12); inst_right_n=1; cycles(12); end
    if(inst_r!==0) $fatal(1,"right cycle piano");
    repeat(5) begin inst_left_n=0;inst_right_n=0;cycles(12);inst_left_n=1;inst_right_n=1;cycles(12); end
    if(inst_l!==0 || inst_r!==0) $fatal(1,"simultaneous timbre cycle");
    keys_left=0;keys_right=0;cycles(512);keys_left=3;keys_right=5;check_pcm;
    if(adsr_a!==6 || adsr_d!==4 || adsr_s!==12 || adsr_r!==5) $fatal(1,"octave encoder edited ADSR");
    $display("PASS octave: detents +/-4, independent panel selection, debounce, identical scale, live DDS x2/x4, K2, final PCM");
    $finish;
  end
  initial begin #10000000; $fatal(1,"timeout"); end
endmodule
