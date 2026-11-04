`timescale 1ns/1ps
module tb_additive_diff;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,frame_tick=0;
 reg [31:0] v_gate;reg [255:0] v_note;reg [95:0] v_inst;
 reg [17:0] pitch_scale_q16;
 reg [7:0] a_param,d_param,s_param,r_param,guitar_d_param,guitar_r_param;
 wire signed [39:0] mix_sum,panel_a_sum,panel_b_sum;
 wire [9:0] active_osc,observed_voice;wire [5:0] sounding_voices;wire [39:0] env_observe;
 wire busy,ready,sample_valid,deadline_error;
 mig_additive_engine dut(.*);
 reg [449:0] stimulus[0:5199];
 integer f,states,trace,i,j,ret,state_ret,expected_count,mismatches=0,cycles,max_cycles=0;
 integer state_checks=0,sample_checks=0,frame_state_checks;
 integer sf,si;reg [31:0] sp,sa;
 reg signed [39:0] expected_mix,expected_a,expected_b;
 initial begin
  $readmemh("results/additive/stimulus.hex",stimulus);
  f=$fopen("results/additive/expected.txt","r");
  states=$fopen("results/additive/expected_state.txt","r");
  trace=$fopen("results/additive/rtl_samples.txt","w");
  if(f==0 || states==0 || trace==0)$fatal(1,"cannot open differential input/output files");
  state_ret=$fscanf(states,"%d %d %d %d\n",sf,si,sp,sa);
  if(state_ret!=4)$fatal(1,"empty or malformed state oracle");
  repeat(3)@(negedge clk);rst_n=1;
  wait(ready);@(negedge clk);
  for(i=0;i<5200;i=i+1)begin
   frame_state_checks=0;
   {guitar_r_param,guitar_d_param,r_param,s_param,d_param,a_param,pitch_scale_q16,v_inst,v_note,v_gate}=stimulus[i];
   frame_tick=1;@(negedge clk);frame_tick=0;cycles=0;
   // Deliberately corrupt LIVE inputs during the pass. Only the frame snapshot
   // may affect this output; restore them from the next vector next frame.
   v_note=~v_note;v_gate=~v_gate;v_inst=~v_inst;pitch_scale_q16=1;
   a_param=~a_param;d_param=~d_param;s_param=~s_param;r_param=~r_param;
   guitar_d_param=~guitar_d_param;guitar_r_param=~guitar_r_param;
   while(!sample_valid && cycles<650)begin @(negedge clk);cycles=cycles+1;end
   if(cycles>=650 || deadline_error)$fatal(1,"deadline frame=%0d cycles=%0d",i,cycles);
   if(sounding_voices>32 || (active_osc==512 && sounding_voices!=32))
    $fatal(1,"sounding voice count frame=%0d partials=%0d voices=%0d",i,active_osc,sounding_voices);
   if(cycles>max_cycles)max_cycles=cycles;
   ret=$fscanf(f,"%d %d %d %d\n",expected_mix,expected_a,expected_b,expected_count);
   if(ret!=4)$fatal(1,"oracle truncated");
   sample_checks=sample_checks+1;
   if(mix_sum!==expected_mix || panel_a_sum!==expected_a || panel_b_sum!==expected_b || active_osc!==expected_count)begin
    if(mismatches<8)$display("DIFF frame=%0d rtl=%0d/%0d/%0d/%0d expected=%0d/%0d/%0d/%0d",i,mix_sum,panel_a_sum,panel_b_sum,active_osc,expected_mix,expected_a,expected_b,expected_count);
    mismatches=mismatches+1;
   end
   $fwrite(trace,"%0d %0d %0d %0d\n",mix_sum,panel_a_sum,panel_b_sum,active_osc);
   while(state_ret==4 && sf==i)begin
    if(si!=frame_state_checks)$fatal(1,"state RAM index missing, duplicated, or out of order: %0d",si);
    if(dut.oscillator[si]!=={sp,sa})begin
     if(mismatches<8)$display("STATE frame=%0d osc=%0d rtl=%h expected=%h",i,si,dut.oscillator[si],{sp,sa});
     mismatches=mismatches+1;
    end
    state_checks=state_checks+1;
    frame_state_checks=frame_state_checks+1;
    state_ret=$fscanf(states,"%d %d %d %d\n",sf,si,sp,sa);
   end
   if(state_ret==4 && sf<i)$fatal(1,"state oracle is out of order");
   if(state_ret!=4 && state_ret!=-1)$fatal(1,"malformed state oracle");
   case(i)
    0,1,74,75,76,149,749,1699,1700,5199:
     if(frame_state_checks!=512)$fatal(1,"state oracle truncated at frame=%0d checks=%0d",i,frame_state_checks);
    default:if(frame_state_checks!=0)$fatal(1,"unexpected state checkpoint");
   endcase
   // Actual hardware frame has 1057/1058 clocks, enough for parameter settle.
   repeat(1057-cycles-1)@(negedge clk);
  end
  ret=$fscanf(f,"%d %d %d %d\n",expected_mix,expected_a,expected_b,expected_count);
  if(ret!=-1 || state_ret!=-1 || sample_checks!=5200 || state_checks!=5120)
   $fatal(1,"oracle length mismatch samples=%0d states=%0d",sample_checks,state_checks);
  $fclose(f);$fclose(states);$fclose(trace);
  $display("samples=%0d state_checks=%0d mismatches=%0d max_cycles=%0d active_osc=%0d",sample_checks,state_checks,mismatches,max_cycles,active_osc);
  if(mismatches!=0 || active_osc!=512)$fatal(1,"additive differential failed");
  $display("PASS additive differential");$finish;
 end
endmodule
