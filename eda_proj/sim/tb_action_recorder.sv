`timescale 1ns/1ps
module tb_action_recorder;
 wire suspend=0;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,record_n=1,play_n=1;
 reg [31:0] live_keys=0;
 reg hmi_valid=0; reg [7:0] hmi_cmd=0; reg [15:0] hmi_value=0;
 wire [31:0] replay_keys;wire record_stable,play_stable,recording,playing,record_led,play_led,full;
 wire loop_enabled;wire [31:0] duration_ms,elapsed_ms;
 wire [3:0] length;
 mig_action_recorder #(.CLK_HZ(10000),.DEPTH(8)) dut(.*);
 reg lr=1,lp=1;reg [31:0] lk=0;
 wire [31:0] loop_keys;wire loop_playing;
 mig_action_recorder #(.CLK_HZ(10000),.DEPTH(8),.LOOP_PLAYBACK(1)) looping(
  .clk(clk),.rst_n(rst_n),.record_n(lr),.play_n(lp),.live_keys(lk),.replay_keys(loop_keys),
  .hmi_valid(1'b0),.hmi_cmd(8'd0),.hmi_value(16'd0),.loop_enabled(),.duration_ms(),.elapsed_ms(),
  .record_stable(),.play_stable(),.recording(),.playing(loop_playing),.record_led(),.play_led(),.full(),.length());
 integer rp=0,pp=0,seen_first=0,seen_chord=0,seen_release=0,loops=0;
 reg [31:0] previous_replay=0,previous_loop=0;
 always @(negedge clk)begin
  if(dut.record_press)rp=rp+1;
  if(dut.play_press)pp=pp+1;
  if(playing)begin
   if(replay_keys==1)seen_first=1;
   if(replay_keys==32'h80010001)seen_chord=1;
   if(seen_chord && replay_keys==0)seen_release=1;
  end
  if(loop_keys==1 && previous_loop==0)loops=loops+1;
  previous_replay=replay_keys;previous_loop=loop_keys;
 end
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 task ms(input integer n);cycles(n*10);endtask
 task rec_press;begin record_n=0;ms(20);record_n=1;ms(20);end endtask
 task play_press;begin play_n=0;ms(20);play_n=1;ms(20);end endtask
 task reset;
  begin rst_n=0;record_n=1;play_n=1;live_keys=0;lr=1;lp=1;lk=0;cycles(5);rst_n=1;ms(20);end
 endtask
 integer i,n,before_pulses;reg [47:0] saved[0:7];reg [31:0] deadline,started;
 initial begin
  reset;play_press;if(playing || length!=0 || replay_keys!=0)$fatal(1,"empty playback");
  before_pulses=rp;
  repeat(5)begin record_n=0;ms(3);record_n=1;ms(3);end
  if(recording || rp!=before_pulses)$fatal(1,"bounce triggered recorder");
  record_n=0;ms(120);
  if(!recording || length!=1 || rp!=before_pulses+1)$fatal(1,"long hold repeated K3");
  record_n=1;ms(20);
  live_keys=1;ms(25);live_keys=32'h80010001;ms(25);live_keys=0;ms(25);
  rec_press;cycles(3);
  if(recording || length!=5 || !dut.valid)$fatal(1,"manual EOT/length %d",length);
  if(dut.memory[0]!==0 || dut.memory[1][31:0]!=1 || dut.memory[2][31:0]!=32'h80010001 || dut.memory[3][31:0]!=0 || dut.memory[4][31:0]!=0)$fatal(1,"recorded bitmaps/EOT");
  for(i=0;i<5;i=i+1)saved[i]=dut.memory[i];
  live_keys=32'h20;play_press;
  if(!playing || !play_led)$fatal(1,"start playback LED");
  n=0;while(playing && n<5000)begin cycles(1);n=n+1;end
  if(playing || !seen_first || !seen_chord || !seen_release || replay_keys!=0)$fatal(1,"play timing/content/EOT");
  if((live_keys|replay_keys)!=32'h20)$fatal(1,"EOT cancelled live performance");
  for(i=0;i<5;i=i+1)if(saved[i]!==dut.memory[i])$fatal(1,"playback modified recording");
  // Held K4 starts once, then a fresh press stops and releases playback.
  play_n=0;ms(70);if(!playing)$fatal(1,"held K4 repeated stop");
  play_n=1;ms(20);play_n=0;ms(20);
  if(playing || replay_keys!=0)$fatal(1,"manual playback stop stuck notes");
  play_n=1;ms(20);
  // Starting a new take invalidates old contents. Idle simultaneous K3/K4 -> record.
  record_n=0;play_n=0;ms(20);record_n=1;play_n=1;ms(20);
  if(!recording || playing || length!=1 || dut.valid)$fatal(1,"simultaneous commands/new recording");
  for(i=0;i<6;i=i+1)begin live_keys=32'd1<<i;ms(2);end
  ms(3);
  if(recording || !full || length!=8 || dut.memory[7][31:0]!=0 || !dut.valid)$fatal(1,"full must reserve EOT and stop %d",length);
  for(i=0;i<8;i=i+1)saved[i]=dut.memory[i];
  live_keys=32'hffffffff;ms(40);
  for(i=0;i<8;i=i+1)if(saved[i]!==dut.memory[i])$fatal(1,"overflow overwrote RAM");
  // Long timestamp extension keeps the prior note held, rather than clearing it.
  reset;live_keys=32'h80000001;rec_press;
  ms(65540);cycles(3);
  if(length!=2 || dut.memory[1]!=={16'hffff,32'h80000001})$fatal(1,"65s keepalive altered keys %h",dut.memory[1]);
  live_keys=0;ms(5);rec_press;cycles(3);
  if(length!=4 || dut.memory[2][31:0]!=0 || dut.memory[3][31:0]!=0)$fatal(1,"long recording EOT");
  play_press;ms(65480);
  if(!playing || replay_keys!=32'h80000001)$fatal(1,"long wait playback released early");
  ms(200);if(playing || replay_keys!=0)$fatal(1,"long wait EOT stuck");
  // Optional looping has a deliberate 1ms all-off gap, and K4 still stops.
  lk=1;lr=0;ms(20);lr=1;ms(30);lk=0;ms(20);lr=0;ms(20);lr=1;ms(20);
  lp=0;ms(20);lp=1;ms(350);
  if(!loop_playing || loops<3)$fatal(1,"loop playback %d",loops);
  lp=0;ms(20);if(loop_playing || loop_keys!=0)$fatal(1,"stop loop");
  reset;if(length!=0 || dut.valid || replay_keys!=0 || full)$fatal(1,"reset must discard volatile take");
  $display("PASS recorder: two-FF/15ms debounce, bounce/hold/repress, 32-bit chords, timestamp/EOT, live OR, stop/full/no-overwrite, >65s keepalive/playback, optional loops and reset");$finish;
 end
 initial begin #100000000;$fatal(1,"timeout");end
endmodule
