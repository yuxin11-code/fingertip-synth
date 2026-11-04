`timescale 1ns/1ps
module tb_game_control;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,cmd_valid=0;reg [7:0] cmd=0;reg [15:0] value=0;
 reg [15:0] keys_left=0,keys_right=0;wire test_mode;reg test_toggle_n=1;wire [31:0] voice_gate;
 wire active,ctrl_valid,ram_rd;wire [7:0] ctrl_cmd,ram_addr;wire [15:0] ctrl_value;
 wire [47:0] lane_frames;wire [15:0] game_score,combo;wire [6:0] accuracy,progress,game_state;
 reg [87:0] ram_data=0;
 always @(posedge clk)if(ram_rd)ram_data<={8'd0,8'd100,8'd62,32'd10,32'd500};
 mig_input_ctrl #(.CLK_HZ(100000),.DB_TICKS(20)) inputs(
  .clk(clk),.rst_n(rst_n),.frame_tick(1'b0),.test_suspend(active),.hmi_valid(ctrl_valid),.hmi_cmd(ctrl_cmd),.hmi_value(ctrl_value),
  .selected_panel(1'b0),.keys_left(keys_left),.keys_right(keys_right),.strum_right(1'b0),.strum_left(1'b0),
  .key_up_n(1'b1),.key_dn_n(1'b1),.inst_left_n(1'b1),.inst_right_n(1'b1),.aux3_n(1'b1),.aux4_n(1'b1),.test_toggle_n(test_toggle_n),
  .enc_a(1'b1),.enc_b(1'b1),.enc_c_n(1'b1),.transpose_left(8'sd0),.transpose_right(8'sd0),.voice_gate(voice_gate),.test_mode(test_mode));
 mig_game_control #(.CLK_HZ(100000)) control(.clk(clk),.rst_n(rst_n),.cmd_valid(cmd_valid),.cmd(cmd),.value(value),.keys_left(keys_left),.keys_right(keys_right),
  .score_valid(1'b1),.note_count(16'd1),.bpm(16'd120),.ticks_per_beat(16'd96),.length_ticks(32'd1000),.ram_data(ram_data),.ram_rd(ram_rd),.ram_addr(ram_addr),
  .active(active),.ctrl_valid(ctrl_valid),.ctrl_cmd(ctrl_cmd),.ctrl_value(ctrl_value),.lane_frames(lane_frames),.game_score(game_score),.combo(combo),.accuracy(accuracy),.progress(progress),.game_state(game_state));
 wire loop_enabled;wire [31:0] duration_ms,elapsed_ms,replay_keys;wire recording,playing,record_led,play_led,full,record_stable,play_stable;wire [5:0] length;
 reg record_n=1,play_n=1;reg [31:0] live_keys=0;
 mig_action_recorder #(.CLK_HZ(100000),.DEPTH(32),.DEBOUNCE_MS(1)) recorder(
  .clk(clk),.rst_n(rst_n),.suspend(active),.record_n(record_n),.play_n(play_n),.live_keys(live_keys),.hmi_valid(cmd_valid),.hmi_cmd(cmd),.hmi_value(value),
  .loop_enabled(loop_enabled),.duration_ms(duration_ms),.elapsed_ms(elapsed_ms),.replay_keys(replay_keys),.record_stable(record_stable),.play_stable(play_stable),.recording(recording),.playing(playing),.record_led(record_led),.play_led(play_led),.full(full),.length(length));
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 task command(input [7:0] c,input [15:0] v);begin @(negedge clk);cmd=c;value=v;cmd_valid=1;cycles(1);cmd_valid=0;cycles(5);end endtask
 integer saved_length,saved_time;
 initial begin
  cycles(10);rst_n=1;cycles(150);command(8'h12,1);command(8'h10,1);live_keys=1;cycles(500);
  if(!recording)$fatal(1,"record start");
  command(8'h50,1);cycles(10);if(!active || !test_mode || voice_gate!=0)$fatal(1,"test not suspended");
  keys_left=1;test_toggle_n=0;cycles(100);if(voice_gate!=1)$fatal(1,"physical touch must sound during game");
  saved_length=length;saved_time=recorder.now_ms;
  live_keys=32'hffff;command(8'h10,0);record_n=0;play_n=0;cycles(500);
  if(length!=saved_length || recorder.now_ms!=saved_time || !recording)$fatal(1,"recorder not frozen");
  command(8'h12,1);if(!test_mode || voice_gate!=1)$fatal(1,"test request not blocked");
  command(8'h06,700);if(control.ctrl_cmd!=8'h06)$fatal(1,"volume path changed");
  command(8'h1f,0);cycles(10);if(active || !test_mode || voice_gate!=32'hffffffff || !recording)$fatal(1,"exit restore");
  record_n=1;play_n=1;test_toggle_n=1;cycles(500);command(8'h10,0);cycles(20);
  if(recording || length<=saved_length)$fatal(1,"record resume");
  command(8'h11,1);cycles(20);if(!playing)$fatal(1,"play start");
  command(8'h50,1);saved_time=recorder.now_ms;cycles(1000);
  if(!playing || recorder.now_ms!=saved_time)$fatal(1,"play pause");
  command(8'h52,1);cycles(20);if(active || !playing || !test_mode)$fatal(1,"play/test restore");
  $display("PASS game entry/exit restore: record+play clock freeze, test suspend/restore, page exit, blocked UI and preserved volume commands");$finish;
 end
 initial begin cycles(10000);$fatal(1,"game control watchdog");end
endmodule
