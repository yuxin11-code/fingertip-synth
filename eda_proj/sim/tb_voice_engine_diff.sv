`timescale 1ns/1ps
module tb_voice_engine_diff;
  reg clk=0; always #5 clk=~clk;
  reg rst_n=0;
  reg [10:0] frame_count=0;
  wire frame_tick=(frame_count==0);
  always @(posedge clk) if(!rst_n) frame_count<=0;
    else frame_count <= (frame_count==1056) ? 0 : frame_count+1'b1;
  reg [15:0] keys_left=0,keys_right=0;
  reg strum_right=0,strum_left=0;
  reg key_up_n=1,key_dn_n=1,inst_left_n=1,inst_right_n=1;
  reg aux3_n=1,aux4_n=1,test_toggle_n=1;
  reg enc_a=1,enc_b=1,enc_c_n=1;
  reg signed [7:0] transpose_left=0,transpose_right=0;
  reg hmi_valid=0,selected_panel=0;
  reg [7:0] hmi_cmd=0; reg [15:0] hmi_value=0;

  wire [31:0] vg;wire [255:0] vn;wire [95:0] vi;
  wire [16:0] vol;wire [3:0] aa,dd,ss,rr;wire [5:0] active;
  wire tm,sa,a3,a4,vu,vd;wire [2:0] il,ir;wire [15:0] ga,gs;wire [3:0] gd,gr;
  reg [31:0] replay_gate=0;reg [17:0] pitch_scale_q16=65536;
  reg [3:0] extra_a=6,extra_d=4,extra_s=12,extra_r=5;
  wire [31:0] recorded_gate;
  wire recording,playing,record_full;wire [7:0] record_length;
  wire [31:0] record_duration,record_elapsed;
  mig_action_recorder #(.CLK_HZ(20000),.DEPTH(128),.DEBOUNCE_MS(1)) recorder(
    .clk(clk),.rst_n(rst_n),.record_n(aux3_n),.play_n(aux4_n),.live_keys(vg),
    .hmi_valid(hmi_valid),.hmi_cmd(hmi_cmd),.hmi_value(hmi_value),
    .replay_keys(recorded_gate),.recording(recording),.playing(playing),.full(record_full),
    .length(record_length),.duration_ms(record_duration),.elapsed_ms(record_elapsed));
  wire [31:0] gates=vg|replay_gate|recorded_gate;
  reg pitch_up_n=1,pitch_down_n=1;
  wire [17:0] base_pitch,knob_pitch;
  wire signed [4:0] semitone;
  pitch_key_control #(.CLK_HZ(20000),.DEBOUNCE_MS(1),.LONG_PRESS_MS(3)) pitch_control(
    .clk(clk),.rst_n(rst_n),.key_up_n(pitch_up_n),.key_down_n(pitch_down_n),
    .hmi_valid(hmi_valid),.hmi_cmd(hmi_cmd),.hmi_value(hmi_value),
    .pitch_scale_q16(base_pitch),.semitone(semitone));
  reg [5:0] knob_mask=0;reg [101:0] knob_values={6{17'd32768}};
  reg [95:0] knob_raw={6{16'd5000}};
  wire [84:0] knob_targets,knob_actual;
  mig_six_knobs #(.CONTROL_FRAMES(1)) knobs(
    .clk(clk),.rst_n(rst_n),.frame_tick(frame_tick),.write_mask(knob_mask),.write_values(knob_values),
    .fallback_volume(vol),.base_pitch(base_pitch),.hmi_valid(hmi_valid),.hmi_cmd(hmi_cmd),.hmi_value(hmi_value),
    .volume_up_event(vu),.volume_down_event(vd),.raw_values(knob_raw),
    .calibration_low(96'd0),.calibration_high({6{16'd10000}}),.targets(knob_targets),.actual_values(knob_actual),
    .modulated_pitch(knob_pitch));
  wire [17:0] engine_pitch=phase>=7?knob_pitch:pitch_scale_q16;
  wire [3:0] ap=phase>=6?extra_a:aa,dp=phase>=6?extra_d:dd;
  wire [3:0] sp=phase>=6?extra_s:ss,rp=phase>=6?extra_r:rr;
      mig_input_ctrl #(.CLK_HZ(20000),.DB_TICKS(2),.GAP_FRAMES(2),.HOLD_FRAMES(8)) controls(
        .clk(clk),.rst_n(rst_n),.frame_tick(frame_tick),
        .keys_left(keys_left),.keys_right(keys_right),.strum_right(strum_right),.strum_left(strum_left),
        .key_up_n(key_up_n),.key_dn_n(key_dn_n),.inst_left_n(inst_left_n),.inst_right_n(inst_right_n),
        .aux3_n(aux3_n),.aux4_n(aux4_n),.test_toggle_n(test_toggle_n),
        .enc_a(enc_a),.enc_b(enc_b),.enc_c_n(enc_c_n),
        .transpose_left(transpose_left),.transpose_right(transpose_right),
        .hmi_valid(hmi_valid),.hmi_cmd(hmi_cmd),.hmi_value(hmi_value),.selected_panel(selected_panel),
        .voice_gate(vg),.voice_note(vn),.voice_inst(vi),.volume_q16(vol),
        .adsr_a(aa),.adsr_d(dd),.adsr_s(ss),.adsr_r(rr),.active_voices(active),
        .test_mode(tm),.strum_active(sa),.inst_l(il),.inst_r(ir),
        .aux3_stable(a3),.aux4_stable(a4),.volume_up_event(vu),.volume_down_event(vd),
        .guitar_attack(ga),.guitar_sustain(gs),.guitar_decay(gd),.guitar_release(gr));
  wire signed [39:0] mix_ref,pa_ref,pb_ref,mix_new,pa_new,pb_new;
  mig_voice_engine_ref ref_engine(.clk(clk),.rst_n(rst_n),.frame_tick(frame_tick),
    .v_gate(gates),.v_note(vn),.v_inst(vi),.pitch_scale_q16(engine_pitch),
    .a_param(ap),.d_param(dp),.s_param(sp),.r_param(rp),
    .guitar_attack(ga),.guitar_sustain(gs),.guitar_decay(gd),.guitar_release(gr),
    .mix_sum(mix_ref),.panel_a_sum(pa_ref),.panel_b_sum(pb_ref));
  mig_voice_engine dut(.clk(clk),.rst_n(rst_n),.frame_tick(frame_tick),
    .v_gate(gates),.v_note(vn),.v_inst(vi),.pitch_scale_q16(engine_pitch),
    .a_param(ap),.d_param(dp),.s_param(sp),.r_param(rp),
    .guitar_attack(ga),.guitar_sustain(gs),.guitar_decay(gd),.guitar_release(gr),
    .mix_sum(mix_new),.panel_a_sum(pa_new),.panel_b_sum(pb_new));
  integer cycles_checked=0,frames=0,mismatches=0,phase=0;
  integer step_writes=0,last_step_commits=0,env_writes=0;
  integer recorded_overlap=0,pitch_changes=0;reg [17:0] last_pitch=0;
  always @(posedge clk)begin
    if(rst_n) begin
      if(frame_tick)frames=frames+1;
      if(dut.step_wr_valid)begin step_writes=step_writes+1;if(dut.step_wr_addr==31)last_step_commits=last_step_commits+1;end
      if(dut.env_wr_valid)env_writes=env_writes+1;
      if(playing && recorded_gate!=0 && vg!=0)recorded_overlap=recorded_overlap+1;
      if(engine_pitch!=last_pitch)pitch_changes=pitch_changes+1;
      last_pitch=engine_pitch;
    end
    #1;cycles_checked=cycles_checked+1;
    if({mix_new,pa_new,pb_new}!=={mix_ref,pa_ref,pb_ref})begin
      if(mismatches==0)$display("FIRST_DIFF cycle=%0d phase=%0d ref=%0d,%0d,%0d new=%0d,%0d,%0d vidx=%0d/%0d",
        cycles_checked,phase,mix_ref,pa_ref,pb_ref,mix_new,pa_new,pb_new,ref_engine.vidx,dut.vidx);
      mismatches=mismatches+1;
    end
    if(rst_n && (dut.vidx!==dut.vidx_step || dut.vidx!==dut.vidx_env ||
       dut.vidx!==dut.vidx_phase || dut.vidx!==dut.vidx_io))$fatal(1,"scheduler copies diverged");
  end
  task clocks(input integer n); repeat(n) @(negedge clk); endtask
  task command(input [7:0] cmd,input [15:0] value);
    begin hmi_valid=1;hmi_cmd=cmd;hmi_value=value;clocks(1);hmi_valid=0;clocks(3);end
  endtask
  integer t,o,k;
  initial begin
    clocks(5);rst_n=1;clocks(20);
    // All five timbres, both panels, every octave, sustained chords and gestures.
    phase=1;
    for(t=0;t<5;t=t+1) begin
      command(8'h01,t);command(8'h02,4-t);
      for(o=-4;o<=4;o=o+1) begin
        transpose_left=o;transpose_right=-o;
        keys_left=16'h8421;keys_right=16'h2492;clocks(2200);
        strum_right=1;clocks(5);strum_right=0;clocks(2200);
        strum_left=1;clocks(5);strum_left=0;clocks(1100);
        keys_left=0;keys_right=0;clocks(1100);
      end
    end
    // Physical timbre/test keys, single keys and coincident TDMA boundaries.
    phase=2;transpose_left=0;transpose_right=0;
    inst_left_n=0;inst_right_n=0;clocks(8);inst_left_n=1;inst_right_n=1;clocks(8);
    for(k=0;k<16;k=k+1) begin
      keys_left=16'd1<<k;keys_right=16'h8000>>k;clocks(1100);
    end
    keys_left=16'hffff;keys_right=16'hffff;clocks(2200);
    phase=3;command(8'h12,1);clocks(12000);command(8'h12,0);clocks(2200);
    test_toggle_n=0;clocks(8);test_toggle_n=1;clocks(5000);
    test_toggle_n=0;clocks(8);test_toggle_n=1;clocks(2200);
    phase=4;
    // Inputs can legally change at any system clock relative to the voice pass.
    for(k=0;k<40;k=k+1) begin
      while(frame_count!=k) clocks(1);
      transpose_left=(k%9)-4;transpose_right=4-(k%9);
      keys_left=~keys_left;keys_right=~keys_right;
      command(8'h01,k%5);clocks(1100);
    end
    phase=5;
    keys_left=16'hffff;keys_right=16'hffff;
    for(k=0;k<16;k=k+1)begin
      pitch_scale_q16=32768+k*8192;
      replay_gate=32'h80018001 << (k%4);
      clocks(2200);
    end
    phase=6;
    for(k=0;k<32;k=k+1)begin
      clocks(1);extra_a=k[3:0];extra_d=15-k[3:0];extra_s=k[3:0];extra_r=15-k[3:0];
      replay_gate=32'h00018001;clocks(1100);
    end
    phase=7;replay_gate=0;
    command(8'h10,1);keys_left=16'h0001;clocks(2200);
    keys_left=16'h8000;keys_right=16'h0001;clocks(2200);
    keys_left=0;keys_right=16'h8000;clocks(2200);command(8'h10,0);
    if(record_length<3)$fatal(1,"record coverage missing");
    keys_left=16'h8001;command(8'h11,1);clocks(6000);command(8'h11,0);
    for(k=-12;k<=12;k=k+1)begin command(8'h05,k);clocks(1100);end
    pitch_up_n=0;clocks(200);pitch_up_n=1;clocks(200);
    pitch_down_n=0;clocks(200);pitch_down_n=1;clocks(200);
    for(k=0;k<6;k=k+1)begin
      knob_values[k*17+:17]=60000;knob_raw[k*16+:16]=9000;knob_mask=1<<k;clocks(1);knob_mask=0;clocks(2200);
    end
    keys_left=0;keys_right=0;clocks(12000);

    $display("VOICE_DIFF cycles=%0d frames=%0d mismatches=%0d output_delay=0 step_writes=%0d last_voice_commits=%0d env_writes=%0d",cycles_checked,frames,mismatches,step_writes,last_step_commits,env_writes);
    $display("COVERAGE recorder_events=%0d replay_live_overlap_clocks=%0d pitch_changes=%0d semitone_sweep=-12..12 rp108_slots=6",record_length,recorded_overlap,pitch_changes);
    if(mismatches || last_step_commits==0 || env_writes==0 || recorded_overlap==0 || pitch_changes<25)$fatal(1,"FAIL voice engine differential");
    $display("PASS voice engine differential mismatches=0 delay=0");$finish;
  end
  initial begin #15000000;$fatal(1,"timeout");end
endmodule
