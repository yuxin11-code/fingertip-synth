`timescale 1ns/1ps
module tb_pluck_mode;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0;reg [3:0] frame_div=0;
 always @(posedge clk)frame_div<=frame_div+1'b1;
 wire frame_tick=(frame_div==0);
 reg hmi_valid=0;reg [7:0] hmi_cmd=0;reg [15:0] hmi_value=0;
 reg selected_panel=0,test_suspend=0;
 reg [15:0] keys_left=0,keys_right=0;
 reg strum_right=0,strum_left=0,key_up_n=1,key_dn_n=1;
 reg inst_left_n=1,inst_right_n=1,aux3_n=1,aux4_n=1,test_toggle_n=1,pluck_toggle_n=1;
 reg enc_a=1,enc_b=1,enc_c_n=1;
 reg signed [7:0] transpose_left=0,transpose_right=0;
 wire [31:0] voice_gate;wire [255:0] voice_note;wire [95:0] voice_inst;
 wire [16:0] volume_q16;wire volume_up_event,volume_down_event;
 wire [3:0] adsr_a,adsr_d,adsr_s,adsr_r,guitar_decay,guitar_release;
 wire [5:0] active_voices;wire test_mode,strum_active,pluck_mode;
 wire [2:0] inst_l,inst_r;wire aux3_stable,aux4_stable;
 wire [15:0] guitar_attack,guitar_sustain;
 mig_input_ctrl #(.CLK_HZ(10000),.DB_TICKS(4),.GAP_FRAMES(2),.HOLD_FRAMES(12)) dut(.*);
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 task command(input [7:0] c,input [15:0] v);begin
  hmi_cmd=c;hmi_value=v;hmi_valid=1;cycles(1);hmi_valid=0;cycles(10);
 end endtask
 task toggle_mode;begin pluck_toggle_n=0;cycles(12);pluck_toggle_n=1;cycles(12);end endtask
 task gesture(input bit descending);begin
  strum_left=descending;strum_right=!descending;cycles(8);strum_left=0;strum_right=0;
 end endtask
 integer timbre,direction,n,rises_l,rises_r,order_l,order_r;
 reg [31:0] previous_gate,seen;
 reg [31:0] rise;
 initial begin
  cycles(5);rst_n=1;cycles(15);
  if(pluck_mode!==0)$fatal(1,"cold start must use direct touch");
  keys_left=1;keys_right=2;cycles(10);
  if(voice_gate!==32'h00020001)$fatal(1,"default direct touch");
  // Bouncing or holding KEY3 cannot create repeated toggles.
  pluck_toggle_n=0;cycles(2);pluck_toggle_n=1;cycles(3);
  if(pluck_mode!==0)$fatal(1,"KEY3 bounce toggled mode");
  pluck_toggle_n=0;cycles(30);if(pluck_mode!==1)$fatal(1,"KEY3 did not enter pluck");
  cycles(100);if(pluck_mode!==1 || voice_gate!==0)$fatal(1,"held KEY3 / held touch retriggered");
  pluck_toggle_n=1;cycles(12);
  keys_left=16'hffff;keys_right=16'hffff;cycles(30);
  if(voice_gate!==0)$fatal(1,"32 held touch keys must remain silent");
  gesture(0);seen=0;
  for(n=0;n<1200;n=n+1)begin cycles(1);seen=seen|voice_gate;end
  if(seen!==32'hffffffff)$fatal(1,"full dual-panel gesture chord missing voices %h",seen);
  keys_left=0;keys_right=0;cycles(300);
  for(timbre=0;timbre<5;timbre=timbre+1)begin
   keys_left=0;keys_right=0;
   command(1,timbre);command(2,timbre);
   for(direction=0;direction<2;direction=direction+1)begin
    keys_left=16'h0005;keys_right=16'h000a;cycles(30);
    if(voice_gate!==0)$fatal(1,"touch sounded in pluck mode timbre=%0d",timbre);
    gesture(direction[0]);previous_gate=voice_gate;seen=0;rises_l=0;rises_r=0;order_l=-1;order_r=-1;
    for(n=0;n<350;n=n+1)begin
     cycles(1);rise=voice_gate & ~previous_gate;previous_gate=voice_gate;seen=seen|voice_gate;
     if(rise[0] || rise[2])begin
      if(rises_l==0)order_l=rise[2]?2:0;
      rises_l=rises_l+1;
     end
     if(rise[17] || rise[19])begin
      if(rises_r==0)order_r=rise[19]?19:17;
      rises_r=rises_r+1;
     end
    end
    if(seen!==32'h000a0005 || rises_l!=2 || rises_r!=2)$fatal(1,"gesture/chord coverage timbre=%0d dir=%0d seen=%h rises=%0d/%0d",timbre,direction,seen,rises_l,rises_r);
    if(order_l!=(direction?2:0) || order_r!=(direction?19:17))$fatal(1,"gesture direction reversed");
    cycles(100);if(voice_gate!==0)$fatal(1,"pluck hold did not expire");
   end
   // A fresh swipe while the previous hold is active must create a low
   // frame and a new rising edge for the same selected voice on BOTH panels.
   keys_left=1;keys_right=1;cycles(10);gesture(0);
   wait(voice_gate[0] && voice_gate[16]);cycles(3);gesture(1);
   n=0;while((voice_gate[0] || voice_gate[16]) && n<100)begin cycles(1);n=n+1;end
   if(n==100)$fatal(1,"same-note swipe failed low frame");
   n=0;while((!voice_gate[0] || !voice_gate[16]) && n<100)begin cycles(1);n=n+1;end
   if(n==100)$fatal(1,"same-note swipe failed restart");
   keys_left=0;keys_right=0;cycles(300);
  end
  key_up_n=0;key_dn_n=0;cycles(30);key_up_n=1;key_dn_n=1;cycles(12);
  if(volume_q16!=32768 || volume_up_event || volume_down_event)$fatal(1,"KEY1/KEY2 still control volume");
  command(8'h12,1);cycles(10);
  if(voice_gate!==32'hffffffff)$fatal(1,"32-voice test mode broken");
  command(8'h12,0);cycles(10);if(voice_gate!==0)$fatal(1,"test left stale gates");
  // Game still receives ordinary direct note gates and restores pluck mode.
  test_suspend=1;keys_left=1;keys_right=1;cycles(15);
  if(voice_gate!==32'h00010001)$fatal(1,"game direct touch disabled");
  test_suspend=0;cycles(15);if(voice_gate!==0)$fatal(1,"pluck mode not restored after game");
  toggle_mode;cycles(10);if(pluck_mode!==0 || voice_gate!==32'h00010001)$fatal(1,"KEY3 direct restore");
  $display("PASS KEY3 pluck mode: debounce/toggle, both panels, five timbres, silent touch, gesture order/chords, same-note retrigger, test/game isolation, KEY1/KEY2 volume disabled");
  $finish;
 end
 initial begin #1000000;$fatal(1,"pluck mode watchdog");end
endmodule
