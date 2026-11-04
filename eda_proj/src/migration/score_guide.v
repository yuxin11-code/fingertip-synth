// Guided practice: one timestamp group at a time, with no timed skipping.
// Equal-start notes form a chord. All required keys must be held together,
// with a fresh press for each key after the prompt (including repeated notes).
// The sorted score stream and ESP32 loader format are unchanged.
module score_guide # (parameter integer CLK_HZ=52500000,PART=0)(
 input wire clk,rst_n,score_valid,input wire [15:0] note_count,bpm,ticks_per_beat,
 input wire [31:0] length_ticks,input wire [87:0] ram_data,
 output reg ram_rd,output reg [7:0] ram_addr,
 input wire cmd_valid,input wire [7:0] cmd,input wire [15:0] keys,value,
 output reg active,paused,wait_mode,output reg [1:0] speed,
 output reg [15:0] lane_now,lane_next,lane_hit,lane_miss,
 output reg [15:0] score,combo,output wire [6:0] accuracy,progress,
 output reg [31:0] song_tick,clk_per_tick,window_ticks,
 output wire ready,output reg waiting,output reg completed);
 reg valid_d;
 reg [3:0] config_state;
 reg div_start;reg [35:0] dividend,divisor;
 wire div_done,div_busy;wire [35:0] quotient;
 reg [31:0] base_den;
 serial_divider divider(.clk(clk),.rst_n(rst_n),.start(div_start),.numerator(dividend),.denominator(divisor),.busy(div_busy),.done(div_done),.quotient(quotient));
 assign ready=(score_valid===1'b1 && config_state==0 && clk_per_tick!=0);
 // Metadata changes are accepted only at score_valid rising or speed change.
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin valid_d<=0;config_state<=0;div_start<=0;dividend<=0;divisor<=1;base_den<=1;clk_per_tick<=0;window_ticks<=0;speed<=0;end
  else begin
   valid_d<=score_valid;div_start<=0;
   if((score_valid && !valid_d) || (cmd_valid && (cmd==8'h54 || cmd==8'h56)))begin
    if(cmd_valid && cmd==8'h54)speed<=(speed==2)?0:speed+1'b1;
    if(cmd_valid && cmd==8'h56)speed<=(value>2)?0:value[1:0];
    config_state<=1;
   end else case(config_state)
    1:begin base_den<=bpm*ticks_per_beat;config_state<=2;end
    2:begin
     // 100%,75%,50%: rational LUT factors (1/1,4/3,2/1).
     dividend<=(speed==1)?36'd4*CLK_HZ*60:(speed==2)?36'd2*CLK_HZ*60:36'd1*CLK_HZ*60;
     divisor<=(speed==1)?({4'd0,base_den}<<1)+base_den:base_den;
     config_state<=3;
    end
    3:if(!div_busy)begin div_start<=1;config_state<=4;end
    4:if(div_done)begin clk_per_tick<=(quotient==0)?1:quotient[31:0];config_state<=5;end
    5:begin dividend<=CLK_HZ/10;divisor<=clk_per_tick;config_state<=6;end
    6:if(!div_busy)begin div_start<=1;config_state<=7;end
    7:if(div_done)begin window_ticks<=(quotient==0)?1:quotient[31:0];config_state<=0;end
   endcase
  end
 end
 // MIDI->lane table generated exhaustively: octave folding outside C4..D6,
 // and the nearest white key (lower key on a semitone tie).
 function [3:0] midi_lane;input [6:0] pitch;begin
  case(pitch)
  `include "score_lane_lut.vh"
  endcase
 end endfunction
 reg [31:0] feedback_count;
 reg [15:0] previous_keys,fresh_keys;
 reg [8:0] head,cursor,group_count;
 reg [3:0] scan_state;
 reg [87:0] note;
 reg [15:0] group_mask;
 reg [31:0] group_start;
 reg group_present;
 reg [15:0] hits,misses;
 // End page-exit/value decode in a register before the wide group reset.
 // This adds one sys clock only to game buttons, never to audio or key scans.
 reg start_event,pause_event,stop_event;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin start_event<=0;pause_event<=0;stop_event<=0;end
  else begin
   start_event<=cmd_valid && cmd==8'h50 && ready;
   pause_event<=cmd_valid && cmd==8'h51;
   stop_event<=cmd_valid && cmd==8'h52;
  end
 end
 wire [15:0] note_lane_bit=16'h1<<midi_lane(note[70:64]);
 wire [15:0] fresh_now=fresh_keys|(keys&~previous_keys&group_mask);
 hmi_percent accuracy_calc(.clk(clk),.rst_n(rst_n),.numerator({16'd0,hits}),.denominator({16'd0,hits}+misses),.percent(accuracy));
 hmi_percent progress_calc(.clk(clk),.rst_n(rst_n),.numerator({23'd0,head}),.denominator({16'd0,note_count}),.percent(progress));
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   active<=0;paused<=0;wait_mode<=1;completed<=0;waiting<=0;song_tick<=0;feedback_count<=0;
   lane_now<=0;lane_next<=0;lane_hit<=0;lane_miss<=0;score<=0;combo<=0;hits<=0;misses<=0;
   previous_keys<=0;fresh_keys<=0;head<=0;cursor<=0;group_count<=0;scan_state<=0;note<=0;
   group_mask<=0;group_start<=0;group_present<=0;ram_rd<=0;ram_addr<=0;
  end else begin
   previous_keys<=keys;ram_rd<=0;
   // Old mode-toggle commands cannot re-enable a deadline or skip a note.
   wait_mode<=1;
   if(feedback_count!=0)feedback_count<=feedback_count-1'b1;
   else begin lane_hit<=0;lane_miss<=0;end
   if(active && !paused && ready)begin
    case(scan_state)
     0:begin
      cursor<=head;group_mask<=0;group_count<=0;group_present<=0;
      fresh_keys<=0;lane_now<=0;lane_next<=0;waiting<=1;scan_state<=1;
      if(head>=note_count)begin active<=0;completed<=1;lane_now<=0;lane_next<=0;waiting<=0;end
     end
     1:begin
      if(cursor>=note_count)scan_state<=5;
      else begin ram_addr<=cursor[7:0];ram_rd<=1;scan_state<=2;end
     end
     2:scan_state<=3;
     3:begin note<=ram_data;scan_state<=4;end
     4:begin
      if(group_present && note[31:0]!=group_start)scan_state<=5;
      else begin
       cursor<=cursor+1'b1;
       if(note[87:80]==PART)begin
        group_present<=1;group_start<=note[31:0];
        group_mask<=group_mask|note_lane_bit;group_count<=group_count+1'b1;
       end
       scan_state<=1;
      end
     end
     5:begin
      if(!group_present)begin
       head<=cursor;active<=0;completed<=1;waiting<=0;lane_now<=0;
      end else begin
       lane_now<=group_mask;song_tick<=group_start;fresh_keys<=0;
       waiting<=1;scan_state<=6;
      end
     end
     6:begin
      fresh_keys<=fresh_now;
      // Partial/arpeggiated chords do not pass. Extra wrong keys do not pass.
      // No age limit, timer, duration or speed value changes this predicate.
      if(keys==group_mask && (fresh_now&group_mask)==group_mask)begin
       head<=cursor;waiting<=0;lane_now<=0;lane_hit<=group_mask;
       feedback_count<=CLK_HZ/5;hits<=hits+group_count;
       score<=score+group_count*16'd100;combo<=combo+group_count;
       scan_state<=0;
       if(cursor>=note_count)begin active<=0;completed<=1;end
      end
     end
     default:scan_state<=0;
    endcase
   end
   if(!score_valid)begin active<=0;completed<=0;waiting<=0;lane_now<=0;lane_next<=0;lane_hit<=0;scan_state<=0;fresh_keys<=0;end
   begin
    if(pause_event && active)paused<=~paused;
    if(start_event && ready)begin
     active<=1;paused<=0;completed<=0;waiting<=0;song_tick<=0;
     head<=0;cursor<=0;group_count<=0;group_present<=0;group_mask<=0;scan_state<=0;score<=0;combo<=0;hits<=0;misses<=0;
     fresh_keys<=0;lane_now<=0;lane_next<=0;lane_hit<=0;lane_miss<=0;
    end
    if(stop_event)begin
     active<=0;paused<=0;waiting<=0;scan_state<=0;lane_now<=0;lane_next<=0;lane_hit<=0;fresh_keys<=0;
    end
   end
  end
 end
 // Page exit is handled by the integration wrapper as a STOP command.
endmodule
