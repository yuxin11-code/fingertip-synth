`timescale 1ns/1ps
// Acceptance: transpose input register -> old controls -> output register
// -> original engine, versus the unchanged candidate RTL.
// All three audio outputs must match at exactly the same system clock.
// A third, unretimed original engine measures per-voice onset displacement.
module tb_input_ctrl_diff;
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
  reg signed [7:0] ref_transpose_left_q,ref_transpose_right_q;
  always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin ref_transpose_left_q<=0;ref_transpose_right_q<=0;end
    else begin ref_transpose_left_q<=transpose_left;ref_transpose_right_q<=transpose_right;end
  end
  reg hmi_valid=0,selected_panel=0;
  reg [7:0] hmi_cmd=0; reg [15:0] hmi_value=0;
  wire [31:0] vg[0:1]; wire [255:0] vn[0:1]; wire [95:0] vi[0:1];
  wire [16:0] vol[0:1]; wire [3:0] aa[0:1],dd[0:1],ss[0:1],rr[0:1];
  wire [5:0] active[0:1]; wire tm[0:1],sa[0:1],a3[0:1],a4[0:1],vu[0:1],vd[0:1];
  wire [2:0] il[0:1],ir[0:1]; wire [15:0] ga[0:1],gs[0:1];
  wire [3:0] gd[0:1],gr[0:1]; wire signed [39:0] mix[0:1],pa[0:1],pb[0:1];
  wire [383:0] cv[0:1]; wire [127:0] side[0:1]; wire [119:0] pcm[0:1];
  reg [31:0] ref_gate_q;
  reg [255:0] ref_note_q;
  reg [95:0] ref_inst_q;
  always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      ref_gate_q<=0;ref_inst_q<=0;
      ref_note_q<={2{8'd86,8'd84,8'd83,8'd81,8'd79,8'd77,8'd76,8'd74,
                      8'd72,8'd71,8'd69,8'd67,8'd65,8'd64,8'd62,8'd60}};
    end else begin
      ref_gate_q<=vg[0];ref_note_q<=vn[0];ref_inst_q<=vi[0];
    end
  end
  genvar g;
  generate for(g=0;g<2;g=g+1) begin: paths
    if(g==0) begin: ref_ctrl
      mig_input_ctrl_ref #(.CLK_HZ(20000),.DB_TICKS(2),.GAP_FRAMES(2),.HOLD_FRAMES(8)) controls(
        .clk(clk),.rst_n(rst_n),.frame_tick(frame_tick),
        .keys_left(keys_left),.keys_right(keys_right),.strum_right(strum_right),.strum_left(strum_left),
        .key_up_n(key_up_n),.key_dn_n(key_dn_n),.inst_left_n(inst_left_n),.inst_right_n(inst_right_n),
        .aux3_n(aux3_n),.aux4_n(aux4_n),.test_toggle_n(test_toggle_n),
        .enc_a(enc_a),.enc_b(enc_b),.enc_c_n(enc_c_n),
        .transpose_left(ref_transpose_left_q),.transpose_right(ref_transpose_right_q),
        .hmi_valid(hmi_valid),.hmi_cmd(hmi_cmd),.hmi_value(hmi_value),.selected_panel(selected_panel),
        .voice_gate(vg[g]),.voice_note(vn[g]),.voice_inst(vi[g]),.volume_q16(vol[g]),
        .adsr_a(aa[g]),.adsr_d(dd[g]),.adsr_s(ss[g]),.adsr_r(rr[g]),.active_voices(active[g]),
        .test_mode(tm[g]),.strum_active(sa[g]),.inst_l(il[g]),.inst_r(ir[g]),
        .aux3_stable(a3[g]),.aux4_stable(a4[g]),.volume_up_event(vu[g]),.volume_down_event(vd[g]),
        .guitar_attack(ga[g]),.guitar_sustain(gs[g]),.guitar_decay(gd[g]),.guitar_release(gr[g]));
    end else begin: new_ctrl
      mig_input_ctrl #(.CLK_HZ(20000),.DB_TICKS(2),.GAP_FRAMES(2),.HOLD_FRAMES(8)) controls(
        .clk(clk),.rst_n(rst_n),.frame_tick(frame_tick),
        .keys_left(keys_left),.keys_right(keys_right),.strum_right(strum_right),.strum_left(strum_left),
        .key_up_n(key_up_n),.key_dn_n(key_dn_n),.inst_left_n(inst_left_n),.inst_right_n(inst_right_n),
        .aux3_n(aux3_n),.aux4_n(aux4_n),.test_toggle_n(test_toggle_n),
        .enc_a(enc_a),.enc_b(enc_b),.enc_c_n(enc_c_n),
        .transpose_left(transpose_left),.transpose_right(transpose_right),
        .hmi_valid(hmi_valid),.hmi_cmd(hmi_cmd),.hmi_value(hmi_value),.selected_panel(selected_panel),
        .voice_gate(vg[g]),.voice_note(vn[g]),.voice_inst(vi[g]),.volume_q16(vol[g]),
        .adsr_a(aa[g]),.adsr_d(dd[g]),.adsr_s(ss[g]),.adsr_r(rr[g]),.active_voices(active[g]),
        .test_mode(tm[g]),.strum_active(sa[g]),.inst_l(il[g]),.inst_r(ir[g]),
        .aux3_stable(a3[g]),.aux4_stable(a4[g]),.volume_up_event(vu[g]),.volume_down_event(vd[g]),
        .guitar_attack(ga[g]),.guitar_sustain(gs[g]),.guitar_decay(gd[g]),.guitar_release(gr[g]));
    end
    mig_voice_engine voices(.clk(clk),.rst_n(rst_n),.frame_tick(frame_tick),
      .v_gate(g==0 ? ref_gate_q : vg[g]),
      .v_note(g==0 ? ref_note_q : vn[g]),
      .v_inst(g==0 ? ref_inst_q : vi[g]),.pitch_scale_q16(18'd65536),
      .a_param(aa[g]),.d_param(dd[g]),.s_param(ss[g]),.r_param(rr[g]),
      .guitar_attack(ga[g]),.guitar_sustain(gs[g]),.guitar_decay(gd[g]),.guitar_release(gr[g]),
      .mix_sum(mix[g]),.panel_a_sum(pa[g]),.panel_b_sum(pb[g]));
    assign cv[g]=(g==0) ? {ref_gate_q,ref_note_q,ref_inst_q} : {vg[g],vn[g],vi[g]};
    assign side[g]={vol[g],aa[g],dd[g],ss[g],rr[g],active[g],tm[g],sa[g],il[g],ir[g],
      a3[g],a4[g],vu[g],vd[g],ga[g],gs[g],gd[g],gr[g]};
    assign pcm[g]={mix[g],pa[g],pb[g]};
  end endgenerate

  wire signed [39:0] raw_mix,raw_pa,raw_pb;
  wire [31:0] raw_gate;wire [255:0] raw_note;wire [95:0] raw_inst;
  mig_input_ctrl_ref #(.CLK_HZ(20000),.DB_TICKS(2),.GAP_FRAMES(2),.HOLD_FRAMES(8)) original_controls(
    .clk(clk),.rst_n(rst_n),.frame_tick(frame_tick),
    .keys_left(keys_left),.keys_right(keys_right),.strum_right(strum_right),.strum_left(strum_left),
    .key_up_n(key_up_n),.key_dn_n(key_dn_n),.inst_left_n(inst_left_n),.inst_right_n(inst_right_n),
    .aux3_n(aux3_n),.aux4_n(aux4_n),.test_toggle_n(test_toggle_n),
    .enc_a(enc_a),.enc_b(enc_b),.enc_c_n(enc_c_n),
    .transpose_left(transpose_left),.transpose_right(transpose_right),
    .hmi_valid(hmi_valid),.hmi_cmd(hmi_cmd),.hmi_value(hmi_value),.selected_panel(selected_panel),
    .voice_gate(raw_gate),.voice_note(raw_note),.voice_inst(raw_inst));
  mig_voice_engine original_voices(.clk(clk),.rst_n(rst_n),.frame_tick(frame_tick),
    .v_gate(raw_gate),.v_note(raw_note),.v_inst(raw_inst),.pitch_scale_q16(18'd65536),
    .a_param(aa[0]),.d_param(dd[0]),.s_param(ss[0]),.r_param(rr[0]),
    .guitar_attack(ga[0]),.guitar_sustain(gs[0]),.guitar_decay(gd[0]),.guitar_release(gr[0]),
    .mix_sum(raw_mix),.panel_a_sum(raw_pa),.panel_b_sum(raw_pb));

  // Record gate-on activation in each voice's TDMA slot, not pitch-only
  // restarts while a key remains held. Timbre re-arm is counted when its
  // forced-low gate is subsequently consumed high.
  // Pair events in order per voice, and fail on unmatched events as well.
  integer raw_onset[0:31][0:511],new_onset[0:31][0:511];
  integer raw_count[0:31],new_count[0:31];
  integer m,n,event_pairs=0,onset_unmatched=0,onset_violations=0,max_onset_delta=0;
  integer delta,max_voice=-1,max_event=-1;
  always @(posedge clk) begin
    if(!rst_n) begin
      for(m=0;m<32;m=m+1) begin raw_count[m]=0;new_count[m]=0;end
    end else begin
      if(original_voices.running && !original_voices.guitar_tick_d &&
         original_voices.vidx<32 && original_voices.restart && !original_voices.timbre_change &&
         !original_voices.gate_d[original_voices.vi]) begin
        m=original_voices.vi;
        if(raw_count[m]>=512) $fatal(1,"raw onset buffer overflow");
        raw_onset[m][raw_count[m]]=cycles_checked+1;
        raw_count[m]=raw_count[m]+1;
      end
      if(paths[1].voices.running && !paths[1].voices.guitar_tick_d &&
         paths[1].voices.vidx<32 && paths[1].voices.restart && !paths[1].voices.timbre_change &&
         !paths[1].voices.gate_d[paths[1].voices.vi]) begin
        m=paths[1].voices.vi;
        if(new_count[m]>=512) $fatal(1,"new onset buffer overflow");
        new_onset[m][new_count[m]]=cycles_checked+1;
        new_count[m]=new_count[m]+1;
      end
    end
  end

  integer cycles_checked=0,pcm_mismatches=0,control_mismatches=0,side_mismatches=0;
  integer frame_checks=0,first_pcm_cycle=-1,phase=0;
  reg [119:0] old_pcm_d; reg [383:0] old_cv_d;
  task dump_first_failure;
    integer z,different;
    begin
      $display("FIRST_FAILURE cycle=%0d phase=%0d frame_phase=%0d pcm_ref=%0d,%0d,%0d pcm_new=%0d,%0d,%0d",
        cycles_checked,phase,frame_count,mix[0],pa[0],pb[0],mix[1],pa[1],pb[1]);
      $display("INPUTS rst_n=%b frame_tick=%b keys_left=%h keys_right=%h strum_right=%b strum_left=%b transpose_left=%0d transpose_right=%0d ref_transpose_left_q=%0d ref_transpose_right_q=%0d",
        rst_n,frame_tick,keys_left,keys_right,strum_right,strum_left,transpose_left,transpose_right,ref_transpose_left_q,ref_transpose_right_q);
      $display("INPUTS key_up_n=%b key_dn_n=%b inst_left_n=%b inst_right_n=%b aux3_n=%b aux4_n=%b test_toggle_n=%b enc_a=%b enc_b=%b enc_c_n=%b hmi_valid=%b hmi_cmd=%h hmi_value=%h selected_panel=%b pitch_scale_q16=65536",
        key_up_n,key_dn_n,inst_left_n,inst_right_n,aux3_n,aux4_n,test_toggle_n,enc_a,enc_b,enc_c_n,hmi_valid,hmi_cmd,hmi_value,selected_panel);
      $display("CONTROL_GATE ref=%h new=%h xor=%h",ref_gate_q,vg[1],ref_gate_q^vg[1]);
      $display("CONTROL_NOTE ref=%h new=%h xor=%h",ref_note_q,vn[1],ref_note_q^vn[1]);
      $display("CONTROL_INST ref=%h new=%h xor=%h",ref_inst_q,vi[1],ref_inst_q^vi[1]);
      $display("CONTROL_PARAMS ref=%h new=%h xor=%h",side[0],side[1],side[0]^side[1]);
      different=0;
      for(z=0;z<32;z=z+1) begin
        if({paths[0].voices.phase[z],paths[0].voices.step[z],paths[0].voices.gain[z],
            paths[0].voices.env_st[z],paths[0].voices.div_cnt[z],paths[0].voices.gate_d[z],
            paths[0].voices.note_d[z],paths[0].voices.inst_d[z]} !==
           {paths[1].voices.phase[z],paths[1].voices.step[z],paths[1].voices.gain[z],
            paths[1].voices.env_st[z],paths[1].voices.div_cnt[z],paths[1].voices.gate_d[z],
            paths[1].voices.note_d[z],paths[1].voices.inst_d[z]}) begin
          different=different+1;
          $display("VOICE_DIFF voice=%0d phase=%h/%h step=%h/%h gain=%0d/%0d env_st=%0d/%0d div_cnt=%0d/%0d gate_d=%b/%b note_d=%0d/%0d inst_d=%0d/%0d (ref/new)",z,
            paths[0].voices.phase[z],paths[1].voices.phase[z],paths[0].voices.step[z],paths[1].voices.step[z],
            paths[0].voices.gain[z],paths[1].voices.gain[z],paths[0].voices.env_st[z],paths[1].voices.env_st[z],
            paths[0].voices.div_cnt[z],paths[1].voices.div_cnt[z],paths[0].voices.gate_d[z],paths[1].voices.gate_d[z],
            paths[0].voices.note_d[z],paths[1].voices.note_d[z],paths[0].voices.inst_d[z],paths[1].voices.inst_d[z]);
        end
      end
      $display("VOICE_STATE_DIFFERENT_COUNT=%0d",different);
      $display("SCHEDULER ref/new running=%b/%b vidx=%0d/%0d sum_acc=%0d/%0d acc_a=%0d/%0d acc_b=%0d/%0d rom_gain=%0d/%0d rom_addr=%h/%h",
        paths[0].voices.running,paths[1].voices.running,paths[0].voices.vidx,paths[1].voices.vidx,
        paths[0].voices.sum_acc,paths[1].voices.sum_acc,paths[0].voices.acc_a,paths[1].voices.acc_a,
        paths[0].voices.acc_b,paths[1].voices.acc_b,paths[0].voices.rom_gain,paths[1].voices.rom_gain,
        paths[0].voices.rom_addr,paths[1].voices.rom_addr);
    end
  endtask
  always @(posedge clk) begin
    #1;
    if(rst_n) begin
      cycles_checked=cycles_checked+1;
      if(cycles_checked>8) begin
        if(pcm[1]!==pcm[0]) begin
          if(first_pcm_cycle<0) begin first_pcm_cycle=cycles_checked;dump_first_failure;end
          pcm_mismatches=pcm_mismatches+1;
        end
        if(cv[1]!==cv[0]) begin
          control_mismatches=control_mismatches+1;
        end
        if(side[1]!==side[0]) side_mismatches=side_mismatches+1;
      end
      if(frame_tick) frame_checks=frame_checks+1;
    end
    old_pcm_d=pcm[0]; old_cv_d=cv[0];
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
    keys_left=0;keys_right=0;clocks(12000);
    for(m=0;m<32;m=m+1) begin
      if(raw_count[m]!=new_count[m]) begin
        $display("ONSET_UNMATCHED voice=%0d raw=%0d new=%0d",m,raw_count[m],new_count[m]);
        onset_unmatched=onset_unmatched+1;
      end
      for(n=0;n<raw_count[m] && n<new_count[m];n=n+1) begin
        delta=new_onset[m][n]-raw_onset[m][n];
        if(delta<0)delta=-delta;
        if(delta>max_onset_delta)begin max_onset_delta=delta;max_voice=m;max_event=n;end
        if(delta>1057)onset_violations=onset_violations+1;
        event_pairs=event_pairs+1;
      end
    end
    $display("DIFF_RESULT transpose_delay=1 output_delay=1 cycles=%0d frames=%0d timbres=5 octaves=-4..4 keys=16 chords=1 both_strums=1 physical_test=1 hmi_test=1 pcm_mismatches=%0d control_mismatches=%0d side_mismatches=%0d first_pcm_cycle=%0d",
      cycles_checked,frame_checks,pcm_mismatches,control_mismatches,side_mismatches,first_pcm_cycle);
    $display("ONSET_RESULT pairs=%0d max_clocks=%0d limit=1057 voice=%0d event=%0d unmatched_voices=%0d violations=%0d",
      event_pairs,max_onset_delta,max_voice,max_event,onset_unmatched,onset_violations);
    // Acceptance is exactly the two user-specified criteria; vector and
    // sideband differences above are diagnostics, not extra pass gates.
    if(pcm_mismatches || onset_unmatched || onset_violations || event_pairs==0)
      $fatal(1,"FAIL input_ctrl differential/onset acceptance");
    $display("PASS input_ctrl differential mismatches=0");$finish;
  end
  initial begin #10000000;$fatal(1,"timeout");end
endmodule
