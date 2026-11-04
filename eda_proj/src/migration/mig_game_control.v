// Game owns only the score read port and temporary UI/recorder/test arbitration.
// Timbre, volume, octave, pitch keys and physical touch keep their native path.
module mig_game_control # (parameter integer CLK_HZ=52500000,PART=0,RIGHT_PANEL=0)(
 input wire clk,rst_n,cmd_valid,input wire [7:0] cmd,input wire [15:0] value,
 input wire [15:0] keys_left,keys_right,
 input wire score_valid,input wire [15:0] note_count,bpm,ticks_per_beat,
 input wire [31:0] length_ticks,input wire [87:0] ram_data,
 output wire ram_rd,output wire [7:0] ram_addr,
 output wire active,output wire ctrl_valid,output wire [7:0] ctrl_cmd,
 output wire [15:0] ctrl_value,
 output wire [16*3-1:0] lane_frames,
 output wire [15:0] game_score,combo,output wire [6:0] accuracy,progress,
 output wire [6:0] game_state);
 wire [15:0] now_lanes,next_lanes,hit_lanes,miss_lanes;
 wire paused,wait_mode,ready,waiting,completed;wire [1:0] speed;
 wire [31:0] song_tick,clk_per_tick,window_ticks;
 wire stop_on_exit=cmd_valid && cmd==8'h1f && value!=7;
 score_guide #(.CLK_HZ(CLK_HZ),.PART(PART)) guide(
  .clk(clk),.rst_n(rst_n),.score_valid(score_valid),.note_count(note_count),.bpm(bpm),.ticks_per_beat(ticks_per_beat),.length_ticks(length_ticks),
  .ram_data(ram_data),.ram_rd(ram_rd),.ram_addr(ram_addr),.cmd_valid(cmd_valid),.cmd(stop_on_exit?8'h52:cmd),.value(value),.keys(RIGHT_PANEL?keys_right:keys_left),
  .active(active),.paused(paused),.wait_mode(wait_mode),.speed(speed),.lane_now(now_lanes),.lane_next(next_lanes),.lane_hit(hit_lanes),.lane_miss(miss_lanes),
  .score(game_score),.combo(combo),.accuracy(accuracy),.progress(progress),.song_tick(song_tick),.clk_per_tick(clk_per_tick),.window_ticks(window_ticks),.ready(ready),.waiting(waiting),.completed(completed));
 assign game_state={completed,speed,wait_mode,paused,active,score_valid===1'b1};
 genvar g;
 generate for(g=0;g<16;g=g+1)begin: lamps
  // A repeated/common chord tone must show the NEW prompt immediately,
  // rather than being covered by the preceding 200-ms green hit feedback.
  assign lane_frames[g*3+:3]=now_lanes[g]?3'd2:hit_lanes[g]?3'd3:miss_lanes[g]?3'd4:next_lanes[g]?3'd1:3'd0;
 end endgenerate
 wire blocked=active && (cmd==8'h12 || cmd==8'h30 || cmd==8'h31);
 assign ctrl_valid=cmd_valid && !blocked;
 assign ctrl_cmd=cmd;
 assign ctrl_value=value;
endmodule
