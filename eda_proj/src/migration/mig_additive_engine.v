// 32 voices x 16 partials. One independent phase32/amp32 state per partial.
// Frame: 32 snapshot shift reads + 4 preprocess drain + 512 issues + 13 drain.
// The 512x64 simple-dual-port state RAM is never asynchronously reset.
// Startup/reset scrubs it over 512 clocks, preserving BSRAM inference.
`default_nettype none
module mig_additive_engine(
 input wire clk,rst_n,frame_tick,
 input wire [31:0] v_gate,input wire [255:0] v_note,input wire [95:0] v_inst,
 input wire [17:0] pitch_scale_q16,
 input wire [7:0] a_param,d_param,s_param,r_param,guitar_d_param,guitar_r_param,
 output reg signed [39:0] mix_sum,panel_a_sum,panel_b_sum,
 output reg [9:0] active_osc,
 output reg [5:0] sounding_voices,
 output reg [39:0] env_observe, output wire [9:0] observed_voice,
 output reg busy,output wire ready,output reg sample_valid,
 output reg deadline_error
);
 localparam [31:0] CUTOFF=32'd1477468750; // round(.344 * 2^32)
 localparam [31:0] ACTIVE_THRESHOLD=32'd1076291; // round(10^(-66/20)*2^31)
 localparam [31:0] LFO_STEP=32'd458316;
 // All acoustic tables have synchronous read ports.
 (* rom_style="block" *) reg [31:0] note_rom[0:255];
 (* rom_style="block" *) reg [41:0] harmonic_rom[0:127];
 (* rom_style="block" *) reg [22:0] body_rom[0:1023];
 (* rom_style="block" *) reg [17:0] norm_rom[0:1023];
 (* rom_style="block" *) reg signed [15:0] sine_rom[0:1023];
 (* rom_style="block" *) reg [17:0] vibrato_rom[0:255];
 initial begin
  $readmemh("src/migration/additive_rom/note.hex",note_rom);
  $readmemh("src/migration/additive_rom/harmonic.hex",harmonic_rom);
  $readmemh("src/migration/additive_rom/body.hex",body_rom);
  $readmemh("src/migration/additive_rom/norm.hex",norm_rom);
  $readmemh("src/migration/additive_rom/sine.hex",sine_rom);
  $readmemh("src/migration/additive_rom/vibrato.hex",vibrato_rom);
 end
 (* syn_ramstyle="block_ram" *) reg [63:0] oscillator[0:511];
 // packed: base_step[44:13], note[12:5], inst[4:2], gate[1], restart[0]
 (* syn_ramstyle="block_ram" *) reg [44:0] voice_ram[0:31];
 (* syn_ramstyle="block_ram" *) reg [11:0] history[0:31];
 reg initializing;reg [8:0] clear_addr;
 assign ready=!initializing;
 reg [31:0] gate_sr;reg [255:0] note_sr;reg [95:0] inst_sr;
 reg [17:0] pitch_snap,vibrato_snap;
 reg [7:0] a_snap,d_snap,s_snap,r_snap,gd_snap,gr_snap;
 reg [31:0] lfo_phase;reg [17:0] vibrato_q;
 reg [9:0] cycle;
 wire pre_issue=busy && cycle<32;
 wire osc_issue=busy && cycle>=38 && cycle<550;
 wire [8:0] issue_id=cycle-10'd38;
 reg [3:0] pre_valid;
 reg [4:0] pre_id[0:3];
 reg [11:0] current0,current1,current2;
 reg [11:0] history_q;
 reg [31:0] note_q;
 (* syn_dspstyle="dsp" *) reg [49:0] pitch_product;
 (* syn_dspstyle="dsp" *) reg [49:0] vibrato_product;
 reg restart1,restart2;
 wire [2:0] snapshot_inst=(inst_sr[2:0]<5)?inst_sr[2:0]:3'd0;
 wire [31:0] pitched_step=(|pitch_product[49:48])?32'hffffffff:pitch_product[47:16];
 wire [31:0] vibrated_step=vibrato_product[49]?32'hffffffff:vibrato_product[48:17];
 wire [44:0] voice_write={vibrated_step,current2[10:3],current2[2:0],current2[11],restart2};
 // history word: gate[11], note[10:3], instrument[2:0]
 always @(posedge clk) begin
  vibrato_q<=vibrato_rom[lfo_phase[31:24]];
  if(pre_issue)begin
   note_q<=note_rom[note_sr[7:0]];
   history_q<=history[cycle[4:0]];
  end
  if(initializing && clear_addr<32)history[clear_addr[4:0]]<=0;
  else if(pre_issue) history[cycle[4:0]]<={gate_sr[0],note_sr[7:0],snapshot_inst};
  if(pre_valid[2])voice_ram[pre_id[2]]<=voice_write;
 end

 reg [10:0] valid;
 reg [8:0] cid[0:10];
 reg [44:0] vp[0:7];
 reg [63:0] st[0:7];
 reg [41:0] harmonic_q;
 reg [17:0] norm_q,norm2,norm3;
 reg [22:0] body_q;
 reg [17:0] weight2;
 (* syn_dspstyle="dsp" *) reg [49:0] frequency_product2;
 (* syn_dspstyle="dsp" *) reg [35:0] body_product3;
 (* syn_dspstyle="dsp" *) reg [51:0] normalized_product4;
 reg [36:0] frequency3;
 reg [31:0] increment4,increment5,increment6,increment7;
 reg [31:0] initial5,initial6,initial7;
 (* syn_dspstyle="dsp" *) reg [48:0] sustain_product6;
 reg [4:0] shift3,shift4,shift5,shift6,shift7;
 reg [10:0] muted;
 reg signed [32:0] difference7;
 reg [31:0] phase8,amp8,amp9,amp10;
 reg signed [15:0] sine_q;
 (* syn_dspstyle="dsp" *) reg signed [48:0] sample_product10;
 reg signed [39:0] acc_a,acc_b;
 reg [9:0] active_count;
 reg [5:0] sounding_count;
 reg voice_is_sounding;
 reg finish_pending;
 wire [31:0] voice_step0=vp[0][44:13];
 wire [7:0] note0=vp[0][12:5];
 wire [2:0] inst0=vp[0][4:2];
 wire [7:0] note1=vp[1][12:5];
 wire [2:0] inst1=vp[1][4:2];
 wire [8:0] absolute_note={1'b0,note1}+{3'd0,harmonic_q[41:36]};
 wire [7:0] bounded_note=(absolute_note>191)?8'd191:absolute_note[7:0];
 // k*192 = k*128 + k*64; addresses are registered ROM inputs.
 wire [9:0] norm_address=({7'd0,inst0}<<7)+({7'd0,inst0}<<6)+((note0>191)?8'd191:note0);
 wire [9:0] body_address=({7'd0,inst1}<<7)+({7'd0,inst1}<<6)+bounded_note;
 wire [7:0] selected_d=(vp[2][4:2]==1)?gd_snap:d_snap;
 wire [7:0] selected_r=(vp[2][4:2]==1)?gr_snap:r_snap;
 wire signed [6:0] decay_adjusted=$signed({2'd0,body_q[22:18]})+$signed({5'd0,selected_d[7:6]})-7'sd1;
 wire [4:0] decay_shift=(decay_adjusted<8)?5'd8:((decay_adjusted>22)?5'd22:decay_adjusted[4:0]);
 wire [4:0] release_shift=5'd9+{2'd0,selected_r[7:5]};
 wire [16:0] sustain_factor=(s_snap==255)?17'd65536:(17'd32768+{2'd0,s_snap,7'd0});
 wire [31:0] target6=(vp[6][4:2]==2 && vp[6][1])?sustain_product6[47:16]:32'd0;
 wire signed [32:0] envelope_delta=difference7>>>shift7;
 wire signed [32:0] nonzero_delta=(difference7!=0 && envelope_delta==0)?33'sd1:envelope_delta;
 wire [31:0] next_amplitude=$signed({1'b0,st[7][31:0]})+nonzero_delta;
 wire signed [39:0] partial_sample=sample_product10>>>34;

 // Synchronous simple dual port RAM, independent read and write addresses.
 always @(posedge clk)begin
  if(osc_issue) begin vp[0]<=voice_ram[issue_id[8:4]];st[0]<=oscillator[issue_id];end
  if(initializing) oscillator[clear_addr]<=64'd0;
  else if(valid[8])oscillator[cid[8]]<={phase8,amp8};
  if(valid[0])begin
   harmonic_q<=harmonic_rom[{inst0,cid[0][3:0]}];
   norm_q<=norm_rom[norm_address];
  end
  if(valid[1])body_q<=body_rom[body_address];
  if(valid[8])sine_q<=sine_rom[phase8[31:22]];
 end

 // Read-only monitor: latest onset per panel, full 16-partial amplitude sum.
 // No monitor signal feeds phase, frequency, amplitude or mixer arithmetic.
 reg [4:0] watched_a,watched_b;
 assign observed_voice={watched_b,watched_a};
 reg [35:0] observe_sum,sum_a,sum_b,previous_a,previous_b;
 reg onset_a,onset_b,gate8,gate_a,gate_b;
 reg [2:0] inst8,inst_a,inst_b;
 function [16:0] amplitude_view;
  input [35:0] value;
  begin amplitude_view=(|value[35:31])?17'd65536:{1'b0,value[30:15]}; end
 endfunction
 function [2:0] inferred_stage;
  input [35:0] value,previous; input gate,onset; input [2:0] instrument;
  begin
   if(value==0)inferred_stage=0;
   else if(!gate)inferred_stage=4;
   else if(onset || (instrument==2 && value>previous+36'd64))inferred_stage=1;
   else inferred_stage=(instrument==2)?3'd3:3'd2;
  end
 endfunction
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   watched_a<=0;watched_b<=16;observe_sum<=0;sum_a<=0;sum_b<=0;
   previous_a<=0;previous_b<=0;onset_a<=0;onset_b<=0;
   gate8<=0;gate_a<=0;gate_b<=0;inst8<=0;inst_a<=0;inst_b<=0;env_observe<=0;
  end else begin
   if(frame_tick && !initializing && !busy)begin onset_a<=0;onset_b<=0;end
   if(pre_valid[1] && restart1)begin
    if(pre_id[1][4])begin watched_b<=pre_id[1];onset_b<=1;previous_b<=0;end
    else begin watched_a<=pre_id[1];onset_a<=1;previous_a<=0;end
   end
   if(valid[7])begin gate8<=vp[7][1];inst8<=vp[7][4:2];end
   if(valid[8])begin
    if(cid[8][3:0]==0)observe_sum<={4'd0,amp8};
    else observe_sum<=observe_sum+{4'd0,amp8};
    if(cid[8][3:0]==15)begin
     if(cid[8][8:4]==watched_a)begin sum_a<=observe_sum+{4'd0,amp8};gate_a<=gate8;inst_a<=inst8;end
     if(cid[8][8:4]==watched_b)begin sum_b<=observe_sum+{4'd0,amp8};gate_b<=gate8;inst_b<=inst8;end
    end
   end
   if(finish_pending)begin
    env_observe<={inferred_stage(sum_b,previous_b,gate_b,onset_b,inst_b),amplitude_view(sum_b),
                  inferred_stage(sum_a,previous_a,gate_a,onset_a,inst_a),amplitude_view(sum_a)};
    previous_a<=sum_a;previous_b<=sum_b;
   end
  end
 end

 integer j;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   initializing<=1;clear_addr<=0;busy<=0;cycle<=0;pre_valid<=0;valid<=0;
   gate_sr<=0;note_sr<=0;inst_sr<=0;pitch_snap<=65536;vibrato_snap<=131072;
   a_snap<=0;d_snap<=0;s_snap<=0;r_snap<=0;gd_snap<=0;gr_snap<=0;
   lfo_phase<=0;mix_sum<=0;panel_a_sum<=0;panel_b_sum<=0;active_osc<=0;sounding_voices<=0;
   sample_valid<=0;deadline_error<=0;finish_pending<=0;
   acc_a<=0;acc_b<=0;active_count<=0;sounding_count<=0;voice_is_sounding<=0;muted<=0;
  end else begin
   sample_valid<=0;
   if(initializing)begin
    if(clear_addr==511)initializing<=0;
    else clear_addr<=clear_addr+1'b1;
   end
   if(frame_tick && !initializing)begin
    if(busy)deadline_error<=1;
    else begin
     busy<=1;cycle<=0;gate_sr<=v_gate;note_sr<=v_note;inst_sr<=v_inst;
     pitch_snap<=pitch_scale_q16;vibrato_snap<=vibrato_q;lfo_phase<=lfo_phase+LFO_STEP;
     a_snap<=a_param;d_snap<=d_param;s_snap<=s_param;r_snap<=r_param;
     gd_snap<=guitar_d_param;gr_snap<=guitar_r_param;
     acc_a<=0;acc_b<=0;active_count<=0;sounding_count<=0;voice_is_sounding<=0;
    end
   end
   if(busy)cycle<=cycle+1'b1;
   pre_valid<={pre_valid[2:0],pre_issue};
   if(pre_issue)begin
    current0<={gate_sr[0],note_sr[7:0],snapshot_inst};pre_id[0]<=cycle[4:0];
    gate_sr<={1'b0,gate_sr[31:1]};note_sr<={8'd0,note_sr[255:8]};inst_sr<={3'd0,inst_sr[95:3]};
   end
   if(pre_valid[0])begin
    pitch_product<=note_q*pitch_snap;current1<=current0;pre_id[1]<=pre_id[0];
    restart1<=current0[11] && (!history_q[11] || current0[10:0]!=history_q[10:0]);
   end
   if(pre_valid[1])begin
    vibrato_product<=pitched_step*((current1[2:0]==2)?vibrato_snap:18'd131072);
    current2<=current1;restart2<=restart1;pre_id[2]<=pre_id[1];
   end

   valid<={valid[9:0],osc_issue};cid[0]<=issue_id;
   for(j=1;j<=10;j=j+1)cid[j]<=cid[j-1];
   for(j=1;j<=7;j=j+1)begin vp[j]<=vp[j-1];st[j]<=st[j-1];end
   muted<={muted[9:0],1'b0};
   if(valid[1])begin
    frequency_product2<=vp[1][44:13]*harmonic_q[17:0];
    norm2<=norm_q;weight2<=harmonic_q[35:18];
   end
   if(valid[2])begin
    frequency3<=frequency_product2[49:13];body_product3<=weight2*body_q[17:0];norm3<=norm2;
    if(vp[2][4:2]==2)shift3<=vp[2][1]?(5'd7+{2'd0,a_snap[7:5]}):release_shift;
    else shift3<=vp[2][1]?decay_shift:((decay_shift<release_shift)?decay_shift:release_shift);
   end
   if(valid[3])begin
    normalized_product4<=body_product3[35:2]*norm3;
    increment4<=frequency3[31:0];muted[4]<=frequency3>{5'd0,CUTOFF};shift4<=shift3;
   end
   if(valid[4])begin
    initial5<=normalized_product4[48:17];increment5<=increment4;shift5<=shift4;
   end
   if(valid[5])begin
    sustain_product6<=initial5*sustain_factor;initial6<=initial5;increment6<=increment5;shift6<=shift5;
   end
   if(valid[6])begin
    difference7<=$signed({1'b0,target6})-$signed({1'b0,st[6][31:0]});
    initial7<=initial6;increment7<=increment6;shift7<=shift6;
   end
   if(valid[7])begin
    if(vp[7][4:2]!=2 && vp[7][0])begin amp8<=initial7;phase8<=0;end
    else begin amp8<=next_amplitude;phase8<=st[7][63:32]+increment7;end
   end
   if(valid[8])begin
    amp9<=amp8;
   end
   if(valid[9])begin sample_product10<=sine_q*$signed({1'b0,amp9});amp10<=amp9;end
   if(valid[10])begin
    if(cid[10][3:0]==0)voice_is_sounding<=!muted[10] && amp10>ACTIVE_THRESHOLD;
    else if(!muted[10] && amp10>ACTIVE_THRESHOLD)voice_is_sounding<=1;
    if(cid[10][3:0]==15 && (voice_is_sounding || (!muted[10] && amp10>ACTIVE_THRESHOLD)))
     sounding_count<=sounding_count+1'b1;
    if(!muted[10])begin
     if(cid[10][8])acc_b<=acc_b+partial_sample;else acc_a<=acc_a+partial_sample;
     if(amp10>ACTIVE_THRESHOLD)active_count<=active_count+1'b1;
    end
    if(cid[10]==511)finish_pending<=1;
   end
   if(finish_pending)begin
    panel_a_sum<=acc_a;panel_b_sum<=acc_b;mix_sum<=acc_a+acc_b;active_osc<=active_count;sounding_voices<=sounding_count;
    finish_pending<=0;sample_valid<=1;busy<=0;
   end
  end
 end
endmodule
`default_nettype wire
